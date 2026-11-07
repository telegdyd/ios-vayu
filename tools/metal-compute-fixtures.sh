#!/bin/bash
# Regenerate only task-6 compute fixtures, against the existing AIR frontend.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
D="$HOME/vayu/hakios-metal"
B="$HOME/vayu/build/mesa-host"
make -C "$D" out/host/ir3-dump/ir3_cmdline.c MESA_HOST="$B"
# Older frontend has no null_texture metadata. These compute fixtures do not
# declare null textures; omit that unrelated graphics-only metadata loop.
python3 - "$D/out/host/ir3-dump/ir3_cmdline.c" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
marker='   /* The front end\'s reserved slot for Metal\'s null texture'
if marker in s:
    start=s.index(marker)
    end=s.index('\n}\n', start)
    s=s[:start]+s[end:]
if s != p.read_text(): p.write_text(s)
PY
make -C "$D" out/host/ir3_compiler MESA_HOST="$B"
failed=0
for k in chain160 chain220 long_chain pvt_fill tg_arg ptr_phi tex_fill_h tex_fill_arr tex_fill_3d tex_sample_wide tex_size_h; do
    mkdir -p "$D/out/host/kernels"
    llvm-as "$D/tools/kernels/$k.ll" -o "$D/out/host/kernels/$k.bc"
    if "$D/out/host/ir3_compiler" --chip-id 0x06040001 -o "$D/out/host/kernels/${k}_air.hpp" -s "$D/tools/kernels/$k.ll" -n "${k}_air" "$D/out/host/kernels/$k.bc" > "$D/out/host/kernels/$k.listing" 2>&1; then
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
