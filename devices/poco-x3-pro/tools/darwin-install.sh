#!/bin/bash
# vayu: the port's darwin partition, from a recovery booted with `fastboot boot` (PBRP; adb is root), run in WSL
# where the images are (adb.exe is Windows' own, reached through WSL's interop).
#
#   darwin-install.sh check                   darwin's identity on the phone, now                    (writes nothing)
#   darwin-install.sh gpt HEAD TAIL OLDHEAD OLDTAIL
#                                             LUN 0's partition table: the phone's must still be OLDHEAD/OLDTAIL
#                                             (the backup), then HEAD's blocks 1..5 and TAIL's 0..5 are written,
#                                             each copy table first, and read back (gpt-plan.py retype makes them)
#   darwin-install.sh write IMAGE BLOCK       IMAGE into darwin at its block BLOCK, read back by sha256
#   darwin-install.sh sum BLOCK BYTES         sha256 of BYTES of darwin from BLOCK                    (writes nothing)
#   darwin-install.sh var IMAGE               the data volume (HFS Plus, var-volume.sh makes it) into darwin's
#                                             blocks VAR_FIRST.. (/dev/ufs_var: ufs_var_first=, ufs_var_blocks=):
#                                             only what mkfs wrote (the sparse file's data), each piece read back
#
# Every write needs DARWIN_WRITE=yes. What `write` may reach: darwin as it was set up (entry 32 of sda, its GPT
# entry with both GUIDs and LBAs, sysfs and blockdev agreeing), only blocks below 2097152 (where the phone's own
# writes begin, xnuloader darwin_vayu.write_first) and only by dd into /dev/block/sda32 by name, checked again
# right before. The layout is redwood's (docs/ru/notes.md, "Криптексы на флеше"): rootfs.apfs at 0, the OS cryptex
# at 1374208, the App cryptex at 2039808. Every attempt goes into logs/darwin-install.log of the Windows checkout.
set -o pipefail
ADB=${ADB:-adb.exe}
PART=32 NODE=/dev/block/sda32 DEV=/dev/block/by-name/darwin
FIRST=2851328 LAST=62162938 BS=4096
BLOCKS=$((LAST - FIRST + 1))
LIMIT=2097152
# the data volume: past var_store's two slots of 2 GiB (2097152..3145727), 8 GiB (the kernel's ufs_var_first/blocks)
VAR_FIRST=3145728 VAR_BLOCKS=2097152
TYPE=7C3457EF-0000-11AA-AA11-00306543ECAC UNIQ=1756C529-8738-41C3-BA3A-8F263332C072
LUNBLOCKS=62162944
HERE=$(cd "$(dirname "$0")/../../.." && pwd)
LOG=$HERE/logs/darwin-install.log
mkdir -p "$HERE/logs"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; echo "darwin-install: $*"; }
die() { log "REFUSED: $*"; exit 1; }
sh_phone() { "$ADB" shell "$1" | tr -d '\r'; }

state() { "$ADB" get-state 2>/dev/null | tr -d '\r'; }

# the GPT entry, read from the phone's LUN 0 now and parsed here
gpt_entry() {
	"$ADB" exec-out "dd if=/dev/block/sda bs=$BS skip=1 count=2 2>/dev/null" | python3 -I -c '
import sys, struct, zlib, uuid
raw = sys.stdin.buffer.read(); BS = 4096
h = raw[:BS]
if h[:8] != b"EFI PART": sys.exit("no GPT header")
size, crc = struct.unpack_from("<II", h, 12)
hh = bytearray(h[:size]); hh[16:20] = bytes(4)
if zlib.crc32(hh) & 0xffffffff != crc: sys.exit("GPT header CRC wrong")
lba, n, es, tcrc = struct.unpack_from("<QIII", h, 72)
t = raw[BS:BS + n * es]
if lba != 2 or zlib.crc32(t) & 0xffffffff != tcrc: sys.exit("GPT table wrong")
p = int(sys.argv[1]); e = t[(p - 1) * es:p * es]
f, l = struct.unpack_from("<QQ", e, 32)
name = e[56:128].decode("utf-16-le").split("\0")[0]
over = [i + 1 for i in range(n) if i + 1 != p and t[i*es:i*es+16] != bytes(16) and
        struct.unpack_from("<Q", t, i*es+32)[0] <= l and struct.unpack_from("<Q", t, i*es+40)[0] >= f]
print(name, str(uuid.UUID(bytes_le=e[:16])).upper(), str(uuid.UUID(bytes_le=e[16:32])).upper(), f, l, len(over))
' $PART
}

check() {
	[ "$(state)" = recovery ] || die "the phone is not in the recovery (adb: $(state))"
	[ "$(sh_phone "id -u")" = 0 ] || die "adb is not root"
	local g want facts
	g=$(gpt_entry) || die "GPT: $g"
	want="darwin $TYPE $UNIQ $FIRST $LAST 0"
	[ "$g" = "$want" ] || die "GPT entry $PART is '$g', not '$want'"
	facts=$(sh_phone "readlink -f $DEV; cat /sys/class/block/sda$PART/partition /sys/class/block/sda$PART/start /sys/class/block/sda$PART/size; grep ^PARTNAME= /sys/class/block/sda$PART/uevent; blockdev --getsize64 $NODE; blockdev --getss /dev/block/sda" | tr '\n' ' ')
	want="$NODE $PART $((FIRST * 8)) $((BLOCKS * 8)) PARTNAME=darwin $((BLOCKS * BS)) $BS "
	[ "$facts" = "$want" ] || die "the phone's view of darwin is '$facts', not '$want'"
	log "check: darwin is entry $PART of sda, LBA $FIRST..$LAST, $((BLOCKS * BS >> 30)) GiB, as set up"
}

sum() { # sum BLOCK BYTES: sha256 on the phone, after dropping its caches
	sh_phone "echo 3 > /proc/sys/vm/drop_caches; dd if=$NODE bs=1048576 skip=$(($1 / 256)) count=$((($2 + 1048575) / 1048576)) 2>/dev/null | head -c $2 | sha256sum" | cut -d' ' -f1
}

write() {
	local img=$1 block=$2 bytes have want
	[ -f "$img" ] || die "no $img"
	bytes=$(stat -c %s "$img")
	[ $((block % 256)) = 0 ] || die "block $block is not a whole MiB"
	[ $((bytes % BS)) = 0 ] || die "$img is not whole blocks"
	[ $((block + bytes / BS)) -le $LIMIT ] || die "$img at $block would pass block $LIMIT (the phone's own writes)"
	[ "$DARWIN_WRITE" = yes ] || die "DARWIN_WRITE=yes is not set: would write $img ($bytes bytes) at block $block"
	check
	want=$(sha256sum "$img" | cut -d' ' -f1)
	log "write: $img, $bytes bytes, sha256 $want, at block $block"
	local t0=$(date +%s)
	"$ADB" exec-in "[ \"\$(readlink -f $DEV)\" = $NODE ] && [ \"\$(blockdev --getsize64 $NODE)\" = $((BLOCKS * BS)) ] && dd of=$NODE bs=1048576 seek=$((block / 256)) conv=notrunc,fsync 2>/dev/null" < "$img" ||
		die "the write did not finish"
	local dt=$(( $(date +%s) - t0 + 1 ))
	have=$(sum "$block" "$bytes")
	[ "$have" = "$want" ] || die "read back $have, not $want"
	log "write: done in $dt s ($((bytes / 1048576 / dt)) MB/s), read back the same"
}

# The data volume: an HFS Plus image as a sparse file, the size of the slice. What mkfs left as holes is free space
# (HFS Plus never reads it as anything until it has written it), so only the file's data is written, piece by piece.
var() {
	local img=$1 bytes pieces n=0 total=0 have want
	[ -f "$img" ] || die "no $img"
	bytes=$(stat -c %s "$img")
	[ "$bytes" = $((VAR_BLOCKS * BS)) ] || die "$img is $bytes bytes, not the slice's $((VAR_BLOCKS * BS))"
	case "$(dd if="$img" bs=1 skip=1024 count=2 2>/dev/null)" in H+|HX) ;; *) die "$img is not an HFS Plus volume" ;; esac
	[ $((VAR_FIRST)) -ge $LIMIT ] || die "VAR_FIRST $VAR_FIRST is below $LIMIT"
	[ $((VAR_FIRST + VAR_BLOCKS)) -le $BLOCKS ] || die "the slice does not fit in darwin"
	pieces=$(python3 -I -c '
import os, sys
fd = os.open(sys.argv[1], os.O_RDONLY); end = os.fstat(fd).st_size; at = 0
while at < end:
    try: d = os.lseek(fd, at, os.SEEK_DATA)
    except OSError: break
    h = os.lseek(fd, d, os.SEEK_HOLE)
    a, b = d // 4096, (h + 4095) // 4096
    print(a, b - a); at = h
' "$img") || die "could not find the image's data"
	while read -r a c; do total=$((total + c)); done <<< "$pieces"
	[ "$DARWIN_WRITE" = yes ] || die "DARWIN_WRITE=yes is not set: would write $(wc -l <<< "$pieces") pieces, $((total * BS >> 20)) MB, of $img into darwin's blocks $VAR_FIRST..$((VAR_FIRST + VAR_BLOCKS - 1))"
	check
	log "var: $img: $(wc -l <<< "$pieces") pieces, $((total * BS)) bytes, into darwin's blocks $VAR_FIRST..$((VAR_FIRST + VAR_BLOCKS - 1))"
	while read -r a c; do
		n=$((n + 1))
		dd if="$img" bs=$BS skip=$a count=$c 2>/dev/null | "$ADB" exec-in "[ \"\$(readlink -f $DEV)\" = $NODE ] && [ \"\$(blockdev --getsize64 $NODE)\" = $((BLOCKS * BS)) ] && dd of=$NODE bs=$BS seek=$((VAR_FIRST + a)) conv=notrunc,fsync 2>/dev/null" ||
			die "piece $n (blocks $a+$c) did not finish"
	done <<< "$pieces"
	sh_phone "echo 3 > /proc/sys/vm/drop_caches" >/dev/null
	n=0
	while read -r a c; do
		n=$((n + 1))
		want=$(dd if="$img" bs=$BS skip=$a count=$c 2>/dev/null | sha256sum | cut -d' ' -f1)
		have=$("$ADB" exec-out "dd if=$NODE bs=$BS skip=$((VAR_FIRST + a)) count=$c 2>/dev/null" | sha256sum | cut -d' ' -f1)
		[ "$have" = "$want" ] || die "piece $n (blocks $a+$c) read back $have, not $want"
	done <<< "$pieces"
	log "var: written, every piece read back the same"
}

gpt() {
	local head=$1 tail=$2 ohead=$3 otail=$4 h t
	for f in "$head" "$tail" "$ohead" "$otail"; do [ -s "$f" ] || die "no $f"; done
	[ "$(state)" = recovery ] || die "the phone is not in the recovery"
	[ "$(sh_phone "blockdev --getsize64 /dev/block/sda")" = $((LUNBLOCKS * BS)) ] || die "sda is not the unit it was"
	# compared: LUN 0's blocks 0..5 and its last 5 (the tail dump's block 0 is the partition's data)
	h=$("$ADB" exec-out "dd if=/dev/block/sda bs=$BS count=6 2>/dev/null" | sha256sum | cut -d' ' -f1)
	t=$("$ADB" exec-out "dd if=/dev/block/sda bs=$BS skip=$((LUNBLOCKS - 5)) count=5 2>/dev/null" | sha256sum | cut -d' ' -f1)
	tsum() { dd if="$1" bs=$BS skip=1 count=5 2>/dev/null | sha256sum | cut -d' ' -f1; }
	if [ "$h" = "$(sha256sum < "$head" | cut -d' ' -f1)" ] && [ "$t" = "$(tsum "$tail")" ]; then
		log "gpt: the phone has the new table already"; return 0
	fi
	[ "$h" = "$(sha256sum < "$ohead" | cut -d' ' -f1)" ] || die "LUN 0's first blocks are not the backup's"
	[ "$t" = "$(tsum "$otail")" ] || die "LUN 0's last blocks are not the backup's"
	[ "$DARWIN_WRITE" = yes ] || die "DARWIN_WRITE=yes is not set: would write LUN 0's partition table"
	log "gpt: writing $head and $tail (the phone's were the backup's)"
	# each copy: its table, then its header (a header always describes a table that is already there)
	dd if="$head" bs=$BS skip=2 count=4 2>/dev/null | "$ADB" exec-in "dd of=/dev/block/sda bs=$BS seek=2 conv=notrunc,fsync 2>/dev/null" || die "primary table"
	dd if="$head" bs=$BS skip=1 count=1 2>/dev/null | "$ADB" exec-in "dd of=/dev/block/sda bs=$BS seek=1 conv=notrunc,fsync 2>/dev/null" || die "primary header"
	# (TAIL's block 0 is the last block of the partition before the table: data, not written)
	dd if="$tail" bs=$BS skip=1 count=4 2>/dev/null | "$ADB" exec-in "dd of=/dev/block/sda bs=$BS seek=$((LUNBLOCKS - 5)) conv=notrunc,fsync 2>/dev/null" || die "backup table"
	dd if="$tail" bs=$BS skip=5 count=1 2>/dev/null | "$ADB" exec-in "dd of=/dev/block/sda bs=$BS seek=$((LUNBLOCKS - 1)) conv=notrunc,fsync 2>/dev/null" || die "backup header"
	sh_phone "echo 3 > /proc/sys/vm/drop_caches" >/dev/null
	h=$("$ADB" exec-out "dd if=/dev/block/sda bs=$BS count=6 2>/dev/null" | sha256sum | cut -d' ' -f1)
	t=$("$ADB" exec-out "dd if=/dev/block/sda bs=$BS skip=$((LUNBLOCKS - 5)) count=5 2>/dev/null" | sha256sum | cut -d' ' -f1)
	[ "$h" = "$(sha256sum < "$head" | cut -d' ' -f1)" ] && [ "$t" = "$(tsum "$tail")" ] ||
		die "read back differs: the old table is $ohead/$otail"
	log "gpt: written and read back; the kernel sees it after the recovery is booted again"
}

case $1 in
check) check ;;
sum) [ $# = 3 ] || exit 2; check; sum "$2" "$3" ;;
write) [ $# = 3 ] || exit 2; write "$2" "$3" ;;
gpt) [ $# = 5 ] || exit 2; gpt "$2" "$3" "$4" "$5" ;;
var) [ $# = 2 ] || exit 2; var "$2" ;;
*) sed -n '2,23p' "$0"; exit 2 ;;
esac
