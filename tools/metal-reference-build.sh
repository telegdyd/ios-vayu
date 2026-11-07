#!/bin/bash
# WSL Debian: build the phone job and native cffdump from the pinned Mesa archive.
# Requires liblua5.4-dev libarchive-dev libdrm-dev libexpat1-dev libzstd-dev.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_ROOT=${BUILD_ROOT:-$HOME/vayu}
M=$BUILD_ROOT/xnu-deps/build/mesa
source "$BUILD_ROOT/xnu-env.sh"
export PATH="$M/venv/bin:$PATH"
mkdir -p "$ROOT/userland/obj"
"$BUILD_ROOT/xnu-deps/host/bin/xnu-clang" -arch arm64 \
    -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" -O1 -Wall -Wextra \
    -I "$M/mesa-25.0.7/include" "$ROOT/userland/src/gl_reference.c" \
    "$M/out/libOSMesa.8.dylib" -o "$ROOT/userland/obj/gl_reference"
echo '592272df3cf01e85e7db300c449df5061092574d099da275d19e97ef0510f8a6  '"$M/mesa-25.0.7.tar.xz" | sha256sum -c -
if [ ! -f "$M/metal4-native-source/meson.build" ]; then
    mkdir -p "$M/metal4-native-source"
    tar -xf "$M/mesa-25.0.7.tar.xz" -C "$M/metal4-native-source" --strip-components=1
fi
if [ ! -f "$M/metal4-native-build/build.ninja" ]; then
    meson setup "$M/metal4-native-build" "$M/metal4-native-source" \
        -Dtools=freedreno -Dgallium-drivers= -Dvulkan-drivers= -Dplatforms= \
        -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dllvm=disabled \
        -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dshared-glapi=disabled \
        -Dbuild-tests=false
fi
ninja -j3 -C "$M/metal4-native-build" src/freedreno/decode/cffdump
echo "Decoder: $M/metal4-native-build/src/freedreno/decode/cffdump"
