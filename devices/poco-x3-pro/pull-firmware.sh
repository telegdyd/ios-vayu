#!/bin/bash
# Pull the phone's own firmware into fw-poco-x3-pro/ at the top of the repository (never committed: it is
# the vendor's). userland/build.sh (DEVICE=poco-x3-pro) copies that directory flat into the image's fw/,
# where the vayu_* drivers look for it. Missing files are told, not fatal.
#
# On the stock vayu ROM adb's shell user cannot read /vendor/firmware or /vendor/firmware_mnt: root is
# needed. Either works (devices/poco-x3-pro/tools/adbroot.sh):
#   - a recovery booted with `fastboot boot` (adb is root there). If the recovery has not mounted them,
#     this mounts vendor (the logical partition in super), modem and bluetooth READ-ONLY under /mnt/fw-*
#     and unmounts them at the end;
#   - Android with su (Magisk).
# Without root it still tries, as before, and says what it could not read.
#
# Every file is checked: its sha256 on the phone against the copy here. The list of what was pulled
# goes to fw-poco-x3-pro.sha256 beside the directory (not inside it: the directory goes into the image).
set -e
cd "$(dirname "$0")/../.."
. devices/poco-x3-pro/tools/adbroot.sh
OUT=${OUT:-fw-poco-x3-pro}
mkdir -p "$OUT"
adb_detect || { echo "pull-firmware.sh: no phone on adb (Android or recovery)"; exit 1; }
echo "pull-firmware.sh: phone in $ADB_STATE, root: $ADB_ROOT"
[ "$ADB_ROOT" = none ] && echo "pull-firmware.sh: no root: on this ROM /vendor/firmware will not be readable"

# where the phone keeps them (the stock ROM's mount points)
VROOT=/vendor VFW=/vendor/firmware MFW=/vendor/firmware_mnt/image BT=/vendor/bt_firmware/image
MOUNTED=
unmount() { local m; for m in $MOUNTED; do rsh "umount $m 2>/dev/null"; done; }
trap unmount EXIT
yes_on_phone() { rsh "$1 && echo yes" | tr -d '\r' | grep -q '^yes$'; }
if [ "$ADB_STATE" = recovery ]; then
	if ! yes_on_phone "test -f $VFW/a630_sqe.fw"; then
		# ext4 with noload: a read-only mount that replays no journal; vendor may also be erofs
		if yes_on_phone "mkdir -p /mnt/fw-vendor && { mount -t ext4 -o ro,noload /dev/block/mapper/vendor /mnt/fw-vendor || mount -t erofs -o ro /dev/block/mapper/vendor /mnt/fw-vendor || mount -o ro /dev/block/mapper/vendor /mnt/fw-vendor; } 2>/dev/null && test -d /mnt/fw-vendor/firmware"; then
			VROOT=/mnt/fw-vendor VFW=/mnt/fw-vendor/firmware MOUNTED="$MOUNTED /mnt/fw-vendor"
		else
			echo "pull-firmware.sh: could not mount vendor read-only (no /dev/block/mapper/vendor?): mount Vendor from the recovery's Mount menu and run again"
		fi
	fi
	if ! yes_on_phone "test -f $MFW/modem.mdt"; then
		if yes_on_phone "mkdir -p /mnt/fw-modem && mount -t vfat -o ro /dev/block/by-name/modem /mnt/fw-modem 2>/dev/null && test -d /mnt/fw-modem/image"; then
			MFW=/mnt/fw-modem/image MOUNTED="$MOUNTED /mnt/fw-modem"
		else
			echo "pull-firmware.sh: could not mount the modem partition read-only"
		fi
	fi
	if ! yes_on_phone "test -d $BT"; then
		if yes_on_phone "mkdir -p /mnt/fw-bt && mount -t vfat -o ro /dev/block/by-name/bluetooth /mnt/fw-bt 2>/dev/null && test -d /mnt/fw-bt/image"; then
			BT=/mnt/fw-bt/image MOUNTED="$MOUNTED /mnt/fw-bt"
		else
			echo "pull-firmware.sh: could not mount the bluetooth partition read-only"
		fi
	fi
fi

declare -A got
pulled=0 failed=0
grab() { # ROOT DEPTH GLOB...: every file under ROOT (DEPTH levels down) whose name matches a GLOB; the first of a name wins
	local root=$1 depth=$2 g p name want have
	shift 2
	for g in "$@"; do
		mapfile -t paths < <(rsh "find $root -maxdepth $depth -type f -name \"$g\" 2>/dev/null" | tr -d '\r')
		for p in "${paths[@]}"; do
			[ -n "$p" ] || continue
			name=${p##*/}
			[ -n "${got[$name]}" ] && continue
			want=$(rline "sha256sum $p 2>/dev/null" | cut -d' ' -f1)
			rsh "cat $p 2>/dev/null" > "$OUT/$name.part"
			have=$(sha256sum "$OUT/$name.part" | cut -d' ' -f1)
			if [ -n "$want" ] && [ "$want" = "$have" ]; then
				mv "$OUT/$name.part" "$OUT/$name"; got[$name]=$p; pulled=$((pulled + 1))
			else
				rm -f "$OUT/$name.part"; failed=$((failed + 1))
				echo "pull-firmware.sh: $p: the copy does not match the phone's (sha256 ${want:-unreadable})"
			fi
		done
	done
}
# GPU: command processor, GMU and the signed zap shader (vayu_adreno.c, "gpu=1 vayu_gpu=1")
grab "$VFW" 1 a630_sqe.fw a640_gmu.bin a640_zap.mdt 'a640_zap.b[0-9][0-9]'
# touch: the Novatek NT36675 is flashless, XNU downloads its firmware at every start (vayu_nvt.c)
grab "$VFW" 1 'j20s_novatek_ts_fw*.bin'
# the DSPs and engines started by vayu_pas.c: audio, modem, sensors (slpi_vy), video (venus), IPA (ipa_fws)
for n in adsp modem slpi_vy venus ipa_fws; do
	grab "$MFW" 1 $n.mdt "$n.b[0-9][0-9]"
	grab "$VFW" 1 $n.mdt "$n.b[0-9][0-9]"
done
# Wi-Fi runs on the modem's DSP: the image the modem asks for over TFTP, the board data, the regulatory
# database (vayu_wifi.c; regdb.bin is optional)
grab "$MFW" 1 wlanmdsp.mbn
grab "$VFW" 3 bdwlan.bin regdb.bin
grab "$MFW" 1 bdwlan.bin regdb.bin             # MIUI 14 keeps the board data on the modem partition
grab "$VROOT" 4 wlanmdsp.mbn bdwlan.bin
# Bluetooth controller firmware (vayu_bt.c): the bluetooth partition, else wherever vendor has it
grab "$BT" 1 'crbtfw*.tlv' 'crnv*.bin'
grab "$VROOT" 4 'crbtfw*.tlv' 'crnv*.bin'
# touch, again: MIUI 14's kernel has the Novatek images built in (no file anywhere on vendor/odm/modem).
# Read boot (checked by sha256) and take them out of its kernel (tools/nvt-fw.py).
if ! ls "$OUT"/j20s_novatek_ts_fw0*.bin >/dev/null 2>&1; then
	PY=
	for p in python3 python "py -3"; do
		$p -c 'import sys; sys.exit(sys.version_info[0] != 3)' >/dev/null 2>&1 && { PY=$p; break; }
	done
	tmp=$(mktemp -d)
	want=$(rline "sha256sum /dev/block/by-name/boot 2>/dev/null" | cut -d' ' -f1)
	rsh "cat /dev/block/by-name/boot 2>/dev/null" > "$tmp/boot.img"
	if [ -z "$PY" ]; then
		echo "pull-firmware.sh: no Python 3 for tools/nvt-fw.py (touch firmware)"
	elif [ -n "$want" ] && [ "$want" = "$(sha256sum "$tmp/boot.img" | cut -d' ' -f1)" ] &&
		$PY -I devices/poco-x3-pro/tools/nvt-fw.py "$(cygpath -w "$tmp" 2>/dev/null || echo "$tmp")/boot.img" \
		    "$(cygpath -w "$tmp" 2>/dev/null || echo "$tmp")/nvt"; then
		cp "$tmp"/nvt/j20s_novatek_ts_fw0*.bin "$OUT"/ && pulled=$((pulled + $(ls "$tmp"/nvt/j20s_novatek_ts_fw0*.bin | wc -l)))
	else
		echo "pull-firmware.sh: the touch firmware is not in boot's kernel either (or boot could not be read)"
		failed=$((failed + 1))
	fi
	rm -rf "$tmp"
fi

(cd "$OUT" && sha256sum -- *) > "$OUT.sha256" 2>/dev/null || true
echo "pull-firmware.sh: $pulled pulled, $failed failed; $OUT: $(ls -1 "$OUT" | wc -l | tr -d ' ') files (list: $OUT.sha256)"
missing=
for f in a630_sqe.fw a640_gmu.bin a640_zap.mdt j20s_novatek_ts_fw01.bin adsp.mdt modem.mdt slpi_vy.mdt wlanmdsp.mbn bdwlan.bin; do
	[ -s "$OUT/$f" ] || missing="$missing $f"
done
ls "$OUT"/crbtfw*.tlv >/dev/null 2>&1 || missing="$missing crbtfw*.tlv"
[ -z "$missing" ] && echo "pull-firmware.sh: everything the drivers need is there" ||
	echo "pull-firmware.sh: still missing:$missing"
echo "pull-firmware.sh: the camera tables (fw/camera-*.tab) are made from the sensor modules with devices/poco-x3-pro/tools/camtab.py"
[ -z "$missing" ] && [ "$failed" = 0 ]
