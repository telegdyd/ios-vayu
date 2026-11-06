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

- Phone (FACT, 2026-11-05 ~18:45; full dumps in `../device-info/` outside git: getprop.txt, fastboot-getvar-all.txt):
  vayu_global M2102J20SG, MIUI V14.0.3.0.TJUMIXM (Android 13), hwc GLOBAL, hwversion 6.19.0, hw-revision 20002,
  board msmnile, dynamic partitions, no A/B slots (has its own `recovery`), bootloader locked, verified boot green,
  **anti:2** (anti-rollback index: never flash a ROM/firmware with a lower index), vendor.panel.display 6,
  vendor.panel.touch_vendor 4. Partition sizes: userdata 0x38905FB000 (~226 GB: a 256 GB unit), super 8.5 GB,
  boot/recovery 128 MB each, modem 320 MB, persist 64 MB (+ persistbak), modemst1/2 + fsg 8 MB each,
  xbl/abl/devcfg each with a *bak copy, logdump 64 MB (HakiOS's loader writes its log there).
- Firmware pull (FACT): `pull-firmware.sh` from Git Bash got 0 files. Two causes: (1) MSYS path conversion turned
  /vendor/... into C:/Program Files/Git/vendor/... (fixed in f8d2cb6: MSYS_NO_PATHCONV=1); (2) on this ROM the adb
  shell gets "Permission denied" on /vendor/firmware and /vendor/firmware_mnt/image: **root is needed**, so the
  pull moves to day 1 (the unlock wipe keeps /vendor and modem).
- Implicit declarations (FACT, 2026-11-06): the build runs `-w`, so they never showed. `XNU_CLANG_DIAG=1 ./xnu-build.sh`
  (462bb33) shows only implicit-declaration/int-pointer diagnostics. Our files had 17 sites: 8x `printf` in
  vayu_wifi_scan.c (no libkern.h: a **real bug** on Darwin arm64, where an undeclared function is called as
  non-variadic, its arguments go in registers while printf reads them from the stack -> garbage or a fault on `%s`;
  INFERENCE: the author's w24 EAPOL log lines printed garbage), 6x `thread_terminate`, `ml_get_interrupts_enabled`,
  `vayu_ipa_firmware_up` (bool, no prototype anywhere), `halt_all_cpus` (loader_return.c); those return int/void/bool, so no
  truncation, only a missing prototype. All fixed in 6cb5488. Rebuilt with DIAG: 0 diagnostics in our files (the
  remaining 7 casts in model_dep.c/kern_sysctl.c are Apple's own code), rc=2 (export check as before),
  `mach.development.bcm2837` 16525904 bytes sha256 b4e9d065d50ddaebd46bcf0a3567898c965ea5e6d95980f2c2823cb42a70dd58,
  copied to `~/vayu/hakios-kernel` (replaces d4d61ee2...). Not yet run on the phone.
- xl on Git Bash (FACT, 2026-11-06, 1d1580f + 0dbc8dc): as the author left it, it could not work from Windows: no
  `flock` in Git for Windows (every `fb` call fails), `python3` is the Store stub (mkpayload/mkxnuimg fail), DEVICE
  defaulted to poco-x5-pro, and the Windows checkout had no UEFI pieces (no Mu-Silicium, no vayu BootShim.bin).
  Fixed: mkdir+PID lock stand-in when flock is absent, `$PY` (python3 | python | py -3), CR stripped in `fb`,
  `DEVICE` defaults to poco-x3-pro, a warning when the author's prebuilt loader would be used.
  `devices/poco-x3-pro/tools/stage-windows.sh` (run in WSL) builds and verifies a USB image (verify-bootimg OK:
  shim 176 + FD c8d2a573... + XNUP loader.efi/usb/platform=vayu + DTB 1c71a972...), then copies BootShim.bin/FD/ramdisk/
  mkbootimg.py to devices/poco-x3-pro/prebuilt/ (now git-ignored except the DTB), the kernel to the xnu-src BUILD path,
  loader.efi, root.apfs, system.apfs, plus `staged.sha256`. Staged 2026-11-06, 1m50s. The Windows-built xnu-usb.img
  differs from the WSL one only in the gzip OS byte and the header's SHA-1 id (decompressed kernel and DTB are identical).
  Dry run with fake fastboot/adb (scratchpad, CRLF on stderr like Windows): state, enter (adb reboot bootloader ->
  boot -> loader), ramdisk, run (payload = kernel b4e9d065 + root.apfs + cmdline), a second xl refused during a run,
  state/stop allowed, stale-lock recovery, screenshot PNG, log, reboot: all OK. Real `./xl state` on the phone
  (Android, adb) = `android`. Not tested: real fastboot (locked bootloader refuses `fastboot boot` until day 1),
  USB transfer speed of the 2.5 GB `xl ramdisk`. Windows has no `dtc`: verify-bootimg.py's last DTB check needs WSL.
  Re-stage after any rebuild: `devices/poco-x3-pro/tools/stage-windows.sh` (SKIP_SYSTEM=1 skips system.apfs).
- Day-1 script (FACT, 2026-11-06, 9a9946c): `devices/poco-x3-pro/tools/day1.sh` status | root IMG | backup | firmware |
  image | boot [smoke|baseline], from Git Bash; nothing flashed or written on the phone. `pull-firmware.sh` rewritten
  for root (recovery: adb root, vendor/modem/bluetooth mounted read-only under /mnt/fw-* and unmounted; Android: su),
  each file sha256-checked against the phone; now also venus, ipa_fws (both loaded via vayu_pas_load), regdb.bin.
  Shared helper `devices/poco-x3-pro/tools/adbroot.sh`. xl knows `recovery` (state, and enter reboots it to fastboot).
  The partitions without userdata/super/cust total ~2.5 GB (getvar dump), not 1.2; backup adds logical vendor+odm.
  Tested: real phone (stock Android, no root): status, backup refuses, pull-firmware reports no root. Fake phone
  (scratchpad fake adb running the commands on a file tree): root refuses locked / non-ANDROID! image / "n";
  backup critical-first, a corrupted read caught by sha256 and retried alone on rerun, contents byte-identical,
  GPT head/tail per LUN; firmware in recovery (mount, 34 files identical, unmount), Android+su same set; boot from
  recovery -> fastboot -> loader -> one system.apfs upload -> smoke run; second boot reuses the resident image.
  Real `day1.sh image`: WSL pull + root.apfs rebuild + restage in 33 s (system.apfs unchanged, skipped).
  Not testable before the unlock: a real recovery (`ls /dev/block/mapper/vendor`, its toybox/busybox `blockdev`,
  `sha256sum`, `mount -o ro,noload`), exec-out throughput for the backup, Magisk's su prompt.
  The pull list does not cover what the author built privately: fw/sensors.pak (vayu_fastrpc.c) and the MCFG tree
  served over TFTP (vayu_wifi.c, /readonly/firmware/image/modem_pr/...): the backup's modem.img and
  logical-vendor.img hold their sources.

Next:
1. Day 1 (each step checks the phone first; see the head of day1.sh):
   - Mi Unlock (wipes userdata). Choose a vayu recovery image to `fastboot boot` (the author uses PBRP;
     downloading one needs the user's OK; a recovery avoids Android setup and Magisk's su prompt).
   - `devices/poco-x3-pro/tools/day1.sh root IMG` -> `day1.sh backup` (to ../backup-vayu/<date>/, then copy it off
     this PC) -> `day1.sh firmware` -> `day1.sh image` -> `day1.sh boot smoke` -> `day1.sh boot baseline`
     -> `./xl reboot`.

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
