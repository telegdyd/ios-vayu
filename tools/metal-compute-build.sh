#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
for f in "$ROOT"/hakios-metal/tests/fixtures/*_air.hpp; do
    cmp -s "$f" "$HOME/vayu/hakios-metal/tests/fixtures/$(basename "$f")" || cp "$f" "$HOME/vayu/hakios-metal/tests/fixtures/"
done
cmp -s "$ROOT/hakios-metal/src/gpu.cpp" "$HOME/vayu/hakios-metal/src/gpu.cpp" || cp "$ROOT/hakios-metal/src/gpu.cpp" "$HOME/vayu/hakios-metal/src/gpu.cpp"
bash "$ROOT/tools/metal-transport-build.sh"
