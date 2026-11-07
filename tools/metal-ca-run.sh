#!/bin/bash
# Task 11 on the phone, from Git Bash, with no reflash: the window server (backboardd) on the plug-in that
# tools/metal-ca-build.sh made, or back on the image's.
#
#   tools/metal-ca-run.sh on NAME [SECONDS]   upload userland/obj/task11 to /private/var/tmp/task11, name backboardd in
#                                             /private/var/tmp/HakiosMetal.clients, insert ca.dylib into backboardd
#                                             (kern.exec_inject), restart backboardd (SpringBoard follows), and record
#                                             the console for SECONDS (default 60) into logs/metal-step11/NAME.log
#   tools/metal-ca-run.sh off NAME [SECONDS]  the sysctl as the image set it, the clients file removed, backboardd
#                                             restarted: GL again
#
# Everything it changes is in RAM or /private/var/tmp (emptied at boot): a reboot is the image's GL window server.
# Nothing here reboots the phone or writes a partition.
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
WHAT=${1:?on or off}
NAME=${2:?name}
SECS=${3:-60}
PY=${PY:-python}
S="$PY devices/poco-x3-pro/tools/sweet-sh.py"
O=userland/obj/task11
D=/private/var/tmp/task11
L=logs/metal-step11
LIB=/var/tmp/ca.dylib           # short: kern.exec_inject holds 511 bytes and the image's line is ~485
mkdir -p "$L"

inject=$($S sysctl kern.exec_inject | sed -n 's/^kern.exec_inject: //p')
[ -f "$L/exec_inject.orig" ] || { [ -n "$inject" ] && printf '%s' "$inject" > "$L/exec_inject.orig"; }
orig=$(cat "$L/exec_inject.orig")
case "$WHAT" in
on)
	$S mkdir $D >/dev/null 2>&1
	$S mkdir $D/HakiosMetal.bundle >/dev/null 2>&1
	for f in metal_test HakiosMetal.bundle/HakiosMetal HakiosMetal.bundle/Info.plist; do
		$S rm "/private/var/tmp/task11/${f:?}" >/dev/null 2>&1
		$S --put "$O/$f" "$D/$f" >/dev/null || { echo "upload of $f failed"; exit 1; }
	done
	$S rm /private/var/tmp/ca.dylib >/dev/null 2>&1
	$S --put "$O/ca.dylib" /private/var/tmp/ca.dylib >/dev/null || { echo "upload of ca.dylib failed"; exit 1; }
	printf 'backboardd\n%s' "${CLIENTS:-}" | tr ' ' '\n' > "$L/clients"
	$S --put "$L/clients" /private/var/tmp/HakiosMetal.clients 644 >/dev/null
	# nfcd's group gives way for ours (nfcd is not restarted meanwhile; the image's line comes back with `off` or a boot)
	new=$(printf '%s' "$orig" | sed 's#;/redwood/lib/libnfcrestore.dylib nfcd##');
	new="$new;$LIB backboardd"
	$S $D/metal_test sysctl kern.exec_inject "$new" || exit 1
	;;
off)
	$S rm /private/var/tmp/HakiosMetal.clients >/dev/null 2>&1
	[ -n "$orig" ] && $S $D/metal_test sysctl kern.exec_inject "$orig"
	;;
*)
	echo "on or off"; exit 2;;
esac
$PY devices/poco-x3-pro/tools/sweet-netlog.py "$L/$NAME.log" --for "$SECS" >/dev/null 2>&1 &
LOGGER=$!
$PY -c "import time; time.sleep(3)"
bb=$($S /bin/ps -A -o pid,comm | awk '/\/backboardd$/ {print $1}')
sb=$($S /bin/ps -A -o pid,comm | awk '/\/SpringBoard$/ {print $1}')
echo "backboardd $bb, SpringBoard $sb: restarting backboardd"
$S kill -9 "$bb"
wait $LOGGER
echo "after: $($S /bin/ps -A -o pid,comm | grep -E '/(backboardd|SpringBoard)$' | tr '\n' ' ')"
grep -a -E "metal_ca_try|HakiosMetal|is shown the device|is not shown|backboardd.*(Metal|OpenGL|GL)" "$L/$NAME.log" | tail -40
