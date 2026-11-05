# ios-vayu notes

## Active handoff (2026-11-05, day 0: bootloader still locked, unlock expected ~2026-11-06)

Goal: iOS on the POCO X3 Pro, installed on the phone eventually. Continue from the author's vayu work
rather than porting our jasmine stack (decision below).

Done (FACT):
- Workspace: this repo = author's fork `main` @ b49864a (2026-11-03), clean; branch `vayu-dev` for our work.
  WSL Debian `~/vayu` = build checkout (same commit). `~/hakios` in WSL = upstream oosexgang/hakios-xnu-kernel
  @ 397750d (reference only; its history was rewritten, no common history with this fork).
- WSL packages: 7zip 25.01, clang 19, lld, lz4, python3-venv, git, make (passwordless sudo works).
- Disk: pruned 949 old jasmine build outputs (~18 GB) -> C: 26 GB free.
- Toolchain in WSL: theos at ~/theos (L1ghtmann iOSToolchain, sdks/iPhoneOS16.5.sdk), `xnu/apply.sh` (xnu-8796.121.2
  + 80 changed / 202 new files), `xnu-deps/setup.sh` stage 1 + 2.
- Host fixes needed on Debian 13 / clang 19 (the author builds with clang 14 + older glibc), all on vayu-dev:
  bab9b97 hostcompat.h strlcpy/strlcat only for glibc < 2.38; bb653c1 xnu-clang drops the
  `-enable-trivial-auto-var-init-zero-knowing-it-will-be-removed-from-clang` gate on clang >= 16; 852fd53 xnu-clang keeps
  implicit-function-declaration/int-conversion/... as warnings on clang >= 16 (17 such sites in vayu_*.c,
  loader_return.c); 2a197eb uefi/build.sh inits Mu_Basecore submodules one level + system nasm without Mono.
- Kernel: `./xnu-build.sh -j12 -k` rc=2 (normal: export check), 0 compile errors,
  `mach.development.bcm2837` 16525952 bytes sha256 d4d61ee2b573421e5783a3fdc6cfabff529f33eb06138d9e30c5745a85bc13b8,
  arm64 Mach-O, 988 `vayu_` strings; copied to `~/vayu/hakios-kernel`. Built from 852fd53 (= author b49864a + host fixes).
- UEFI: `devices/poco-x3-pro/uefi/build.sh` -> Mu-Silicium/Build/vayuPkg/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd,
  3145728 bytes, sha256 c8d2a573a0269077d18c3b6301c6fe29c6fd237c528ea26bb93b3d01d25e0158 (reproduced by a rerun at 2a197eb).
- IPSW: user approved downloading iOS 16.5 20F66 iPhone X members from Apple's CDN; `sysimage/fetch.sh` done in
  41 min: 3.0G rootfs, 26M cryptex, 11M App cryptex, 2.6G dyld shared cache (sysimage/ 5.7 GB; dmgs not kept).
- Loader: `xnuloader/build.sh` -> loader.efi 86528 bytes sha256 f5ede4ca00272d5442a0671b2db0334c6449e794a3ffe26433d834e02fa64d98
  (identity.h from DeviceTree.d22ap.im4p, 33694 bytes from the CDN).
- Userland: `DEVICE=poco-x3-pro REST=1 userland/build.sh` rc=0 in 5 min: Mesa 25.0.7 (softpipe,freedreno) libOSMesa
  14.8 MB, root.apfs 6483968 bytes, system.apfs 2511761408 bytes; root.apfs `/` is 040755 (umask pitfall OK).
  **Built without firmware** (`fw/: 0 files`): rebuild root.apfs after `pull-firmware.sh` fills ../fw-poco-x3-pro
  (userland/build.sh copies it into root/fw; system.apfs need not be rebuilt for that).
- Disk: C: was down to 3.4 GB free (WSL ext4.vhdx grew ~14 GB). User chose the sparse WSL disk:
  `wsl --shutdown; wsl --manage Debian --set-sparse true` (WSL 3.0.3; it warns sparse is experimental), then
  `sudo fstrim -av` inside -> C: 9.2 GB free (vhdx logical size stays 57.8 GB, `fsutil sparse queryflag` = sparse).
  From now on space freed inside WSL returns to Windows after `fstrim`. Still tight for day 1 (backups + a 2.5 GB
  Windows copy of system.apfs). Further candidates, not touched: ~/ios-work in WSL (35 GB of jasmine work incl. the
  16.7.16 IPSW: the user's, ask), ~/vayu/sysimage rootfs + dyld (5.7 GB, only needed to rebuild system.apfs).

Next:
1. Phone still locked, on Android: `getprop`, `fastboot getvar all`, `devices/poco-x3-pro/pull-firmware.sh`
   (phone was not on USB as of 16:16), then rebuild root.apfs.
2. Day 1: unlock, back up partitions (temp root boot), copy kernel/loader/UEFI FD/images to the Windows checkout,
   `./xl enter`, `./xl ramdisk userland/system.apfs`, `./xl run` with the device README's boot args.

## Decision: base on HakiOS vayu (2026-11-05)

- The published device repo nomorecoolnicknames/hakios-sm8150 (2026-10-28) is a split-out of this fork and
  does NOT build against current upstream HakiOS: upstream has no `platform_vayu` in the loader and nothing
  calls the `vayu_*` drivers. The working tree is this fork's `main`.
- Why HakiOS rather than our jasmine stack (ABL -> shim -> XNU, bgmtl on Gallium): this fork already runs on
  vayu (display at 120 Hz, touch, GPU, cpufreq, Wi-Fi with internet, audio, camera, modem); HakiOS's own Metal
  path (hakios-metal, PM4 direct) reached 100-118 fps on redwood's Adreno 642L versus our 38 fps on jasmine's
  Adreno 512 (different GPUs, but the gap is larger than the GPU difference); an A640 port patch exists
  (docs/vayu-patches/0040-hakios-metal-a640-gen2-port.patch).
- What we may bring from jasmine: install into `userdata` with a standalone boot, our tooling
  (netlog/sweet-run/sweet-fs/framebench ideas), CoreAnimation fixes (format 500 YCbCr textures, SPI texture
  bind, CA_DISABLE_DETACHED), perf methodology.
- Fallback if the fork cannot be made to boot here: our shim + XNU, with `vayu_*.c` as the register reference.

## State of the author's work (from docs/HANDOFF-2026-11-02.md and later commits; their claims, not yet seen here)

- Wi-Fi: works with internet (WPA2-PSK, iOS DHCP, ~30 MB rx, 0 drops; runs 150920, 161303, 032001). PMK file
  inside the root image, boot-arg `vayu_wifi_pmk_file=1`; `vayu_wifi_a80211=0` default.
- Display/UI: 120 Hz, GL, SpringBoard. Touch NT36675 on QUP SPI (`touchscreen=1 nvt_qup=1`, `s8_touch=1`).
- Bluetooth: stack comes up; RETAIN_LE_SCAN stall, fix via libbt 67056 untested.
- Camera: kernel 30 fps; userland preview 4-5 fps, fixes untested.
- Cellular: LTE registration works; mobile data (IPA) hangs the SoC: never enable in common builds.
- SMS near; Venus (HW video codec), IFE0, ultra-wide camera written but untested.
- Their kernel builds: `xnu-build.sh -j24 -k`, rc=2 is normal (export check). Their root images (root-night9,
  root-cam4, ...) are on their own host, not public: we build our own.
- Pitfalls they list: root image must be 0755 (umask 077 breaks `mobile`), copied trees with BUILD/ silently
  build the old tree, no pauses between IPA MMIO writes, full driver set overheats the phone in a minute
  (run only what is needed), RPMh TCS0 single lock.
- Boot args baseline (device README): `bootcpu=7 cpus=8 fb_threads=6 vtimer_intid=19 touchscreen=1 nvt_qup=1 gpu=1 vayu_gpu=1 vayu_keep=1`.
