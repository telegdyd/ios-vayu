#!/bin/bash
# Task 10 on the phone, from Git Bash: `tools/metal-layer-run.sh NAME [SECONDS [VAR=VALUE ...]]`.
#
# Uploads what tools/metal-layer-build.sh made (userland/obj/task10) to /private/var/tmp/task10 -- each file removed
# first: the kernel keeps the code signature of a file overwritten in place, and the new one then counts as unsigned --
# records the phone's log meanwhile, runs `metal_test layer` for SECONDS (default 20) with the VAR=VALUE settings
# (LAYER_PLAIN=1: a magenta root layer, the Metal layer its lower half), and judges both with tools/metal-layer-report.py.
# Logs: logs/metal-step10/NAME.{txt,log,json}. Needs SpringBoard to have MetalLayerHost.dylib (install: see
# docs/metal-layer-results.md). Nothing here reboots the phone or writes a partition.
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
NAME=${1:?name}
SECS=${2:-20}
shift $(( $# > 1 ? 2 : 1 ))
PY=${PY:-python}
S="$PY devices/poco-x3-pro/tools/sweet-sh.py"
O=userland/obj/task10
D=/private/var/tmp/task10
L=logs/metal-step10
mkdir -p "$L"
$S mkdir $D >/dev/null 2>&1
for f in metal_test metal_layer_lookup.dylib task10.metallib; do
	$S rm $D/$f >/dev/null 2>&1
	$S --put $O/$f $D/$f >/dev/null || { echo "upload of $f failed"; exit 1; }
done
$PY devices/poco-x3-pro/tools/sweet-netlog.py "$L/$NAME.log" --for $((SECS + 25)) >/dev/null 2>&1 &
LOGGER=$!
$PY -c "import time; time.sleep(4)"
$S --timeout $((SECS + 60)) $D/metal_test layer $D/task10.metallib "$@" "$SECS" 3 > "$L/$NAME.txt" 2>&1
echo "metal_test exit status $?"
wait $LOGGER
$S /usr/bin/true >/dev/null 2>&1
$PY tools/metal-layer-report.py "$L/$NAME.txt" "$L/$NAME.log" "$L/$NAME.json"
