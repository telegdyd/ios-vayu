# ios-vayu notes

## Active handoff (2026-11-07 ~01:00: iOS in `boot`, starts by itself, /private/var is HFS Plus on the flash)

HFS Plus for a real writable /private/var (in progress, 2026-11-06 late night):
- Why: /private/var is a RAM disk (ramfs) restored from / saved to darwin by var_store at Shut Down only; the APFS
  driver is read-only. The user wants a proper system: writes going straight to flash.
- Survey of github.com/Chromitsune/Portsmith-iOS (90 ports): Scion-Project/scion-kernel (HakiOS fork, same licenses)
  has Apple's HFS Plus built into the kernel, QEMU-tested only; DC28088/ios-sweet runs iOS 16 from a writable
  journaled HFS+ volume on a real phone (no license: idea only, nothing copied); zzweiqing/UniXNU-nabu is the same
  SoC/GPU (SM8150/A640) with Metal via metal2vulkan+Turnip (UniXNU, iPadOS 17): a reference for GPU speed later.
- FACT: HFS Plus is in our kernel tree: xnu/hfs/ (Scion's hfs.sh/hfs.patch/lists + our xnu.patch for bsd/conf/files,
  config/MASTER(.arm64.bcm2837), bsd/conf/Makefile.template, bsd/vfs/vfs_conf.c), xnu/files/bsd/hfs/hfs_builtin.c;
  xnu/apply.sh applies them. Kernel built in WSL (415 _hfs_ symbols; mach 63d7ca3b...+ the fix below; NOT staged to
  Windows, NOT on the phone: the phone still runs c329096e).
- FACT: virtio_blk=2 (our QEMU disk driver writes; buf_map() for cluster-I/O buffers, which carry a UPL not a VA).
  `qemu/run-hfs-test.sh` (WSL: QEMU_EFI=/usr/share/AAVMF/AAVMF_CODE.fd QEMU_VARS=/usr/share/AAVMF/AAVMF_VARS.fd;
  qemu-system-arm, qemu-efi-aarch64, ipxe-qemu installed in WSL) twice on one image: "ALL OK", boot number 1 then 2
  (journal, 1 MB write/read, unmount/remount, persistence). The panic after it is process 1 exiting (expected).
- FACT (274f982, ec38881): /dev/ufs_var = darwin's blocks 3145728..5242879 (8 GiB), writable only with ufs_write=1
  + ufs_var_first/blocks; init var_hfs=1 mounts HFS Plus there (fallback ramfs), fills it once (skeleton + last
  var_store save) and marks it. Volume made by var-volume.sh (HFSX, journaled; mkfs wrote 3 pieces / 37 MB),
  written by `darwin-install.sh var` from PBRP, read back the same (2026-11-07 00:2x).
- FACT: first try lost a change at a hard reset (run 003527: mounted "as the last boot left it", 2516 writes / 72 MB):
  this kernel has no periodic sync and hfs_syncer runs only for ejectable media. Fix ec38881: hfs_is_ejectable()
  true for /dev/ufs_var, init forks a sync() every 3 s, and counts boots in /private/var/.hakios-var-boots.
- FACT: runs 004421/004528/004636 (xl, 60 s each, ended by loader_return_after = no unmount): "boot 1/2/3 of it",
  ~3500 writes / ~65 MB each, 0 refused. Late writes survive an abrupt end.
- Images: kernel b0cba756..., root-flash.apfs a9419a0e..., flashboot.apfs 2ed5d333...; standalone.sh's default
  cmdline uses var_hfs=1. Rollback: ../backup-vayu/xnu-standalone-varstore.img (+ images-varstore/).
- FACT: 2026-11-07 ~00:5x: xnu-standalone.img cd3e34b5... flashed into `boot` (user's OK) and rebooted. Not yet
  seen by the user on the phone (their own change + hard restart test pending).
- **FACT (user, 2026-11-07):** on the flashed image the user changed something, forced a restart (vol-down+power),
  and the change stayed. /private/var is a writable HFS Plus volume on the flash, written as iOS writes.
- Next: USB shell (vayu_usbnet=3 CDC-ECM, never confirmed, + jasmine's sweetd, TCP 5143) so the agent can inspect a
  standalone-booted phone; ufs_native=1 (kernel's own UFS reads, untested on vayu); the var volume is 8 GiB
  (hfs_resize can grow it into darwin's free space).

Standalone boot (FACT unless marked):
- Loader 2.2 (546ac05, loader.efi 103936 B sha256 539ed29f...): a payload entry "resident" is copied to the
  resident address before the run; in one-shot mode (no "usb" entry) a kernel without loader_return_after gets
  no time limit (the loader feeds the watchdog while the kernel's heartbeat lives; a hung or returning kernel
  ends in a reset, which boots the same image again). The loader's on-screen log stops at 24 s (NOTE_SECONDS).
- `devices/poco-x3-pro/tools/standalone.sh build|try|flash` (Git Bash, stock fastboot): payload = loader.efi +
  kernel (c329096e...) + ramdisk root-flash.apfs + resident flashboot.apfs + cmdline `sb_delay=8` + the run
  225353 args; payload 28090800 B, xnu-standalone.img 13846528 B (sha256 e23696a7...). Log: logs/standalone.log.
  No reads from darwin's spare area were needed: everything fits in the 128 MiB boot partition.
- `try` (fastboot boot, RAM): home screen. Then `FLASH_BOOT=yes ... flash`: **the image is in `boot`**, Android's
  kernel is gone from it. **Undo: `fastboot flash boot ../backup-vayu/20261106/boot.img`.** Stock fastboot
  (volume down + power) is Xiaomi's ABL and unaffected. Updating iOS = rebuild + `standalone.sh flash`.
- **FACT (user):** after `fastboot reboot` the phone booted from `boot` alone to the home screen. The phone is
  now an iOS phone that needs no PC.
- **Persistence (FACT, user):** `var_store=1 ufs_write=1` added (now standalone.sh's default); image 64aee63e...
  flashed into `boot`. The user changed something, did Settings > General > Shut Down, and after the next boot
  the change was still there. The saver (userland/src/var_store.c, launchd job com.hakios.varstore) packs
  /private/var into darwin at byte 8589934592 (block 2097152), two 2 GiB slots in turn; init's restore_var()
  loads it. Saved ONLY by an orderly shutdown (OSKext setLoadEnabled(false) -> hakios_var_save_early); a forced
  reset (vol-down+power, a panic, a hang) keeps the previous save. Not yet seen: how the shutdown ends on vayu
  (PSCI SYSTEM_OFF vs back to the loader, which resets), the saver's own log lines, archive size.
- Rollback images: `../backup-vayu/xnu-standalone-nopersist.img` (e23696a7..., the first flashed one) and
  Android's `../backup-vayu/20261106/boot.img`.

## Earlier handoff (2026-11-06 late: iOS volume installed on the phone's flash, boots with root on flash)

User's goal (2026-11-06): iOS as the phone's main OS, Android gone; not for daily use yet. Install work
comes before features.

Done (FACT):
- GPT of LUN 0: entry 32 `userdata` is now `darwin` (type APFS, unique 1756c529-8738-41c3-ba3a-8f263332c072,
  LBA 2851328..62162938, 226 GiB, same place). Table was full (32/32), so retyped in place rather than adding a
  33rd entry like the author's phone. Made offline by `devices/poco-x3-pro/tools/gpt-plan.py retype` from the
  day-1 backup (only the two headers and table blocks change); written from PBRP by
  `devices/poco-x3-pro/tools/darwin-install.sh gpt` after checking LUN 0's ends were byte-identical to the
  backup; read back. New table: `../backup-vayu/gpt-darwin/{head,tail}.bin`; **undo = the old
  `../backup-vayu/20261106/gpt-sda.{head,tail}.bin`** (user has a copy off the PC). fastboot now reports
  `partition-type:darwin raw`, no userdata. Android no longer has a data partition.
- `darwin` contents (redwood's layout), each written by `darwin-install.sh write` from WSL through adb.exe
  with PBRP root, read back by sha256 after drop_caches (logs/darwin-install.log):
  block 0 rootfs.apfs 5628755968 B sha256 9f430a58... (187 s, 28 MB/s); block 1374208 OS cryptex
  096-04666-078.dmg 2726297600 B 2279bf44... (156 s); block 2039808 App cryptex 10485760 B 6b9d1f09....
  All three hashes equal the author's. Source images deleted from WSL afterwards (re-fetch: fetch-from-ipsw.py
  096-04088-077.dmg + tools/apfs/dmg.py extract --apfs with the pip `lzfse` module; 096-04666-078.dmg as is).
- Loader: darwin_vayu identity updated (56f0a3a). Built with Debian clang 19: loader.efi 103424 B sha256
  4c00a1e7... The day-0 loader was 86528 B from the same source (INFERENCE: another clang in PATH that day);
  the new one boots fine.
- Flash images: `DEVICE=poco-x3-pro CRYPTEXES=flash FLASHBOOT=1 REST=1 userland/build.sh` -> flashboot.apfs
  4 MB (d5f85341...) and a flash root.apfs 7 MB (394bf373..., kept as userland/root-flash.apfs on Windows,
  ~/root-flash.apfs in WSL; userland/root.apfs stays the RAM-boot one).
- **Run 225353 (FACT):** `./xl ramdisk userland/flashboot.apfs` (4 MB, 1 s), then
  `XL_RAMDISK=userland/root-flash.apfs XL_SECS=180 XL_CMDLINE="root_apfs=ufs_darwin ufs=2 bootcpu=7 cpus=8
  fb_threads=6 vtimer_intid=19 touchscreen=1 nvt_qup=1 nvt_fw=1 gpu=1 vayu_gpu=1 vayu_keep=1" ./xl run`:
  init "the iOS root volume on /dev/ufs_darwin as the root", OS/App cryptexes from /dev/ufs_darwin,c=1/c=2,
  SpringBoard, the user opened Maps (logs/flash1.png). Reads go through the loader (no ufs_native=1: untested
  on vayu). No 2.5 GB upload any more.
- darwin-install.sh root check fixed (`sh_phone "id -u"`).

Next:
1. (done: standalone boot, see the active handoff)
2. (done: persistence, see the active handoff; a periodic save, `var_store watch SECS`, is not on)
3. watchdog FFFF line; idle loader resets the phone to Android after a while.
4. DSP firmware (modem/adsp/slpi/venus/wlanmdsp) not in any image yet: could go on darwin's iOS side later.
5. The Windows copy userland/system.apfs (2.5 GB) is only needed for RAM boots now.

## Earlier handoff (2026-11-06 evening, day 1: unlocked, iOS boots to the home screen with GPU and touch)

Done (FACT):
- Bootloader unlocked (fastboot `unlocked: yes`). PBRP 4.0 booted from RAM (`day1.sh root`), adb root "direct".
- Backup: `../backup-vayu/20261106/` (outside git), 99 images, 3.8 GB, every one sha256-checked against the
  phone, DONE file, GPT head/tail of sda..sdf. Critical ones (persist, persistbak, modemst1/2, fsg, fsc, devinfo)
  all present. **Still to do: copy it off this PC.**
  Fix e28c537: PBRP links whole UFS units sda..sdf into /dev/block/by-name (counted 248 GB): skipped.
- Firmware: 96 files in fw-poco-x3-pro/ (e28c537). On MIUI 14 the Novatek touch firmware is built into the
  kernel (no file on vendor/odm/modem): `devices/poco-x3-pro/tools/nvt-fw.py` takes j20s_novatek_ts_fw01/02
  (and mp01/02) out of boot.img with vayu_nvt.c's checks; fw01 v202 sha256 b1bf0bff..., fw02 v200 f716707b....
  bdwlan.bin is on the modem partition (/image), now grabbed there.
- **This phone's panel is dsi_j20s_36_02_0a** (cmdline msm_drm.dsi_display0), not the author's 42_02_0b:
  touch needs **`nvt_fw=1`** (the driver defaults to fw02). Both panels use the PM8150L WLED.
- Windows: the loader enumerates as USB\VID_18D1&PID_D00D\XNULOADER; Windows bound no driver (Problem 28) until
  the user picked "Android Bootloader Interface" by hand in Device Manager (one time; remembered).
  A loader that sat without a driver for minutes stopped answering (AdbWriteEndpointSync timeout): reboot it.
- Payload limit (FACT): the loader's max-download-size is 0x3f00000 (63 MB); kernel + root.apfs with all firmware
  was 123 MB -> "bad size". 84c9fe0: day1.sh image now leaves modem/adsp/slpi_vy/venus/wlanmdsp out of root.apfs
  (FW_BIG); root.apfs 6 MB. hakios_image_file() also searches md1 (resident system image): the DSP images belong
  in system.apfs /fw (MODEM=1 SYSTEM=1 path of userland/build.sh, not done yet) before modem/adsp/Wi-Fi runs.
- Smoke run 214701 (`-v`, kernel b4e9d065): XNU, launchd, backboardd, spinner; returned to the loader at 60 s.
- Baseline run 214825 panicked: SError ("Unhandled implementation specific error", cpu 0) right after
  "vayu: step 1: look up the GPU's supply rails" in vayu_adreno.c cmd_db_find().
  Fix 25c356b: read the AOP pointer at 0xc3f000c (two u32: address, size; msm-4.14 cmd-db.c) through a 4 KiB
  device mapping, map what it names; fixed places only with vayu_cmd_db_probe=1. Result: pointer says
  0x85f20000 size 0x1148, magic matches. INFERENCE: the SError came from the old 128 KB write-combined (normal
  memory) mapping of AOP message RAM at 0xc3f0000 (speculative reads into protected neighbours), not from
  0x85f20000 itself (which is where the database is).
  Kernel c329096e... (xnu-src synced by hand: **edits in xnu/files must be copied into ~/vayu/xnu-src** before
  xnu-build.sh; it built in 7 s).
- Baseline run 220243 (cmdline: bootcpu=7 cpus=8 fb_threads=6 vtimer_intid=19 touchscreen=1 nvt_qup=1 nvt_fw=1
  gpu=1 vayu_gpu=1 vayu_keep=1, 120 s): Apple logo -> lock screen -> **home screen** (logs/day1-baseline.png).
  GL: OpenGL ES 3.2 Mesa 25.0.7 FD640, HakiosGPU submissions. Touch: fw01 downloaded in 872 ms, 240 Hz polling,
  user swiped (screen finger 1, 23 samples). Volume up/down seen by the buttons driver. ~10 fps in S5FPS stats.
- Loader screen line "watchdog: status ret=FFFF..." on every boot: not looked at yet.

Next:
1. Copy ../backup-vayu/20261106 off this PC.
2. day1.sh boot baseline: pass nvt_fw=1 when the panel is 36_02_0a (or make it the vayu default here).
3. DSP firmware into system.apfs (/fw), then Wi-Fi (`wifi=1`, needs fw-wifi network/PMK), audio, modem.
4. Look at the watchdog line, the 10 fps, and install-to-userdata (the user's goal).

## Earlier handoff (2026-11-05, day 0: bootloader still locked, unlock expected ~2026-11-06)

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
   - Mi Unlock (wipes userdata).
   - Recovery (FACT, 2026-11-06, downloaded with the user's OK): official PBRP 4.0 for vayu,
     sourceforge.net/projects/pbrp/files/vayu/PBRP-vayu-4.0-20251016-0805-OFFICIAL.zip, 65110536 bytes, MD5
     36e15129d5558055008834f24c95787d = SourceForge's published one, sha256 1ac7fc0c...7069f. In
     `../downloads/pbrp/` (outside git). Only its recovery.img was extracted (the zip's installer would flash the
     recovery partition: not run): `../downloads/pbrp/pbrp-vayu-4.0-20251016-recovery.img`, 134217728 bytes, sha256
     506797f046020804327c2721dba4d8b11a6d1ec3149a511c236dbb8b17d423f5; boot header v2, page 4096, arm64 Image 42 MB +
     gzip ramdisk 27 MB + recovery_dtbo + dtb, AVB footer, cmdline selinux=permissive buildvariant=eng (adb root).
     Device tree (android_device_xiaomi_vayu-pbrp, android-12.1): dynamic partitions (qti_dynamic_partitions:
     product vendor system system_ext odm), vendor ext4, FBE decryption. INFERENCE: `fastboot boot` of it works on
     vayu (the usual method); if refused, the fallback is flashing `recovery`: ask the user first.
   - `devices/poco-x3-pro/tools/day1.sh root ../downloads/pbrp/pbrp-vayu-4.0-20251016-recovery.img` -> `day1.sh backup` (to ../backup-vayu/<date>/, then copy it off
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
