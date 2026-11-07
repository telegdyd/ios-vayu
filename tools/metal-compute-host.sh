#!/bin/bash
# Native-only fixture tooling; never reconfigure the phone Mesa build.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B="$HOME/vayu/build/mesa-host"
export PATH="$HOME/vayu/xnu-deps/build/mesa/venv/bin:$PATH"
# Synchronize only the frontend files changed by this task.
for f in air_intrinsics.c air_to_nir.c; do
    cmp -s "$ROOT/tools/mesa/air/$f" "$HOME/vayu/tools/mesa/air/$f" || cp "$ROOT/tools/mesa/air/$f" "$HOME/vayu/tools/mesa/air/$f"
done
if [ ! -f "$B/build/build.ninja" ]; then
    # The existing setup may fail its first compile on this libc; fix below.
    bash "$HOME/vayu/tools/air/mk-host.sh" || test -f "$B/build/build.ninja"
fi
# mk-host currently skips once_flag on glibc configurations that do not expose it.
python3 - "$B/mesa-25.0.7" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])/'src/c11/threads.h'
old=p.read_text()
s=old.replace('#  if defined(__GLIBC__) && __GLIBC_USE(ISOC23) && !defined(__cplusplus)', '#  if 0 /* native fixture build: libc does not expose call_once */')
if s != old: p.write_text(s)
PY
ninja -j3 -C "$B/build" src/compiler/air/air2nir src/gallium/drivers/freedreno/ir3_compiler
