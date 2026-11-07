#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$HOME/vayu/xnu-env.sh"
"$HOME/vayu/xnu-deps/host/bin/xnu-clang++" -arch arm64 -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" -miphoneos-version-min=16.0 -std=c++17 -O2 -Wall -Wextra -Werror -I "$ROOT/hakios-metal/include" "$ROOT/hakios-metal/tools/texture-query-probe.cpp" "$HOME/vayu/hakios-metal/out/ios/libhakios-metal.a" -framework IOKit -framework CoreFoundation -o "$ROOT/userland/obj/metal-query-probe"
