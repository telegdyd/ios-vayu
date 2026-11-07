#!/bin/bash
# Task 7: regenerate the render-stage AIR fixtures that still target A635
# (chip id 0x6030500) for A640 (0x06040001).
#
# The compiler is the pinned upstream revision's own AIR frontend (the one that
# generated these fixtures for A635), built natively from a detached worktree
# ~/hakios-pin of oosexgang/hakios-xnu-kernel at 63fc2b46 with Mesa 25.0.7:
# only the chip changes, so a hardware difference is A640's or the driver's,
# not a frontend difference. Our older tools/mesa/air cannot compile ten of
# these shaders and compiles others differently (e.g. tri_arr_vs's constant
# table into private memory); reconciling the two is task 9.
#
# Usage: metal-render-fixtures.sh [NAME...]   (default: every A635 *_air.hpp
# except argbuf_res, a compute fixture carried to task 9)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PIN=63fc2b4633bac3af8e57dadab9f5a8d4cb940438
UP="$HOME/hakios-pin"
B="$UP/build/mesa-host"
D="$HOME/vayu/build/hakios-metal-pin"   # a copy of the vendored driver tree for the generator alone
test "$(git -C "$UP" rev-parse HEAD)" = "$PIN" || { echo "$UP is not at $PIN"; exit 1; }
test -x "$B/build/src/gallium/drivers/freedreno/ir3_compiler" || { echo "build $B first (tools/air/mk-host.sh there)"; exit 1; }
mkdir -p "$D"
rsync -a --delete --exclude out/ "$ROOT/hakios-metal/" "$D/"
make -C "$D" out/host/ir3_compiler MESA_HOST="$B" > "$D/../hakios-metal-pin-make.log"
if [ $# -eq 0 ]; then
    names=()
    for f in "$ROOT"/hakios-metal/tests/fixtures/*_air.hpp; do
        n=$(basename "$f" _air.hpp)
        [ "$n" != argbuf_res ] && grep -q 'chip id 0x6030500' "$f" && names+=("$n")
    done
    set -- "${names[@]}"
fi
failed=0
mkdir -p "$D/out/host/kernels"
for k in "$@"; do
    llvm-as "$D/tools/kernels/$k.ll" -o "$D/out/host/kernels/$k.bc"
    if (cd "$D" && out/host/ir3_compiler --chip-id 0x06040001 -o "out/host/kernels/${k}_air.hpp" -s "tools/kernels/$k.ll" -n "${k}_air" "out/host/kernels/$k.bc") > "$D/out/host/kernels/$k.listing" 2>&1; then
        python3 - "$D/out/host/kernels/${k}_air.hpp" "$ROOT/hakios-metal/tests/fixtures/${k}_air.hpp" "$D/" <<'PY'
from pathlib import Path
import sys
source, dest, prefix = sys.argv[1:]
s = Path(source).read_text().replace(prefix, '')
p = Path(dest)
if not p.exists() or s != p.read_text(): p.write_text(s)
PY
        echo "FIXTURE PASS $k"
    else
        failed=1
        echo "FIXTURE FAIL $k"
        tail -8 "$D/out/host/kernels/$k.listing"
    fi
done
exit "$failed"
