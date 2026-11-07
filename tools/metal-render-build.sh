#!/bin/bash
# Task 7: sync the driver's sources, probe and fixtures into WSL's ~/vayu (only
# files that differ; the build checkout's unrelated work is preserved), then run
# the host suite, the fake probe and the iOS cross build (metal-transport-build.sh).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
D="$HOME/vayu/hakios-metal"
cd "$ROOT/hakios-metal"
for f in src/*.cpp include/hakios-metal/*.hpp tools/*.cpp tests/*.cpp tests/fixtures/*.hpp; do
    cmp -s "$f" "$D/$f" || { cp "$f" "$D/$f"; echo "synced $f"; }
done
bash "$ROOT/tools/metal-transport-build.sh"
