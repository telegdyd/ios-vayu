#!/bin/bash
# Task 9: build what the phone runs for "a real Metal program", in WSL's ~/vayu (synced from this checkout first):
#
#   hakios-metal with its compiler    make vayu-check MESA=1 (host suite with the compiler, fake probe, iOS archive and probe)
#   userland/obj/task9/HakiosMetal.bundle   src/HakiosMetalCA.m over it, Mesa's iOS archives linked in (as build.sh does)
#   userland/obj/task9/metal_test     metal_test.m + metal_app.m (`metal_test app LIBRARY [BUNDLE]`)
#   userland/obj/task9/task9.metallib the hand-written AIR of hakios-metal/tools/kernels, packed by tools/metal-mklib.py
#
# Needs tools/air/mk-host.sh's host Mesa and tools/mk-mesa.sh's iOS Mesa (plus `ninja ... src/compiler/air/libair.a`),
# both from this tree's tools/mesa. Nothing here touches the phone.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B=${BUILD_ROOT:-$HOME/vayu}
source "$B/xnu-env.sh"
cd "$ROOT"
# the changed and new files of this checkout into the build one (nothing deleted there)
git -c core.quotepath=off status --porcelain --untracked-files=all | sed 's/^...//' | while read -r f; do
	[ -f "$f" ] && { mkdir -p "$B/$(dirname "$f")"; cmp -s "$f" "$B/$f" || cp "$f" "$B/$f"; }
done
rsync -a --delete "$ROOT/tools/mesa/air/" "$B/tools/mesa/air/"

make -C "$B/hakios-metal" -j6 vayu-check CXX=clang++ MESA=1
make -C "$B/hakios-metal" -j6 ios MESA=1

O="$ROOT/userland/obj/task9"
mkdir -p "$O/HakiosMetal.bundle"
SDK="$HOME/theos/sdks/iPhoneOS16.5.sdk"
DYN="$B/xnu-deps/host/bin/xnu-clang -arch arm64 -isysroot $SDK -O1"
HM="$B/hakios-metal"
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
	-Wl,-U,_native_bridge_metal_open -Wl,-U,_native_bridge_metal_first_problem -Wl,-U,_native_bridge_metal_status -Wl,-U,_native_bridge_metal_formats -Wl,-U,_native_bridge_metal_variant_hook
cp "$ROOT/userland/src/HakiosMetal.plist" "$O/HakiosMetal.bundle/Info.plist"
$DYN -fobjc-arc -Wno-deprecated-declarations -framework Foundation -framework CoreGraphics \
	-framework CoreImage -framework IOKit -framework IOSurface -framework Metal -framework OpenGLES -framework QuartzCore \
	-lMobileGestalt -o "$O/metal_test" "$ROOT/userland/src/metal_test.m" "$ROOT/userland/src/metal_app.m" "$ROOT/userland/src/metal_layer.m"

# the library: each function's module assembled from its .ll, then the container
K="$O/kernels"
mkdir -p "$K"
for f in fill_id tex_fill tri_color_vs tri_color_fs tri_tex_fs tri_flat_vs tri_fc_fs; do
	llvm-as "$ROOT/hakios-metal/tools/kernels/$f.ll" -o "$K/$f.bc"
done
python3 "$ROOT/tools/metal-mklib.py" "$O/task9.metallib" fill_id=kernel:"$K/fill_id.bc" tex_fill=kernel:"$K/tex_fill.bc" \
	tri_color_vs=vertex:"$K/tri_color_vs.bc" tri_color_fs=fragment:"$K/tri_color_fs.bc" \
	tri_tex_fs=fragment:"$K/tri_tex_fs.bc" tri_flat_vs=vertex:"$K/tri_flat_vs.bc" tri_fc_fs=fragment:"$K/tri_fc_fs.bc+fc_value:int:0:0+fc_opaque:bool:1:1"
# read back by the container reader of tools/metallib.py, and each module by llvm-dis
python3 "$ROOT/tools/metallib.py" list "$O/task9.metallib"
python3 "$ROOT/tools/metallib.py" dump "$O/task9.metallib" "$K/back" >/dev/null
for f in "$K"/back/*.bc; do llvm-dis "$f" -o /dev/null; done
echo "task9 artifacts:"
sha256sum "$O/HakiosMetal.bundle/HakiosMetal" "$O/metal_test" "$O/task9.metallib"
