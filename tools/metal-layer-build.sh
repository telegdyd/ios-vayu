#!/bin/bash
# Task 10: build what the phone runs for "IOSurface textures and CAMetalLayer", in WSL's ~/vayu (synced from this
# checkout first): metal_test with metal_layer.m (`metal_test layer LIBRARY [SECONDS [DIVISOR [BUNDLE]]]`) and the
# library its frames draw with, and metal_layer_lookup.dylib (the window server's lookups, see the source), tri_dpos_vs + tri_cflat_fs (shaders task 7 validated on the A640). The plug-in is the
# image's (task 9's, ramdisk d2186bb7); tools/metal-app-build.sh rebuilds it when it changes. Nothing here touches the phone.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B=${BUILD_ROOT:-$HOME/vayu}
source "$B/xnu-env.sh"
cd "$ROOT"
O="$ROOT/userland/obj/task10"
mkdir -p "$O/kernels"
SDK="$HOME/theos/sdks/iPhoneOS16.5.sdk"
DYN="$B/xnu-deps/host/bin/xnu-clang -arch arm64 -isysroot $SDK -O1"
$DYN -fobjc-arc -Wall -Wno-deprecated-declarations -framework Foundation -framework CoreGraphics \
	-framework CoreImage -framework IOKit -framework IOSurface -framework Metal -framework OpenGLES -framework QuartzCore \
	-lMobileGestalt -Wl,-adhoc_codesign -o "$O/metal_test" userland/src/metal_test.m userland/src/metal_app.m userland/src/metal_layer.m
$DYN -dynamiclib -Wall -Wl,-adhoc_codesign -o "$O/metal_layer_lookup.dylib" userland/src/metal_layer_lookup.c
python3 tools/macho-sign.py "$O/metal_test" userland/src/metal_test.entitlements --no-der
# SpringBoard's side: the tweak that hosts the program's context (metal_layer_host.m), for /var/jb/usr/lib/TweakInject
$DYN -dynamiclib -fobjc-arc -Wall -Wl,-adhoc_codesign -framework Foundation -framework UIKit -framework QuartzCore \
	-o "$O/MetalLayerHost.dylib" userland/src/metal_layer_host.m
cp userland/src/MetalLayerHost.plist "$O/"
for f in tri_dpos_vs tri_cflat_fs; do
	llvm-as "hakios-metal/tools/kernels/$f.ll" -o "$O/kernels/$f.bc"
done
python3 tools/metal-mklib.py "$O/task10.metallib" tri_dpos_vs=vertex:"$O/kernels/tri_dpos_vs.bc" \
	tri_cflat_fs=fragment:"$O/kernels/tri_cflat_fs.bc"
python3 tools/metallib.py list "$O/task10.metallib"
sha256sum "$O/metal_test" "$O/metal_layer_lookup.dylib" "$O/MetalLayerHost.dylib" "$O/task10.metallib"
