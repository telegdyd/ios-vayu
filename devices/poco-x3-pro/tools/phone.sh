#!/bin/bash
# vayu: the test loop over USB, with nobody at the phone (Git Bash on Windows; the phone on the cable).
#
#   phone.sh state            ios (sweetd/command port answer), loader (our loader's USB mode), stock
#                             (vayu's own fastboot), or absent
#   phone.sh loader           from iOS: the command port's "loader" (a flag block in darwin, a reset), then
#                             wait for our loader 2.5 on USB
#   phone.sh flash [IMAGE]    from our loader: write IMAGE (default xnu-standalone.img) into boot
#                             (flash:boot: a boot image only, read back), FLASH_BOOT=yes required
#   phone.sh reboot           from our loader or iOS: restart, then wait for iOS (sweetd)
#   phone.sh deploy [IMAGE]   all of it: iOS -> loader -> flash -> iOS
#   phone.sh sh ARGS...       a command through sweetd (tools/sweet-sh.py)
#   phone.sh log OUT [SECS]   the live kernel log (TCP 5140) into OUT, for SECS (default: until it ends)
#
# In our loader's USB mode, xl works as after "xl enter" (xl run, xl ramdisk, xl log); "fastboot reboot"
# starts the flashed system again. Stock fastboot is only the way back when boot does not start
# (buttons: volume down + power), with the images in ../backup-vayu.
set -uo pipefail
cd "$(dirname "$0")/../../.."
export MSYS_NO_PATHCONV=1
T=devices/poco-x3-pro/tools
PY=${PY:-python}
pause() { $PY -c "import time; time.sleep($1)"; }
is_ios() { $PY $T/sweet-cmd.py ping 2>/dev/null | grep -q pong; }
# (fastboot getvar waits for a device forever when there is none: ask only when "fastboot devices" lists one)
fb_var() {
	fastboot devices 2>/dev/null | grep -q fastboot || return 0
	timeout 10 fastboot getvar "$1" 2>&1 | sed -n "s/^$1: //p" | tr -d '\r'
}
state() {
	if is_ios; then echo ios; return; fi
	case "$(fb_var product)" in
	xnuloader) echo loader ;;
	vayu) echo stock ;;
	*) echo absent ;;
	esac
}
wait_for() {            # wait_for STATE SECONDS
	local t=0
	until [ "$(state)" = "$1" ]; do
		pause 3; t=$((t + 3))
		[ $t -ge "$2" ] && { echo "phone: no $1 in $2 s (now: $(state))" >&2; return 1; }
	done
	echo "phone: $1 (+${t}s)"
}
to_loader() {
	[ "$(state)" = loader ] && return 0
	$PY $T/sweet-cmd.py loader || return 1
	wait_for loader 150
}
flash() {
	local img=${1:-xnu-standalone.img}
	[ "${FLASH_BOOT:-}" = yes ] || { echo "phone: FLASH_BOOT=yes is not set: would write $img into boot" >&2; return 1; }
	[ "$(state)" = loader ] || { echo "phone: not in our loader" >&2; return 1; }
	[ "$(head -c 8 "$img")" = "ANDROID!" ] || { echo "phone: $img is not a boot image" >&2; return 1; }
	echo "phone: flash $img ($(sha256sum "$img" | cut -c1-16))"
	fastboot flash boot "$img" 2>&1 | tail -2
	fastboot oem log >/dev/null 2>&1 && fastboot get_staged logs/phone-loader.log >/dev/null 2>&1
	grep -a "flash: boot: written, read back the same" logs/phone-loader.log >/dev/null ||
		{ echo "phone: the loader did not say the write read back the same (logs/phone-loader.log)" >&2; return 1; }
}
reboot_ios() {
	case "$(state)" in
	loader|stock) fastboot reboot >/dev/null 2>&1 ;;
	ios) $PY $T/sweet-cmd.py reboot ;;
	esac
	pause 10
	wait_for ios 240
}
case "${1:-}" in
state) state ;;
loader) to_loader ;;
flash) flash "${2:-}" ;;
reboot) reboot_ios ;;
deploy) to_loader && flash "${2:-}" && reboot_ios ;;
sh) shift; $PY $T/sweet-sh.py "$@" ;;
log) $PY $T/sweet-netlog.py "$2" ${3:+--for $3} ;;
*) sed -n '2,20p' "$0"; exit 2 ;;
esac
