#!/bin/bash
# Task 11, from Git Bash: `tools/metal-ca-shot.sh NAME [RWTOUCH STEPS...]` -- do the touch steps (rwtouch: tap, swipe,
# button, wait, ...), then take a screenshot: the IOSurface the framebuffer shows in layer 0 (the kernel's latest
# "surfaces in layers" line names it), read by `metal_test screen` and written to logs/metal-step11/NAME.png.
# Needs /private/var/tmp/task11/metal_test (tools/metal-ca-run.sh uploads it). Changes nothing on the phone.
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
NAME=${1:?name}
shift
PY=${PY:-python}
S="$PY devices/poco-x3-pro/tools/sweet-sh.py"
L=logs/metal-step11
mkdir -p "$L"
[ $# -gt 0 ] && $S --timeout 120 /redwood/bin/rwtouch "$@" wait 1.5 >/dev/null
$PY devices/poco-x3-pro/tools/sweet-netlog.py "$L/.ring.txt" --for 3 >/dev/null 2>&1
id=$(grep -a "surfaces in layers" "$L/.ring.txt" | tail -1 | sed -n 's/.*): \([0-9]*\) .*/\1/p')
[ -n "$id" ] && [ "$id" != 0 ] || { echo "no surface in layer 0 ($(grep -a 'surfaces in layers' "$L/.ring.txt" | tail -1))"; exit 1; }
$S /private/var/tmp/task11/metal_test screen "$id" /private/var/tmp/screen.raw | tr -d '\r' | grep -v '^$'
$S cat /private/var/tmp/screen.raw > "$L/$NAME.raw"
$PY tools/metal-layer-png.py "$L/$NAME.raw" "$L/$NAME.png" 3
rm -f "$L/$NAME.raw" "$L/.ring.txt"
