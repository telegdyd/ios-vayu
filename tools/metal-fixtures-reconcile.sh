#!/bin/bash
# Task 9: compile every AIR fixture source (hakios-metal/tools/kernels/*.ll that has a committed
# tests/fixtures/<name>_air.hpp) with the reconciled tools/mesa/air (the pinned upstream frontend plus
# our fixes), for A640, and compare each result with the committed fixture. Nothing is written into the
# tree unless WRITE=1.
#
#   SAME  the reconciled frontend reproduces the committed fixture byte for byte
#   DIFF  it compiles, to different words (the diff of the two listings is kept in the work dir)
#   FAIL  it refuses or crashes
#
# Needs: ~/vayu/build/mesa-host built by tools/air/mk-host.sh from this tree's tools/mesa.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B="${MESA_HOST:-$HOME/vayu/build/mesa-host}"
D="$HOME/vayu/build/hakios-metal-reconcile"
mkdir -p "$D"
rsync -a --delete --exclude out/ "$ROOT/hakios-metal/" "$D/"
make -C "$D" out/host/ir3_compiler MESA_HOST="$B" > "$D/../hakios-metal-reconcile-make.log" 2>&1 ||
	{ echo "ir3_compiler did not build: $D/../hakios-metal-reconcile-make.log"; tail -20 "$D/../hakios-metal-reconcile-make.log"; exit 2; }
mkdir -p "$D/out/host/kernels"
same=0 diff=0 fail=0
for f in "$ROOT"/hakios-metal/tests/fixtures/*_air.hpp; do
	k=$(basename "$f" _air.hpp)
	[ -f "$D/tools/kernels/$k.ll" ] || continue
	llvm-as "$D/tools/kernels/$k.ll" -o "$D/out/host/kernels/$k.bc"
	if (cd "$D" && out/host/ir3_compiler --chip-id 0x06040001 -o "out/host/kernels/${k}_air.hpp" -s "tools/kernels/$k.ll" \
		-n "${k}_air" "out/host/kernels/$k.bc") > "$D/out/host/kernels/$k.listing" 2>&1; then
		sed "s#$D/##g" "$D/out/host/kernels/${k}_air.hpp" > "$D/out/host/kernels/${k}_air.norm"
		if cmp -s "$D/out/host/kernels/${k}_air.norm" "$f"; then
			echo "SAME $k"; same=$((same + 1))
		else
			echo "DIFF $k ($(diff "$f" "$D/out/host/kernels/${k}_air.norm" | grep -c '^[<>]') lines)"; diff=$((diff + 1))
			[ "${WRITE:-}" = 1 ] && cp "$D/out/host/kernels/${k}_air.norm" "$f"
		fi
	else
		echo "FAIL $k: $(grep -m1 -i 'error\|refuse\|fail' "$D/out/host/kernels/$k.listing" | cut -c1-200)"; fail=$((fail + 1))
	fi
done
echo "reconcile: $same same, $diff different, $fail failed"
[ "$fail" = 0 ]
