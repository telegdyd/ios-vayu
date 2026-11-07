#!/bin/bash
# The phone boots iOS by itself: one Android boot image that carries the loader, the kernel and the two small
# images of the flash boot (userland/flashboot.apfs and userland/root-flash.apfs). The root and the cryptexes
# are on darwin already (darwin-install.sh). The loader (2.2 and later) copies the "resident" image to its
# place, runs the kernel with no time limit (no host is there to end the run) and resets the phone when the
# kernel comes back or hangs; the phone then boots the same image again.
#
# Git Bash, from the checkout's root, phone in fastboot (Xiaomi's: volume down + power):
#   devices/poco-x3-pro/tools/standalone.sh build   make xnu-standalone.img
#   devices/poco-x3-pro/tools/standalone.sh try     build it and start it once from RAM (fastboot boot): nothing written
#   devices/poco-x3-pro/tools/standalone.sh flash   build it and write it into the boot partition (FLASH_BOOT=yes):
#                                                   from then on the phone starts iOS when it is switched on
# Android's own boot image is in the day 1 backup (../backup-vayu/20261106/boot.img): "fastboot flash boot" it
# to undo. Fastboot itself (volume down + power) is Xiaomi's and stays reachable whatever is in boot.
#
# STANDALONE_CMDLINE replaces the kernel arguments (the default: run 225353's, plus /private/var on the flash: HFS Plus
# on /dev/ufs_var, darwin's blocks 3145728.. (8 GiB; var-volume.sh makes it, darwin-install.sh var writes it), written
# as iOS writes; ufs_write=1 lets the kernel write there and nowhere else. The volume's first boot takes in the last
# var_store save. The earlier way, var_store=1 instead of var_hfs=1 and ufs_var_*: a snapshot saved at Shut Down.)
# STANDALONE_EXTRA adds to them.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export DEVICE=poco-x3-pro
PY=${PY:-python}
K=xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837
L=xnuloader/loader.efi
RES=userland/flashboot.apfs
RD=userland/root-flash.apfs
OUT=xnu-standalone.img
BOOT_BYTES=134217728            # the boot partition (the backup's boot.img is this size)
ARGS=${STANDALONE_CMDLINE-root_apfs=ufs_darwin ufs=2 bootcpu=7 cpus=8 fb_threads=6 vtimer_intid=19 touchscreen=1 nvt_qup=1 nvt_fw=1 gpu=1 vayu_gpu=1 vayu_keep=1 ufs_write=1 var_hfs=1 ufs_var_first=3145728 ufs_var_blocks=2097152 vayu_usbnet=3 usb_handover=1 usbnet_static=1 usbnet_ip=0xa9fe0702 battery=1 vayu_wled=2}
LOG=logs/standalone.log
mkdir -p logs
say() { echo "standalone: $*"; echo "$(date '+%F %T') $*" >> $LOG; }
die() { say "REFUSED: $*"; exit 1; }

build() {
	local f
	for f in $K $L $RES $RD; do [ -f $f ] || die "$f missing"; done
	grep -aq 'standalone: resident image' $L || die "$L is older than loader 2.2 (xnuloader/build.sh)"
	$PY xnuloader/mkpayload.py -o standalone-payload.bin loader.efi=$L kernel=$K ramdisk=$RD resident=$RES \
		--platform vayu --cmdline "sb_delay=8 $ARGS${STANDALONE_EXTRA:+ $STANDALONE_EXTRA}" >/dev/null
	local psize; psize=$(stat -c %s standalone-payload.bin)
	[ $psize -le $(( 0x3f00000 )) ] || die "payload is $psize bytes, more than the loader's 0x3f00000"
	$PY mkxnuimg.py -p standalone-payload.bin -o $OUT >/dev/null
	local isize; isize=$(stat -c %s $OUT)
	[ $isize -lt $BOOT_BYTES ] || die "$OUT is $isize bytes, more than the boot partition"
	say "built $OUT: $isize bytes, sha256 $(sha256sum $OUT | cut -c1-16); payload $psize bytes"
	say "  kernel $(sha256sum $K | cut -c1-16)  loader $(sha256sum $L | cut -c1-16)  resident $(sha256sum $RES | cut -c1-16)  ramdisk $(sha256sum $RD | cut -c1-16)"
	say "  cmdline: sb_delay=8 $ARGS${STANDALONE_EXTRA:+ $STANDALONE_EXTRA}"
}

stock_fastboot() {
	fastboot devices 2>/dev/null | grep -q fastboot || die "the phone is not in fastboot"
	fastboot getvar product 2>&1 | grep -q 'product: vayu' || die "this is not vayu's own fastboot (the loader's?)"
}

case ${1:-} in
build) build ;;
try)
	build; stock_fastboot
	say "try: fastboot boot $OUT (RAM only)"
	fastboot boot $OUT 2>&1 | tr -d '\r' | tee -a $LOG
	;;
flash)
	build; stock_fastboot
	[ "${FLASH_BOOT:-}" = yes ] || die "FLASH_BOOT=yes is not set: would write the boot partition"
	[ -f ../backup-vayu/20261106/boot.img ] || die "Android's boot.img is not in ../backup-vayu/20261106 (the undo)"
	say "flash: writing $OUT into boot"
	fastboot flash boot $OUT 2>&1 | tr -d '\r' | tee -a $LOG
	say "flash: done; \"fastboot reboot\" starts it"
	;;
*) sed -n '2,17p' "$0"; exit 1 ;;
esac
