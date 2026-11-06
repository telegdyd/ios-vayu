#!/bin/bash
# Day 1 on a freshly unlocked vayu, one step at a time, from Git Bash on Windows (the top of the repository).
# Nothing here flashes or writes anything on the phone: the only thing that reaches it is a `fastboot boot`
# (RAM only) and, in a recovery, read-only mounts. Each step checks the phone's state before it acts and can
# be run again.
#
#   day1.sh [status]      where things stand: tools, disk, phone, unlocked, root, backups, firmware, staging
#   day1.sh root IMG      phone in fastboot: boot IMG once from RAM (a vayu recovery, e.g. PBRP/TWRP, is
#                         simplest: adb is root there and no Android setup is needed), wait for a root shell
#   day1.sh backup [DIR]  root shell: copy every partition but userdata/super/cust (~2.5 GB), the logical
#                         vendor and odm, and the GPT ends of every UFS unit to ../backup-vayu/<date>/, each
#                         checked by sha256 against the phone; resumes where it stopped
#   day1.sh firmware      root shell: devices/poco-x3-pro/pull-firmware.sh -> fw-poco-x3-pro/
#   day1.sh image         in WSL: the firmware into ~/vayu, root.apfs rebuilt, everything staged back here
#   day1.sh boot [smoke|baseline]
#                         phone in recovery/Android/fastboot: xl enter, xl ramdisk, one xl run
#                         smoke: text boot, no drivers (60 s); baseline: the device README's args (120 s)
#
# Environment: YES=1 skips the questions; BACKUP_ROOT (default ../backup-vayu); EXCLUDE (default
# "userdata super cust"); LOGICAL (default "vendor odm"); XL_SECS, XL_CMDLINE override boot's.
set -o pipefail
cd "$(dirname "$(readlink -f "$0")")/../../.." || exit 1
. devices/poco-x3-pro/tools/adbroot.sh
export DEVICE=poco-x3-pro
BACKUP_ROOT=${BACKUP_ROOT:-../backup-vayu}
EXCLUDE=${EXCLUDE:-userdata super cust}
LOGICAL=${LOGICAL:-vendor odm}
# the partitions that cannot be had again from any ROM: calibration, IMEI/modem NV, device info. First.
CRITICAL="persist persistbak modemst1 modemst2 fsg fsc devinfo"

say() { echo "day1: $*"; }
die() { echo "day1: $*" >&2; exit 1; }
ask() { # ask QUESTION: yes unless YES=1 or the answer is y
	[ -n "$YES" ] && return 0
	local a; read -r -p "day1: $1 [y/N] " a; [ "$a" = y ] || [ "$a" = Y ]
}
fb_var() { fastboot getvar "$1" 2>&1 | tr -d '\r' | sed -n "s/^$1: *//p" | head -1; }
in_fastboot() { fastboot devices 2>/dev/null | grep -q fastboot; }
free_mb() { df -Pm "$1" | awk 'NR == 2 { print $4 }'; }
need_root() {
	adb_detect || die "no phone on adb (it should be in the booted recovery, or Android with su)"
	[ "$ADB_ROOT" != none ] || die "the phone is on adb ($ADB_STATE) but without root: day1.sh root IMG first"
}

status() {
	local t
	for t in adb fastboot python sha256sum wsl; do command -v $t >/dev/null || say "missing tool: $t"; done
	say "free on this disk: $(free_mb .) MB"
	if in_fastboot; then
		say "phone: fastboot (product $(fb_var product), unlocked: $(fb_var unlocked), loader version: $(fb_var version))"
	elif adb_detect; then
		say "phone: adb, $ADB_STATE, root: $ADB_ROOT"
	else
		say "phone: not seen (USB cable, drivers, USB debugging?)"
	fi
	local d
	for d in "$BACKUP_ROOT"/*/; do
		[ -f "$d/SHA256SUMS" ] || continue
		say "backup $d: $(wc -l < "$d/SHA256SUMS") images$( [ -f "$d/DONE" ] && echo ", complete" || echo ", NOT complete")"
	done
	say "firmware: $(ls -1 fw-poco-x3-pro 2>/dev/null | wc -l) files in fw-poco-x3-pro/"
	if [ -f staged.sha256 ]; then
		say "staged: $(wc -l < staged.sha256) files ($(date -r staged.sha256 '+%F %T'))"
		[ -n "$(find fw-poco-x3-pro -newer staged.sha256 2>/dev/null | head -1)" ] && say "  firmware is newer than the staging: day1.sh image"
	else
		say "staged: nothing (day1.sh image)"
	fi
}

root() {
	local img=$1
	[ -f "$img" ] || die "usage: day1.sh root IMAGE (a vayu recovery image; nothing is flashed)"
	in_fastboot || die "the phone is not in fastboot (power + volume down, or: adb reboot bootloader)"
	local product unlocked
	product=$(fb_var product) unlocked=$(fb_var unlocked)
	[ "$product" = vayu ] || [ "$product" = vayu_global ] || die "fastboot reports product '$product', not vayu"
	[ "$product" = xnuloader ] && die "that is our loader, not the phone's fastboot: ./xl reboot first"
	[ "$unlocked" = yes ] || die "the bootloader is not unlocked (unlocked: '$unlocked')"
	say "image: $img, $(stat -c %s "$img") bytes, sha256 $(sha256sum "$img" | cut -d' ' -f1)"
	say "head: $(head -c 8 "$img" | tr -dc 'A-Z!')"
	[ "$(head -c 8 "$img")" = 'ANDROID!' ] || die "$img is not an Android boot image"
	ask "boot it once from RAM with fastboot boot (nothing is written to the phone)?" || die "not booted"
	fastboot boot "$img" 2>&1 | tr -d '\r' | tail -2
	say "waiting for adb (up to 120 s)..."
	local i
	for ((i = 0; i < 60; i++)); do
		adb_detect && [ "$ADB_ROOT" != none ] && { say "root shell: $ADB_STATE, $ADB_ROOT"; return 0; }
		sleep 2
	done
	adb_detect
	die "no root shell (adb state '$ADB_STATE', root '$ADB_ROOT'). A Magisk boot asks on the screen to allow the shell"
}

# backup_one NAME DEVICE DIR: DEVICE copied to DIR/NAME.img, unless a good copy is there already
backup_one() {
	local name=$1 dev=$2 dir=$3 size want have
	if [ -f "$dir/$name.img" ] && grep -q "  $name.img\$" "$dir/SHA256SUMS" 2>/dev/null; then
		echo "  have   $name"; return 0
	fi
	size=$(rline "blockdev --getsize64 $dev 2>/dev/null")
	[[ $size =~ ^[0-9]+$ ]] || { echo "  FAILED $name: no size for $dev"; return 1; }
	want=$(rline "sha256sum $dev 2>/dev/null" | cut -d' ' -f1)
	rsh "dd if=$dev bs=1048576 2>/dev/null" > "$dir/$name.img.part"
	have=$(sha256sum "$dir/$name.img.part" | cut -d' ' -f1)
	if [ "$(stat -c %s "$dir/$name.img.part")" = "$size" ] && [ -n "$want" ] && [ "$want" = "$have" ]; then
		mv "$dir/$name.img.part" "$dir/$name.img"
		echo "$have  $name.img" >> "$dir/SHA256SUMS"
		printf '  ok     %-16s %6d MB\n' "$name" $(( size / 1048576 ))
	else
		echo "  FAILED $name: $(stat -c %s "$dir/$name.img.part") of $size bytes, sha256 ${have:0:12} vs ${want:-unreadable}"
		rm -f "$dir/$name.img.part"
		return 1
	fi
}

backup() {
	need_root
	local dir=${1:-$BACKUP_ROOT/$(date +%Y%m%d)} failed=0 n names total=0 size
	mkdir -p "$dir" || die "cannot make $dir"
	say "backup into $dir (phone in $ADB_STATE, root $ADB_ROOT)"
	mapfile -t names < <(rsh "ls /dev/block/by-name 2>/dev/null" | tr -d '\r' | tr ' ' '\n' | grep -v '^$' | sort)
	[ ${#names[@]} -gt 20 ] || die "the phone lists only ${#names[@]} partitions in /dev/block/by-name"
	# what is to be read, the critical ones first
	local order=() skip=" $EXCLUDE "
	for n in $CRITICAL; do printf '%s\n' "${names[@]}" | grep -qx "$n" && order+=("$n"); done
	for n in "${names[@]}"; do
		[[ $skip == *" $n "* ]] && continue
		# PBRP links the whole UFS units (sda..sdf) into by-name too: they hold everything else (and userdata)
		[[ $n =~ ^sd[a-z]$ ]] && continue
		[[ " ${order[*]} " == *" $n "* ]] || order+=("$n")
	done
	for n in "${order[@]}"; do
		size=$(rline "blockdev --getsize64 /dev/block/by-name/$n 2>/dev/null"); total=$(( total + ${size:-0} ))
	done
	local logical=()
	for n in $LOGICAL; do
		size=$(rline "blockdev --getsize64 /dev/block/mapper/$n 2>/dev/null")
		[[ $size =~ ^[0-9]+$ ]] && { logical+=("$n"); total=$(( total + size )); }
	done
	say "${#order[@]} partitions + logical: ${logical[*]:-none} = $(( total / 1048576 )) MB; free here: $(free_mb "$dir") MB"
	[ "$(free_mb "$dir")" -gt $(( total / 1048576 + 1024 )) ] || die "not enough room for that and 1 GB to spare"
	# the layout, before anything else
	rsh "ls -l /dev/block/by-name 2>/dev/null" | tr -d '\r' > "$dir/by-name.txt"
	rsh "cat /proc/partitions 2>/dev/null" | tr -d '\r' > "$dir/partitions.txt"
	rsh "ls -l /dev/block/mapper 2>/dev/null" | tr -d '\r' > "$dir/mapper.txt"
	# the first and last six 4 KiB blocks of every UFS unit: the GPTs (tools/gpt-plan.py reads these)
	local lun blocks
	for lun in $(rsh "ls /dev/block 2>/dev/null" | tr -d '\r' | tr ' ' '\n' | grep -E '^sd[a-z]$'); do
		size=$(rline "blockdev --getsize64 /dev/block/$lun 2>/dev/null")
		[[ $size =~ ^[0-9]+$ ]] || continue
		blocks=$(( size / 4096 ))
		rsh "dd if=/dev/block/$lun bs=4096 count=6 2>/dev/null" > "$dir/gpt-$lun.head.bin"
		rsh "dd if=/dev/block/$lun bs=4096 skip=$(( blocks - 6 )) count=6 2>/dev/null" > "$dir/gpt-$lun.tail.bin"
		echo "$lun $blocks" >> "$dir/gpt-blocks.txt.part"
	done
	[ -f "$dir/gpt-blocks.txt.part" ] && sort -u "$dir/gpt-blocks.txt.part" > "$dir/gpt-blocks.txt" && rm -f "$dir/gpt-blocks.txt.part"
	say "GPT ends of: $(cut -d' ' -f1 "$dir/gpt-blocks.txt" 2>/dev/null | tr '\n' ' ')"
	for n in "${order[@]}"; do backup_one "$n" "/dev/block/by-name/$n" "$dir" || failed=$((failed + 1)); done
	for n in "${logical[@]}"; do backup_one "logical-$n" "/dev/block/mapper/$n" "$dir" || failed=$((failed + 1)); done
	cat > "$dir/README.txt" <<-EOF
	vayu partition backup, $(date '+%F %T'), phone in $ADB_STATE (root: $ADB_ROOT).
	NAME.img is /dev/block/by-name/NAME read whole; logical-NAME.img is /dev/block/mapper/NAME (in super).
	Every image's sha256 was compared with the same one computed on the phone (SHA256SUMS).
	Not copied: $EXCLUDE.
	persist, modemst1/2, fsg hold this phone's calibration and modem NV (IMEI): they exist nowhere else.
	Keep this directory out of git and somewhere besides this PC. Restoring is a manual, deliberate
	fastboot flash NAME NAME.img per partition: never xbl/abl/devcfg/... without a reason, never an
	older ROM than anti-rollback index 2.
	EOF
	if [ "$failed" = 0 ]; then
		(cd "$dir" && sha256sum -c --quiet SHA256SUMS) && date '+%F %T' > "$dir/DONE" &&
			say "backup complete: $(wc -l < "$dir/SHA256SUMS") images, checked again here"
	else
		say "$failed failed; run day1.sh backup $dir again to retry just those"
		return 1
	fi
}

firmware() {
	need_root
	devices/poco-x3-pro/pull-firmware.sh
}

image() {
	command -v wsl >/dev/null || die "no wsl"
	[ -d fw-poco-x3-pro ] && [ -n "$(ls -A fw-poco-x3-pro)" ] || say "note: fw-poco-x3-pro/ is empty: the image will carry no firmware"
	[ -z "$(git status --porcelain --untracked-files=no)" ] || say "note: uncommitted changes here do not reach WSL (it pulls vayu-dev)"
	local win; win=$(pwd -W)   # C:/Users/...: what wslpath takes
	# The loader takes at most 63 MB per download (getvar max-download-size 0x3f00000) and the run payload is
	# the kernel (16 MB) + root.apfs: the DSP images (modem 74 MB, adsp 14, slpi_vy 7, venus, wlanmdsp ~100 MB)
	# do not fit there. They stay out of root.apfs (FW_BIG; "" keeps everything); hakios_image_file() also
	# finds fw/ in the resident system image (md1), which is where they belong (not done yet).
	MSYS_NO_PATHCONV=1 wsl -d Debian -- bash -s "$win" "${FW_BIG-modem adsp slpi_vy venus wlanmdsp}" <<-'EOF'
	set -e
	cd ~/vayu
	git pull -q win vayu-dev
	WIN=$(wslpath -u "$1")
	rm -rf fw-poco-x3-pro
	[ -d "$WIN/fw-poco-x3-pro" ] && cp -a "$WIN/fw-poco-x3-pro" fw-poco-x3-pro
	for n in $2; do rm -f fw-poco-x3-pro/$n.mdt fw-poco-x3-pro/$n.b[0-9][0-9] fw-poco-x3-pro/$n.mbn; done
	[ -n "$2" ] && echo "day1: WSL: left out of root.apfs (too big for one download): $2"
	echo "day1: WSL: $(ls -1 fw-poco-x3-pro 2>/dev/null | wc -l) firmware files; building root.apfs (log ~/userland-build-day1.log)"
	before=$(stat -c %Y userland/system.apfs)
	DEVICE=poco-x3-pro REST=1 userland/build.sh > ~/userland-build-day1.log 2>&1 || { tail -20 ~/userland-build-day1.log; exit 1; }
	after=$(stat -c %Y userland/system.apfs)
	[ "$before" = "$after" ] && skip=1 || skip=
	SKIP_SYSTEM=$skip devices/poco-x3-pro/tools/stage-windows.sh "$WIN"
	EOF
	local k r
	k=$(stat -c %s xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837 2>/dev/null || echo 0)
	r=$(stat -c %s userland/root.apfs 2>/dev/null || echo 0)
	say "run payload: kernel $((k / 1048576)) MB + root.apfs $((r / 1048576)) MB (the loader takes 63 MB)"
	[ $((k + r)) -lt $((0x3f00000 - 1048576)) ] || say "WARNING: that does not fit one download: xl run will fail"
}

boot() {
	local mode=${1:-smoke} st
	local args secs
	case $mode in
	smoke) args="-v bootcpu=7 cpus=8 fb_threads=6 vtimer_intid=19" secs=60 ;;
	baseline) args="bootcpu=7 cpus=8 fb_threads=6 vtimer_intid=19 touchscreen=1 nvt_qup=1 gpu=1 vayu_gpu=1 vayu_keep=1" secs=120 ;;
	*) die "usage: day1.sh boot [smoke|baseline]" ;;
	esac
	[ -f staged.sha256 ] || die "nothing staged: day1.sh image (or devices/poco-x3-pro/tools/stage-windows.sh in WSL)"
	[ -f userland/system.apfs ] || die "no userland/system.apfs here"
	st=$(./xl state)
	if [ "$st" != loader ] && adb_detect; then
		say "phone in $ADB_STATE: to fastboot"
		adb reboot bootloader
		local i; for ((i = 0; i < 30; i++)); do in_fastboot && break; sleep 2; done
		in_fastboot || die "the phone did not reach fastboot"
	fi
	./xl enter || die "the loader did not come up"
	if [ "$st" != loader ]; then
		./xl ramdisk userland/system.apfs || die "the system image did not go up"
	fi
	XL_SECS=${XL_SECS:-$secs} XL_CMDLINE=${XL_CMDLINE-$args} ./xl run
	local rc=$?
	./xl screenshot "logs/day1-$mode.png" 2>/dev/null
	say "log: logs/last.log ($(wc -l < logs/last.log 2>/dev/null) lines); the phone stays in the loader: ./xl reboot brings Android back"
	return $rc
}

case "${1:-status}" in
status) status ;;
root) root "$2" ;;
backup) backup "$2" ;;
firmware) firmware ;;
image) image ;;
boot) boot "$2" ;;
*) awk 'NR > 1 && /^#/ { print; next } NR > 1 { exit }' "$0"; exit 1 ;;
esac
