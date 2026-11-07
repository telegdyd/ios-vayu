#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_ROOT=${BUILD_ROOT:-$HOME/vayu}
source "$BUILD_ROOT/xnu-env.sh"
# Preserve the build checkout's unrelated kernel/userland work.
for f in tools/probe.cpp src/iokit_transport.cpp; do
    cmp -s "$ROOT/hakios-metal/$f" "$BUILD_ROOT/hakios-metal/$f" || \
        cp "$ROOT/hakios-metal/$f" "$BUILD_ROOT/hakios-metal/$f"
done
make -C "$BUILD_ROOT/hakios-metal" -j3 vayu-check CXX=clang++
mkdir -p "$ROOT/userland/obj"
cp "$BUILD_ROOT/hakios-metal/out/ios/hakios-metal-probe" "$ROOT/userland/obj/metal-probe"
"$BUILD_ROOT/xnu-deps/host/bin/xnu-clang" -arch arm64 \
    -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" -O1 -Wall -Wextra -Werror \
    "$ROOT/userland/src/metal_transport_run.c" -o "$ROOT/userland/obj/metal_transport_run"
echo 'iOS library/probe/runner targets ready; deployed executable hashes:'
sha256sum "$ROOT/userland/obj/metal-probe" "$ROOT/userland/obj/metal_transport_run"
