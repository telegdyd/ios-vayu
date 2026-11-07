#!/bin/bash
# Compare unrelated arithmetic failures against the pre-task frontend.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
D="$HOME/vayu/tools/mesa/air"
B="$HOME/vayu/build/mesa-host/build"
export PATH="$HOME/vayu/xnu-deps/build/mesa/venv/bin:$PATH"
restore() {
    for f in air_to_nir.c air_intrinsics.c; do cp "$ROOT/tools/mesa/air/$f" "$D/$f"; done
    ninja -j3 -C "$B" src/compiler/air/air2nir src/gallium/drivers/freedreno/ir3_compiler src/gallium/drivers/freedreno/air_run > "$ROOT/logs/metal-step6/frontend-restore.log" 2>&1
}
trap restore EXIT
for f in air_to_nir.c air_intrinsics.c; do git -C "$ROOT" show "HEAD:tools/mesa/air/$f" > "$D/$f"; done
ninja -j3 -C "$B" src/compiler/air/air2nir src/gallium/drivers/freedreno/ir3_compiler src/gallium/drivers/freedreno/air_run
cd "$HOME/vayu"
set +e
python3 tools/air/intrincheck.py --run --cases 4 > "$ROOT/logs/metal-step6/softpipe-baseline.log" 2>&1
status=$?
set -e
echo "baseline arithmetic check exit=$status"
