#!/bin/bash
# HFS Plus, built into the kernel, on a disk image of its own: userland/src/hfs_test.c as process 1 of a tiny APFS root,
# the volume on a writable virtio disk (virtio_blk=2). Run it twice on the same image to see what the first run wrote
# still there ("boot number 2").
# usage: qemu/run-hfs-test.sh [IMAGE]      (default: a new 256 MB volume in qemu/hfs-test/)
# needs: the kernel built (xnu-build.sh; K= another one), mkfs.hfsplus (hfsprogs) in $PATH or $MKFS, qemu-system-aarch64
# (Debian: qemu-system-arm qemu-efi-aarch64, then QEMU_EFI=/usr/share/AAVMF/AAVMF_CODE.fd QEMU_VARS=/usr/share/AAVMF/AAVMF_VARS.fd)
# From Scion-Project/scion-kernel (qemu/run-hfs-test.sh, userland/src/hfs_test.c).
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
W=qemu/hfs-test
mkdir -p $W/root/dev $W/root/mnt $W/root/sbin
IMG=${1:-$W/hfs.img}
if [ ! -f "$IMG" ]; then
	truncate -s 256M "$IMG"
	"${MKFS:-mkfs.hfsplus}" -s -J -U 0 -G 0 -M 755 -v Data "$IMG" || exit 1
fi
IMG=$(readlink -f "$IMG")       # (qemu/run.sh works from qemu/: the image by its whole path)
. ./xnu-env.sh
xnu-clang -arch arm64 -Os -static -nostdlib -ffreestanding -fno-stack-protector -fno-builtin \
	-Wl,-e,__start -Wl,-pagezero_size,0x100000000 -o $W/root/sbin/launchd userland/src/hfs_test.c || exit 1
python3 tools/apfs/mkapfs.py -o $W/root.apfs Root=$W/root >/dev/null || exit 1
xnuloader/mkpayload.py -o qemu/payload.bin kernel=${K:-xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837} ramdisk=$W/root.apfs \
	--cmdline "cpus=1 debug=0x8 rd=md0 virtio_blk=2" >/dev/null || exit 1
qemu/run.sh 60 -global virtio-mmio.force-legacy=false \
	-drive file="$IMG",format=raw,if=none,id=hd -device virtio-blk-device,drive=hd | grep -a "hfs_test\|^hfs:\|^jnl:\|virtio-blk\|panic("
