#!/bin/bash
# Run in the WSL build checkout (~/vayu): copy what ./xl needs into the Windows checkout, from which Git Bash
# drives the phone (adb and fastboot are Windows programs there). Copies, to the paths xl looks at:
#   the kernel           -> xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837
#   the loader           -> xnuloader/loader.efi
#   the UEFI pieces      -> devices/poco-x3-pro/prebuilt/ (BootShim.bin for vayu's FD_BASE, SILICIUM_UEFI.fd,
#                           ramdisk, mkbootimg.py): mkxnuimg.py builds xnu-usb.img from them, as Windows has
#                           no Mu-Silicium tree and cannot make BootShim (git-ignored: the FD holds vendor code)
#   the images           -> userland/root.apfs, userland/system.apfs (SKIP_SYSTEM=1 leaves system.apfs, 2.5 GB)
# and writes staged.sha256 there. Before copying it builds a USB boot image here and checks it with
# verify-bootimg.py, which is also what makes BootShim.bin for vayu (mkxnuimg.py rebuilds it per FD_BASE).
#
#   devices/poco-x3-pro/tools/stage-windows.sh [WINDOWS_CHECKOUT]   (default: the "win" git remote)
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/../../.."
WIN=${1:-$(git remote get-url win)}
[ -f "$WIN/xl" ] || { echo "stage: $WIN is not a checkout" >&2; exit 1; }
export DEVICE=poco-x3-pro
K=xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837
MU=Mu-Silicium
FD=$MU/Build/vayuPkg/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd
for f in $K xnuloader/loader.efi $FD userland/root.apfs userland/system.apfs; do
	[ -f "$f" ] || { echo "stage: $f missing: build it first (see NOTES.md)" >&2; exit 1; }
done
# root.apfs carries the firmware (userland/build.sh copies ../fw-poco-x3-pro into root/fw): say if it has none
fw=$({ ls -A ../fw-poco-x3-pro 2>/dev/null || true; } | wc -l)
[ "$fw" -gt 0 ] || echo "stage: note: ../fw-poco-x3-pro is empty, so root.apfs carries no firmware" >&2

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
python3 xnuloader/mkpayload.py -o "$tmp/usb-payload.bin" loader.efi=xnuloader/loader.efi --usb --platform vayu >/dev/null
python3 mkxnuimg.py -p "$tmp/usb-payload.bin" -o "$tmp/xnu-usb.img" >/dev/null
python3 devices/poco-x3-pro/uefi/verify-bootimg.py "$tmp/xnu-usb.img" --fd $FD \
	--dtb devices/poco-x3-pro/prebuilt/device-tree.dtb --platform vayu
cmp -s $MU/Resources/DTBs/vayu.dtb devices/poco-x3-pro/prebuilt/device-tree.dtb ||
	{ echo "stage: Mu-Silicium's vayu.dtb differs from devices/poco-x3-pro/prebuilt/device-tree.dtb" >&2; exit 1; }

put() { # put <source> <path in the Windows checkout>: copy unless the same file is already there
	local dst=$WIN/$2
	mkdir -p "$(dirname "$dst")"
	if [ -f "$dst" ] && [ "$(stat -c %s "$1")" = "$(stat -c %s "$dst")" ] && cmp -s "$1" "$dst"; then
		echo "  same   $2"
	else
		cp "$1" "$dst.part" && mv "$dst.part" "$dst" && echo "  copied $2"
	fi
}
P=devices/poco-x3-pro/prebuilt
put $MU/BootShim/BootShim.bin $P/BootShim.bin
put $FD $P/SILICIUM_UEFI.fd
put $MU/Resources/ramdisk $P/ramdisk
put $MU/Resources/Scripts/mkbootimg.py $P/mkbootimg.py
put $K $K
put xnuloader/loader.efi xnuloader/loader.efi
put userland/root.apfs userland/root.apfs
if [ -z "${SKIP_SYSTEM:-}" ]; then
	avail=$(df --output=avail -B1 "$WIN" | tail -1)
	[ "$avail" -gt $(( $(stat -c %s userland/system.apfs) + 4 * 1024 * 1024 * 1024 )) ] ||
		{ echo "stage: less than system.apfs + 4 GB free on the Windows side: not copying it (SKIP_SYSTEM=1 to skip)" >&2; exit 1; }
	put userland/system.apfs userland/system.apfs
fi
files=($P/BootShim.bin $P/SILICIUM_UEFI.fd $P/ramdisk $P/mkbootimg.py $K xnuloader/loader.efi userland/root.apfs)
[ -n "${SKIP_SYSTEM:-}" ] || files+=(userland/system.apfs)
(cd "$WIN" && sha256sum "${files[@]}") > "$WIN/staged.sha256"
(cd "$WIN" && sha256sum -c --quiet staged.sha256) && echo "stage: done, checksums in $WIN/staged.sha256"
