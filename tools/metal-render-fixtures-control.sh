#!/bin/bash
# regenerate each fixture at A635's chip id with the pinned generator; compare with git HEAD's committed A635 fixture
W="/mnt/c/Users/teleg/Documents/Code/Poco X3 Pro/ios-vayu"
D="$HOME/vayu/build/hakios-metal-pin"
mkdir -p "$D/out/host/ctl"
same=0; differ=0
for f in "$W"/hakios-metal/tests/fixtures/*_air.hpp; do
  k=$(basename "$f" _air.hpp)
  git -C "$W" show "HEAD:hakios-metal/tests/fixtures/${k}_air.hpp" > "$D/out/host/ctl/$k.head" 2>/dev/null || continue
  grep -q 'chip id 0x6030500' "$D/out/host/ctl/$k.head" || continue
  [ "$k" = argbuf_res ] && continue
  (cd "$D" && out/host/ir3_compiler --chip-id 0x06030500 -o "out/host/ctl/${k}_air.hpp" -s "tools/kernels/$k.ll" -n "${k}_air" "out/host/kernels/$k.bc") > /dev/null 2>&1
  sed "s#$D/##g" "$D/out/host/ctl/${k}_air.hpp" | tr -d '\r' > "$D/out/host/ctl/$k.gen"
  tr -d '\r' < "$D/out/host/ctl/$k.head" > "$D/out/host/ctl/$k.h2"
  if cmp -s "$D/out/host/ctl/$k.gen" "$D/out/host/ctl/$k.h2"; then same=$((same+1)); else differ=$((differ+1)); echo "DIFFERS $k: $(diff "$D/out/host/ctl/$k.gen" "$D/out/host/ctl/$k.h2" | grep -c '^[<>]') lines"; fi
done
echo "A635 control: $same identical, $differ differ"
