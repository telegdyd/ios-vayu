#!/bin/bash
# Task 11: build what the phone runs for "CoreAnimation's window server on Metal", in WSL's ~/vayu (synced from this
# checkout first):
#
#   userland/obj/task11/HakiosMetal.bundle   src/HakiosMetalCA.m over hakios-metal's iOS core with its compiler
#   userland/obj/task11/metal_test           metal_test.m (+ app, layer; `sysctl NAME VALUE` sets a string sysctl)
#   userland/obj/task11/ca.dylib             metal_ca_try.c: backboardd takes the uploaded bundle as its plug-in
#
# The core is rebuilt only when CORE=1 (make ios MESA=1; the archive task 9 made is reused otherwise). Mesa's iOS
# archives as in tools/metal-app-build.sh. Nothing here touches the phone: tools/metal-ca-run.sh does.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B=${BUILD_ROOT:-$HOME/vayu}
source "$B/xnu-env.sh"
cd "$ROOT"
git -c core.quotepath=off status --porcelain --untracked-files=all | sed 's/^...//' | while read -r f; do
	[ -f "$f" ] && { mkdir -p "$B/$(dirname "$f")"; cmp -s "$f" "$B/$f" || cp "$f" "$B/$f"; }
done
HM="$B/hakios-metal"
rsync -a "$ROOT/hakios-metal/src/" "$HM/src/"
rsync -a "$ROOT/hakios-metal/include/" "$HM/include/"
[ "${CORE:-0}" = 1 ] && make -C "$HM" -j6 ios MESA=1

O="$ROOT/userland/obj/task11"
mkdir -p "$O/HakiosMetal.bundle"
SDK="$HOME/theos/sdks/iPhoneOS16.5.sdk"
DYN="$B/xnu-deps/host/bin/xnu-clang -arch arm64 -isysroot $SDK -O1"
MB="$B/xnu-deps/build/mesa/build-softpipe-freedreno"
[ "$(llvm-nm -g "$HM/out/ios/libhakios-metal.a" 2>/dev/null | grep -c " U _air_")" -gt 0 ] || { echo "the iOS archive has no compiler"; exit 1; }
METAL_GPU="-DHAKIOS_METAL_GPU -I$HM/include $HM/out/ios/libhakios-metal.a -lc++ -framework IOKit -framework IOSurface"
for a in src/compiler/air/libair.a src/freedreno/ir3/libfreedreno_ir3.a src/freedreno/isa/libir3encode.a \
    src/freedreno/isa/libir3decode.a src/compiler/isaspec/libisaspec.a src/compiler/nir/libnir.a \
    src/compiler/libcompiler.a src/freedreno/fdl/libfreedreno_layout.a \
    src/freedreno/common/libfreedreno_common.a src/util/libmesa_util.a src/util/libmesa_util_sse41.a \
    src/util/blake3/libblake3.a src/c11/impl/libmesa_util_c11.a; do
	METAL_GPU="$METAL_GPU $MB/$a"
done
$DYN -bundle -fno-objc-arc -Wno-deprecated-declarations -framework Foundation -framework Metal -lobjc \
	-o "$O/HakiosMetal.bundle/HakiosMetal" "$ROOT/userland/src/HakiosMetalCA.m" $METAL_GPU -lz -lm \
	-Wl,-U,_native_bridge_metal_open -Wl,-U,_native_bridge_metal_first_problem -Wl,-U,_native_bridge_metal_status \
	-Wl,-U,_native_bridge_metal_formats -Wl,-U,_native_bridge_metal_variant_hook
cp "$ROOT/userland/src/HakiosMetal.plist" "$O/HakiosMetal.bundle/Info.plist"
$DYN -fobjc-arc -Wall -Wno-deprecated-declarations -framework Foundation -framework CoreGraphics \
	-framework CoreImage -framework IOKit -framework IOSurface -framework Metal -framework OpenGLES -framework QuartzCore \
	-lMobileGestalt -Wl,-adhoc_codesign -o "$O/metal_test" userland/src/metal_test.m userland/src/metal_app.m userland/src/metal_layer.m
python3 tools/macho-sign.py "$O/metal_test" userland/src/metal_test.entitlements --no-der
# backboardd's side of a try (metal_ca_try.c): MetalPluginName leads to the uploaded bundle
$DYN -dynamiclib -Wall -Wl,-adhoc_codesign -framework CoreFoundation -framework Foundation -lobjc -o "$O/ca.dylib" userland/src/metal_ca_try.c
sha256sum "$O/HakiosMetal.bundle/HakiosMetal" "$O/metal_test" "$O/ca.dylib"
# the library of `metal_test astc` (task 9's vertex stage and float sample, and the half-precision samples of task 11)
K="$O/kernels"
mkdir -p "$K"
for f in tri_color_vs tri_tex_fs tri_texh_fs tri_texhx_fs; do
	llvm-as "hakios-metal/tools/kernels/$f.ll" -o "$K/$f.bc"
done
python3 tools/metal-mklib.py "$O/astc.metallib" tri_color_vs=vertex:"$K/tri_color_vs.bc" tri_tex_fs=fragment:"$K/tri_tex_fs.bc" \
	tri_texh_fs=fragment:"$K/tri_texh_fs.bc" tri_texhx_fs=fragment:"$K/tri_texhx_fs.bc"
