#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
D="$HOME/vayu/hakios-metal"
source "$HOME/vayu/xnu-env.sh"
cmp -s "$ROOT/hakios-metal/src/gpu.cpp" "$D/src/gpu.cpp" || cp "$ROOT/hakios-metal/src/gpu.cpp" "$D/src/gpu.cpp"
cp "$ROOT/hakios-metal/tools/shared-probe.cpp" "$D/tools/shared-probe.cpp"
make -C "$D" out/ios/libhakios-metal.a
"$HOME/vayu/xnu-deps/host/bin/xnu-clang++" -arch arm64 -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" -miphoneos-version-min=16.0 -std=c++17 -O2 -Wall -Wextra -Werror -I "$ROOT/hakios-metal/include" "$D/tools/shared-probe.cpp" "$D/out/ios/libhakios-metal.a" -framework IOKit -framework CoreFoundation -o "$ROOT/userland/obj/metal-shared-probe"
