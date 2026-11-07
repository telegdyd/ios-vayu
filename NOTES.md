# ios-vayu notes

**Deploys (user decision 2026-11-07): flash from iOS, never through our loader's USB mode.**
`FLASH_BOOT=yes devices/poco-x3-pro/tools/phone.sh deploy [IMAGE]` from a settled iOS (~1.5 min): the image
put on the phone, staged in darwin by `flash_stage` (userland/src/flash_stage.c; the binary
userland/obj/flash_stage, kept on the phone as /private/var/hakios/flash_stage), a reboot -- loader 2.8 writes
`boot` before anything else and restarts -- then iOS again and `boot` compared with the image. Keep a copy of
each image in ../backup-vayu. No agent sends "loader"/"fastboot" to the command port, runs `phone.sh
loader|flash`, or flashes `boot` in our loader (`flash:boot`, `xl` there): loader mode hangs inside
Qualcomm's USB driver after any forced restart (below, "Loader-mode hang (parked)"); `phone.sh` refuses
those (LOADER_MODE=yes overrides: only on the user's word, for work on the hang itself). If `boot` does not
start: vayu's stock fastboot (the user: volume down + power), `fastboot flash boot IMAGE`, `fastboot reboot`.

## Flash from iOS (2026-11-07 ~14:40; loader 2.8)

- iOS may write only darwin past ufs_write_first (hakios.ufs.c, holder of kern.hakios.var_busy), and the
  loader on core 0 performs those writes and refuses others; so `boot` is not written by iOS. `flash_stage
  stage IMAGE` writes IMAGE into darwin from block 2621440 (var_store's second slot: unused, var_store is off
  with var_hfs=1), reads it back, then the header into block 3145727 ("XNUFLASH", first block, bytes,
  FNV-1a 64). Loader 2.8 (xnuloader/loader.c standalone_staged_flash, first thing of a standalone start, no
  USB): header cleared first, image read through a 1 MB buffer, place/size/sum checked, flash_boot() (the
  partition named exactly "boot", "ANDROID!", read back), reset. `flash_stage verify IMAGE` reads
  /dev/rufs_boot; `flash_stage cancel` clears a stage.
- **FACT (14:39-14:44):** loader 2.8 image 5478afe2 (loader fa305e53, kernel 734bff34, step 3's args) put in
  once through stock fastboot. Then from iOS: 80853881 (the same + `flashtest=1`) deployed -> iOS came back with
  flashtest=1 in kern.bootargs (1 min 37 s); then 5478afe2 deployed back -> "boot holds" it, flashtest gone,
  rc 0 (1 min 38 s). Staging 14 MB: ~1 s. The staged copy lives in /private/var/hakios (/private/var/tmp is
  emptied at boot).
- `boot` was 5478afe2 (= ../backup-vayu/xnu-standalone-loader28-5478afe2.img); then 1252556b (Metal step 8); now 4cb4ccbf (Metal step 9 below).

## Loader-mode hang (parked 2026-11-07; come back to it later)

Symptom: "loader" from iOS (flag XNULOADR in darwin block 3145727, cold reset, the loader's flag path, USB
command mode) -> Windows lists a fastboot device with serial "????????????", every command times out
(AdbWriteEndpointSync), then it drops off the bus; the phone shows the loader screen until a forced restart.
Trials L1-L9 in the 2026-11-07 handoff below (logs/loader*-net.txt, logs/*.txt are git-ignored).

- **FACT (trigger):** reliable after a forced restart (power held) earlier in the chain: 5 of 5 (H1-H3 in the
  morning, L3, L5, L8, L9 -- all of them with the forced restart as the last reset before the iOS session that
  sent "loader"). 0 of 13+ hung after software resets only, with the 2.5 and marks-only loaders.
  L4: one software reboot after the forced restart cleared it.
- **FACT (not the cause):** the modem or Wi-Fi running (L1 without, L2 with: both OK); iOS uptime (6.5 h OK, 2 min
  OK); the loader binary (4894c295 in every image of the morning); the logdump write (it completes: bar 11,
  "read back the same"); the order of work after usb_start (2.6-order moved the console lines and the log write
  before USB: still hangs, L8); leftover DWC3 core state (2.7 stops the core, waits for DEVCTRLHLT and does
  DCTL.CSFTRST before Qualcomm's start: still hangs, L9).
- **FACT (where, loader 2.6 bars):** flag cleared, Qualcomm's USB init event, protocol, start_ex, buffers, the
  log, the command loop, the stack's "connected" event, the first receive queued (send returned) -- then the
  loader never comes back from Qualcomm's `handle_event` (the blinking square freezes). The PC has the device
  descriptor but not the serial string: enumeration stops inside Qualcomm's UEFI USB device driver.
- **FACT:** when the flag path starts, the controller is already powered, clocked and halted (snap1: GDSC on,
  master clock on, DSTS 0x420004, GCTL 0x102000), left so by an earlier stage of the boot.
- **FACT:** the snapshot loaders (2.6-snap, 2.6-order: PMIC reads through the arbiter's observer channel at TPL
  high, before and around usb_start) hung twice on good chains, same spot (L6, L7). HYPOTHESIS: those PMIC reads
  disturb Qualcomm's stack (it uses the PMIC for Type-C/charger detection) -- a confounder, not the original bug.
- **On vayu there is no watchdog** (the hypervisor's SMCs return -1) and the loader's idle reset applies only
  after a kernel's return: a hung loader and an idle one look the same from outside.
- **Left to try (not done):** compare the USB PHYs (QUSB2 HS PHY 0x088e2000, QMP SS PHY) and PM8150B Type-C/APSD
  between a good and a bad start without disturbing the stack (read once, before the init event, no TPL games;
  or from the kernel at the end of the iOS session before the reset); a full USB block reset through GCC
  (USB30_PRIM_BCR, QUSB2PHY_PRIM_BCR, USB3_PHY_PRIM_BCR) before the init event; HS-only descriptors (no SS).
  Why a forced restart matters is not known: its effect survives one cold ResetSystem and the iOS session in
  between, and is gone after the next.
- **Code:** xnuloader/loader.c 2.7-corereset holds the bars (flag path only), the unused snapshot code and
  usb_core_reset(). `boot` now holds image b7820c77 (loader c57af185, kernel 734bff34, args = step 3's).
  Images: ../backup-vayu/xnu-standalone-{marks-de64333e,snap-a296b56a,order-5a2999b0,nosnap-0530ab82,
  corereset-b7820c77}.img; the last plain-2.5 one is xnu-standalone-wifiios-0c82c913.img.

**Metal:** the plan is `docs/metal-roadmap.md` (direct hakios-metal driver, user decision 2026-11-07): one agent per
task, in order; each ticks its task there and adds a line to the handoff below.

## Metal step 11 (2026-11-07; the window server on Metal, switched at run time)

- **FACT (`docs/metal-ca-results.md`, `docs/metal-step11-phone.log`, screenshots `docs/metal-step11/`):** backboardd on
  this tree's plug-in draws the home screen, Settings, the app switcher (and switching from it), Safari and Control
  Centre through the A640, with blur and materials matching GL. `tools/metal-ca-run.sh off` is GL again (run gl3).
  Task 9's 24/24 and the new `metal_test astc` 72/72 pass on the same bundle.
- **Fixed:** CoreAnimation's uber shaders are now compiled from QuartzCore's own `default.metallib` (this image has
  one), specialised by CA's constants. Upstream's precompiled variants and stand-ins gave Safari's toolbar a grey
  band and its launch-snapshot card one solid colour. `metal_ca_variants=1` gives the old path. Shadow-copy surfaces
  are now written back before events and handlers.
- **How, no reflash:** `tools/metal-ca-build.sh` (WSL), `tools/metal-ca-run.sh on|off NAME`, `tools/metal-ca-shot.sh`.
  - `ca.dylib` goes into backboardd via `kern.exec_inject`; it swizzles `+[NSBundle bundleWithPath:]` to load
    `/private/var/tmp/task11/HakiosMetal.bundle`.
  - Clients file: `/private/var/tmp/HakiosMetal.clients`. Diagnostic switches: `/private/var/tmp/HakiosMetal.args`.
  - All of it is gone after a reboot.
  - bindfs at run time is refused (pid 1 only), and dyld interposing does not reach Metal's IOKit calls in the cache.
- **`boot` now: 76cb40d9** (= ../backup-vayu/xnu-standalone-metal11-76cb40d9.img; deployed from iOS with the user's OK,
  `logs/metal-step11-deploy.log`). It is 4cb4ccbf with ramdisk 37cac8e3 (this plug-in; the previous one is kept as
  ../backup-vayu/root-flash-d2186bb7.apfs) and `metal=3` in place of `metal=1`.
  - `metal=3` now means backboardd (and metal_test) alone. Every process is `metal=4`, which is untested.
  - Rollback: deploy 4cb4ccbf (GL).
  - **FACT (first boot):** kern.bootargs has metal=3; backboardd 15 took the device with the specialised shaders,
    SpringBoard 9 was refused, no `hakios-gl` frames, frames reach the framebuffer.
  - No UI tests were run on this boot; the user checks it by hand.
- **Upstream checked:** `main` = our pin 63fc2b46; nothing newer for Metal (mtk drops it, legacy-hackios is GL-era).
- **Next:** with the user's OK, an image with this plug-in and `metal=3` (backboardd on Metal from boot; `metal=1` is
  GL). Then task 12, or task 13 to measure Metal against GL.

## Metal step 10 (2026-11-07; CAMetalLayer on the panel)

- **FACT (`docs/metal-step10-phone.log`, `docs/metal-layer-results.md`):** `tools/metal-layer-run.sh final-full 60` ran
  `metal_test layer`, a full-screen CAMetalLayer (rotating triangle, frame-numbered clear colour).
  - 3590 frames (59.8/s), 0 errors, 239 drawables read back and 0 wrong. Present interval median 16.65 / p95 18.01 /
    p99 19.15 ms; GPU 2–3 ms a frame.
  - QuartzCore scans the drawables out directly (framebuffer layer 0 names them); the panel runs at 60.9/s.
  - 0 surfaces re-given to the GPU or locked while being copied to the panel, 0 copied before the GPU was done.
  - `final-plain 20 LAYER_PLAIN=1` (the window server composites it): its output surfaces show the layer, each read
    from one frame (`docs/metal-step10-composited.png`).
  - Ended at 35 C / 80%. No plug-in/driver change; `HakiosGPU` 0x7e surface import is now exercised on hardware.
- **Phone state changed (not flashed; `boot` still 4cb4ccbf):**
  - SpringBoard was restarted once (pid 9 -> 710).
  - `/private/var/jb/usr/lib/TweakInject/MetalLayerHost.{dylib,plist}` is installed and persists across boots. It is
    idle until notified; delete both files to remove it.
  - Test files are in /private/var/tmp/task10 (emptied at boot).
- **Learned:**
  - A sweetd child is in launchd's `system` domain and CA's services are in `user/501`. Fix: borrow SpringBoard's
    bootstrap port before an exec, plus `metal_layer_lookup.dylib`.
  - A remote CAContext is never drawn unless SpringBoard hosts it (CALayerHost).
  - The AMFI stand-in gives user space nobody's entitlements.
  - `tools/macho-sign.py` signs ad hoc with XML entitlements; a DER entitlements blob gets the signature rejected.
  - A signed file overwritten in place counts as unsigned (stale cached signature): remove it first.
- **FACT (the user):** watched the panel through all the runs; the animation showed, nothing wrong.
- **Open:** `presentedTime` is never reported. **Next:** task 11 (CoreAnimation
  on Metal; `metal=3` shows backboardd the device).

## Metal step 9 (2026-11-07; a real Metal program draws and computes)

- **FACT (`docs/metal-step9-phone.log`, `docs/metal-app-results.md`):** `metal_test app LIB BUNDLE CACHE` -- public
  Metal API after the device -- 24/24 checks on the A640, cold and warm, GL UI live (SpringBoard 9 / backboardd 15
  unchanged, 31 C / 88%): PC-built `.metallib` (7 functions), compute into a buffer and a texture, two render
  pipelines, function constants (incl. a required one refused), blits, readbacks, handlers. Warm run: 10 cache hits,
  0 compiles (fill_id 91 -> 0.44 ms). Files uploaded to /private/var/tmp/task9 only; **nothing flashed**, `boot`
  still 1252556b. The device was made from the uploaded bundle by hand, not by MTLCreateSystemDefaultDevice().
- **Code:** `tools/mesa/air` = upstream 63fc2b46's frontend (+ its air-ir3 and two ir3 patches): reproduces 58/59
  committed fixtures byte for byte (`tools/metal-fixtures-reconcile.sh`), argbuf_res regenerated for A640 and run on
  the phone. Plug-in = `userland/src/HakiosMetalCA.m` (upstream's full bridge; vayu gate/name/limits, own function
  -constant specialisation, cache lines); `userland/build.sh` builds it by default (METAL_PLUGIN=basic: the old).
  Driver: compute kernels in the disk cache, `hakios_metal_cache_counts()`. Build all: `tools/metal-app-build.sh`
  (WSL; host Mesa `tools/air/mk-host.sh` -> `~/vayu/build/mesa-host`, iOS Mesa `tools/mk-mesa.sh` + libair.a).
  Host suite 263 (MESA=1) / 262, 0 failed. Compiler-enabled probe on the phone: 279 ok, 1 fail = tex_fill's
  phone compile differs in words from the host's (its code runs right; HYPOTHESIS libc qsort order).
- **`boot` now: 4cb4ccbf** (= ../backup-vayu/xnu-standalone-metal9-4cb4ccbf.img; deployed from iOS with the user's
  OK, `docs/metal-step9-deploy.log`): 1252556b with ramdisk d2186bb7 only (built by `DEVICE=poco-x3-pro
  CRYPTEXES=flash FLASHBOOT=1 REST=1 userland/build.sh` in WSL; step 8's fcb7ecfa kept in ../backup-vayu). Rollback
  1252556b. **FACT:** `/redwood/bin/metal_test app /private/var/tmp/task9/task9.metallib` on the system device: 24/24
  twice, cache persists across the reboot; window server on GL ES 3.2 / FD640 with the rebuilt Mesa (new ir3 patches).
  The library must be uploaded again after a boot (/private/var/tmp); it is `userland/obj/task9/task9.metallib`.
- **Next:** task 10 (IOSurface textures, CAMetalLayer) on the CA plug-in's paths. The plug-in's origin licence is
  "to verify" (THIRD_PARTY_LICENSES.md); the user said that is no issue for our purpose (2026-11-07).
- WSL `~/vayu` was fast-forwarded to bd98a33 after `git stash` of its (identical) copies: `stash@{0}` there.

## Metal step 8 (2026-11-07; Metal.framework sees the device)

- **`boot` now: 1252556b** (= ../backup-vayu/xnu-standalone-metal8-1252556b.img): kernel 34b989e3, ramdisk
  fcb7ecfa (root-flash.apfs, with lib/HakiosMetal.bundle; same 21 fw files as a447c783, backed up as
  ../backup-vayu/root-flash-a447c783.apfs), loader fa305e53, resident 2ed5d333, cmdline = 5478afe2's + `metal=1`.
  Deployed from iOS with the user's OK (`logs/metal-step8-deploy.log`). Rollback: 5478afe2.
- **FACT (`docs/metal-step8-phone.log`):** `metal_test device` -> `MTLCreateSystemDefaultDevice()` =
  "HakiOS Adreno 640", A640 limits/families as in the roadmap's task 8 result; public-API GPU blit PASS.
- **FACT (`logs/metal-step8-console.txt`):** SpringBoard, backboardd, chronod, mediaserverd load the bundle and are
  refused (metal=1 = metal_test only); backboardd draws on GL (FD640). Code: MiniIOMobileFramebuffer.cpp
  (metal=N names the plug-in), init.c (synthetic dir + bindfs at /System/Library/Extensions), build.sh (builds
  the bundle over hakios-metal/out/ios), userland/src/HakiosMetal.plist, hakios-metal/plugin/HakiosMetal.m.
- `metal_test bundle PATH` tries a plug-in by hand (no reflash): upload to /private/var/tmp (emptied at boot).
- Open: `-registryID` fix (entry ID at init) is committed but not in the flashed ramdisk; `-featureProfile`
  answered zero. Task 9 is next (needs encoders, pipelines, MESA=1 reconciliation).

## Metal step 7 (2026-11-07; rendering on A640)

- **FACT (`metal-step7`, `docs/metal-step7-phone.log`):** the full hardware
  probe, stages 1–9, passes four consecutive runs with the GL UI live (SpringBoard
  9 / backboardd 15 throughout): 2x default (488 of 683 draw passes in GMEM, 7
  hardware-binned) and 2x `--sysmem` (669 sysmem), 253 checks / 0 failures each
  (175 rendering). Covers clear, flat/attributes/indexed/instanced, textures
  (cube, arrays, 3D, shadow, ASTC, mips), blending, depth, stencil, MSAA, MRT,
  framebuffer fetch, occlusion, IOSurface target, and 1125x2436 GMEM against
  sysmem with 0 differing pixels. Details/coverage: `docs/metal-render-results.md`.
- **FACT (fixtures):** 28 render fixtures were still A635. Our older
  `tools/mesa/air` cannot compile 10 and compiles others differently, so they
  were regenerated by the pinned upstream frontend as the generator only. It runs
  from a WSL worktree `~/hakios-pin` at 63fc2b46 with its own native Mesa 25.0.7
  build. Control: the same generator at A635 reproduces all 28 committed fixtures
  byte for byte. `tools/metal-render-fixtures{,-control}.sh`,
  `docs/metal-step7-fixtures.log`. The single-frontend decision stands; task 9
  must make ours produce these.
- **FACT (changes):** no driver rendering fix needed. Probe: `--sysmem`,
  `--render-stop 9x`, section markers, closing pass totals by mode; A635
  expectations fixed (bicubic now a named refusal, A640 has no cubic TP filter;
  full-screen tile count from the planner, 12 not 24); five GMEM-labelled tests
  now `setGmem` explicitly. Driver: `CommandQueue::setGmemDefault`,
  `passTotals()`. The transport audit names failed requests: the one per run is
  request 126 (`kHakiosSurface`) for the deliberate nonexistent-surface control;
  handles/mappings/queues 0. 261 host tests, 0 failed checks
  (`docs/metal-step7-build.log`).
- Temporary upload `/private/var/tmp/metal-probe-render` only; 26 C / 91%; no
  reboot or partition command. Not covered: device-compiled pipelines (no
  `MESA=1`: 9q/9f), six host-only fixtures, recovery. Task 8 is next.

## Metal step 6 (2026-11-07; compute on A640)

- **FACT (`metal-step6`, `docs/metal-step6-phone.log`):** seven complete
  compute-only phone runs pass, 70 compute + eight transport checks each;
  three with UI stopped, three with UI live, plus the initial complete run.
  An additional half-texture size-query fixture passes at two input sizes,
  4,096 output pixels each. All eight final resource audits pass. No rendering
  or live AIR compilation was enabled. Evidence, capture hashes, limitations
  and reproduction: `docs/metal-compute-results.md`, `metal-step6-summary.json`.
- **FACT:** regenerated eleven additional fixtures for FD640. Fixed the
  existing AIR frontend's pointer-phi offsets (refuses different bindings),
  half store typing, array-store layer argument, and dynamic threadgroup base
  after static arrays. The last initially gave 992/1,024 correct pairs;
  captured/decoded before and after, fixed shader adds 256 bytes to dynamic
  shared accesses and now passes 1,024/1,024. Compared dispatch state with
  task 4; no kernel or PM4 fix needed. Original capture files remain ignored
  in `logs/metal-step6/`. The installed iOS Mesa/GL library was not replaced.
- **FACT / diagnosed remainder for task 9:** `argbuf_res_air` is still an A635
  fixture, not submitted. Existing frontend refuses `air.indirect_buffer`;
  this and the bitcode-only/live-compile cases need task 9's AIR API and
  argument-buffer integration. Do not claim those as hardware passes.
- **FACT (build):** 261 host tests, zero failed checks; fake transport stages
  pass; iOS core/probe/helpers built. Targeted pointer-phi regression passes.
  WSL pull refused unrelated dirty work, which was preserved; only task files
  synced. Native AIR tooling uses a separate `~/vayu/build/mesa-host` build.
  Full frontend check returns 1: ten softpipe clamp/fmin/fmax operation
  mismatches reproduced with the pre-task frontend. 456 readers match LLVM,
  321 compile (unchanged), 255 comparable CPU/drawn results and 71 folded
  operations match; atomics/barriers and 35 texture calls pass. Evidence and
  baseline comparison: `docs/metal-step6-build.log`; no full-CI green claim.
- **FACT (phone):** original UI PIDs 9/15 resumed, 27 C / 89% at final check.
  Temporary uploads only; no reboot or partition command. Recovery remains
  unported; FAULTS remains a stub zero. Task 7 rendering is next: audit/port
  its newer A635 fixtures before use; stay on GL as the system fallback.

## Metal step 5 (2026-11-07; transport on the phone)

- **FACT (`metal-step5`, `docs/metal-step5-phone.log`):** 40 repeated hardware
  probe runs through stages 1–4 / 320 checks pass, plus a final health run.
  Twenty with SpringBoard/backboardd SIGSTOPed (states verified), twenty resumed,
  including ten with page swipes and interleaved display frames. All 41 audits:
  no live GEM handles/maps/queues, no transport errors, successful service close.
  Reused first-allocation IOVAs and quiet wired-memory plateau show no observed
  accumulating leak; this is not a proof of all kernel/long-duration leak freedom.
- **FACT:** current service is `HakiosGPU`, not assumed `RedwoodGPU`; explicit
  RedwoodGPU discovery fails. No kernel ABI patch needed. ABI, limitations,
  reproduction and evidence: `docs/metal-transport-abi.md`, `metal-step5-*`.
  Vayu's FAULTS parameter is hardcoded zero; do not treat it as reset telemetry.
- **FACT (execution adjustment):** temporary uploads plus the existing init
  rc.jobs runner, no root-image replacement/reboot/partition command. Isolation
  used stopped UI processes with retained resources, not a boot before UI exists;
  that startup-only case remains untested. Independent watchdog resumes stopped
  processes. Final original UI PIDs resumed, phone responsive, battery 33 C / 90%.
- **FACT (build):** WSL pull refused unrelated dirty work; preserved it, synced
  only two driver sources. 261 host tests / zero failed checks, fake stages 1–4
  pass, iOS library/probe/runner cross-built. No compiler enabled, no shaders run.
  Task 5 transport acceptance complete with the isolation adjustment above;
  task 6 (compute fixtures on A640) is next. Stay on the existing GL fallback.

## Metal step 4 (2026-11-07; freedreno reference captures on the phone)

- **FACT (run `metal-step4`, `docs/metal-step4-validation.log`):** new off-screen
  `userland/src/gl_reference.c` passes clear, textured triangle, MRT, blending
  (all pixels) and compute (64 SSBO uints) on FD640 / Mesa 25.0.7. Existing
  `FD_RD_DUMP=enable,full` generated ten submissions, collected with byte-count,
  gzip CRC and SHA256 checks in ignored `logs/metal-step4/`. Native Mesa 25.0.7
  `cffdump` built from the verified archive decodes all ten as chip 0x06040001,
  exit 0, empty stderr. Index: `docs/metal-reference-captures.md`; tracked
  manifest/decode summary/validation log alongside it. Preserve the ignored
  capture directory for later hakios-metal comparisons.
- **FACT:** all graphics primaries use 32x32 GMEM bins; no visibility-binning
  packet. This is basic freedreno correctness evidence, not hakios-metal hardware
  validation or a performance result. Phone stayed in the current iOS/GL session;
  no reboot, image replacement or partition commands. Temporary executable and
  filesystem dumps only; command port pong afterward, battery 34 C / 90%.
- **FACT (build):** WSL pull refused existing unrelated dirty work; preserved it.
  New build/capture/decode scripts under `tools/metal-reference-*`. Phone job
  cross-built from Windows source; native decoder in WSL's separate
  `~/vayu/xnu-deps/build/mesa/metal4-native-*`; normal Mesa not reconfigured.
  Task 4 complete; task 5 (hakios-metal transport probe) is next.

## Metal step 3 (2026-11-07; Mesa audit and host checks, phone not used)

- **FACT (source):** A640/gen2 table in `docs/metal-driver-inventory.md` compared
  against pinned Mesa 25.0.7 (archive SHA256 verified). Fixed GMEM framebuffer
  fetch adding vayu's `0x100000` base (old A635 zero-base assumption), and missing
  WFM before indirect draws (a630 SQE/gen2 firmware quirk). Fake bounds and host
  packet/descriptor checks updated. Shader tools now default to A640; GMEM/CCU,
  magic registers, cache event encodings, LPAC and limited UBWC otherwise match.
- **FACT (`docs/metal-step3-register-check.log`):** 1879 header constants match;
  80 marked non-header constants documented. Checker supports integer division;
  header annotations repaired. **FACT (`docs/metal-step3-build.log`):** WSL
  `make -C ~/vayu/hakios-metal -j3 vayu-check CXX=clang++`: 261 host tests / zero
  failed checks, arm64 iOS library/probe built, fake stages 1–4 / zero failures.
  No phone operations or MESA=1. WSL pull again refused unrelated dirty work;
  preserved it and synced only driver files. Firmware startup remains kernel-owned.
  Task 4 is next: reference command-stream captures on the phone.

## Metal step 2 (2026-11-07; source audit, phone not used)

- **FACT (source at `bc19b43`):** task 2 done in
  `docs/metal-driver-inventory.md`: Metal feature/core/plugin coverage and hardware
  paths, each with file:line evidence. The bundled Objective-C plugin has real
  buffer/library/buffer-blit paths but placeholder textures/samplers/pipelines and
  no render/compute encoders; its device name still says A642L. These gaps are now
  explicit in roadmap tasks 8–10.
- **FACT (source):** restricted GMEM, VSC hardware binning, Mesa-dependent UBWC,
  profiling, async submission/pools/deferred recording and load/store elision
  already exist in the core; LRZ is disabled. Tasks 13–17 now reuse/validate those
  paths before extending them. No driver code changed, no new runtime validation
  claimed; step 1's no-Mesa/fake results still apply. Task 3 (A640 constants versus
  our Mesa, with fixes and host checks) is next; no phone needed for that audit.

## Metal step 1 (2026-11-07; phone not used)

- **FACT (`docs/metal-step1-build.log`):** task 1 done: `hakios-metal/` vendored from
  upstream `63fc2b4633bac3af8e57dadab9f5a8d4cb940438`, MIT; 0040/0043 ported.
  Clean WSL driver build: `make -C ~/vayu/hakios-metal -j3 vayu-check CXX=clang++`:
  arm64 iOS archive + probe built, 261 host tests / 0 failed checks, fake probe
  `--stages 4` / 0 failures. No phone commands. Pin, patch conflicts, build details
  and AIR choice in `hakios-metal/VAYU.md`; task 2 is next.
- **FACT (source):** driver uses Mesa's AIR frontend, not a second implementation.
  Choose `tools/mesa/air` as the one frontend; its API is older than the pinned
  driver's. Baseline has no `MESA=1`, so live AIR compilation is not validated;
  reconcile APIs before task 9. Extra upstream fixtures beyond 0043 also need
  A640 validation before hardware use. WSL pull refused unrelated local changes;
  preserved them and synced only the new driver directory for the build.

## Active handoff (2026-11-07 ~05:50: Wi-Fi step 3 -- joined from Settings, internet works; Safari freezes)

- **FACT (run wifi10, logs/wifi10-net.txt, git-ignored):** with `vayu_wifi_ios=1` added to the step 2 args, en0
  appears after the first scan, wifid's scans run on demand (W26 scan #N, ~2.2 s for 13-26 channels), Settings
  lists the networks, a 2.4 GHz WPA2-PSK/CCMP network joined from Settings with the typed password (4-way OK, keys
  in), configd got an address by DHCP. First minute: tx 698 / rx 1841 frames (2.2 MB), 0 dropped; 4 early tx
  completions status 1. `userland/src/net_test.c` (built by hand with xnu-clang against the SDK, unsigned, pushed
  to /private/var/tmp): DNS 0.03 s, TCP to Apple's captive host 0.06 s, "HTTP/1.0 200 OK" in 0.15 s.
- **FACT:** Safari still freezes (its WebContent/Networking/GPU processes start) -- not the network (net_test).
  Next to look at. HYPOTHESIS: WebKit's GPU process / rendering on this port, not Wi-Fi.
- **FACT (run wifi9):** a 5 GHz network refused the association with status 18 (rates): our assoc request has no HT
  IE (the author's W23 path, legacy rates only). iOS says "move closer". Next: HT capabilities in the assoc
  request and PEER_ASSOC.
- **FACT (run wifi9):** once en0 had an address, the USB link (169.254.7.2) died -- log, command port, sweetd (XNU
  keeps IPv4 link-local on the primary interface). The user pointed at jasmine (j0087-j0089). Now (vayu_usbnet_ecm.c,
  usbnet_static=1): en2 also 192.168.7.2/24 (added first), scoped routes 169.254/16, 192.168.7/24, 255.255.255.255,
  the kernel's 5140/5141 listeners bound to en2 (IP_BOUND_IF), and a DHCP server giving the PC 192.168.7.1/24 (no
  router, no DNS). Its replies are whole frames handed to usbnet_output(): through the socket they always failed
  ENETUNREACH (runs usb10, usb11; address order did not matter). The PC tools try 192.168.7.2 first. Run wifi10:
  the USB link stayed up while joined.
- **Code (W26):** hakios.apple80211.c / hakios.sta.c / hakios.sta.h are jasmine's (j0093 LQM event 39 + quality
  every 5 s, j0095, j0098 RSSI_BOUNDS -100/0/-80, noise -95). vayu_wifi_net.c: the station service -- wifid's
  requests are handed to the radio's thread (the only one that may poll the CEs / send WMI) and answered from there;
  ops scan/heard/join/leave/state/channels/power. vayu_wifi_scan.c: the BSS list keeps name, channel, signal,
  elements (768 B), age; vayu_scan_again(). vayu_wifi_sta.c: vayu_sta_join_asked() (any SSID, best RSSI, open or
  WPA2-PSK/CCMP; errors ENOENT/ENOTSUP/EAUTH/ECONNREFUSED/ETIMEDOUT), leave in jasmine's order (DEAUTH, PEER_DELETE
  until PEER_DELETE_RESP 0x6007 / HTT PEER_UNMAP, VDEV_DOWN, VDEV_STOP), MODE_11G on 2.4 GHz. vayu_wifi_rsn.c: the
  key from wifid (PMK, or PBKDF2-SHA1 of the passphrase), never logged. vayu_wifi.c: MAC from fw/wlan_mac.bin if
  there (vayu's persist has no wlan_mac.bin; the fixed 02:50:49:58:45:4c otherwise). While joined, scans answer
  from the list (no off-channel scan).
- configd: /private/var/preferences/SystemConfiguration/preferences.plist had no services; now jasmine's en0 Wi-Fi
  service (tools/wifi-root-config.py's configure()), original beside it as preferences.plist.before-wifi.
- `boot` holds 0c82c913... (kernel 734bff34...; ../backup-vayu/xnu-standalone-wifiios-0c82c913.img), args =
  the step 2 args + `vayu_wifi_ios=1`. Arming as before (modem.mdt put/rm per boot).
- **FACT, open:** the loader's USB command mode ("loader" from iOS: flag + restart) came up dead twice after the
  05:03 flash (Windows sees a fastboot device, serial unreadable, every command times out; gone after a replug);
  11 earlier transitions worked. Since then flashed from vayu's stock fastboot (volume down + power,
  `standalone.sh flash`). Cause not known (kernel af1e6779? the power-key restarts before both?). Also: the
  loader's USB mode shows briefly on EVERY boot -- not a state to flash into.
- **FACT (trial L1, 2026-11-07 12:57, logs/loader1-before.txt):** modem NOT armed this boot (modem.mdt never put,
  the 600 s wait ran out; so no Wi-Fi), iOS up ~6.5 h, same boot/kernel as the two failures (0c82c913): "loader"
  from iOS -> loader 2.5 answered fastboot at +20 s (product xnuloader, version 2.5, max-download-size), still
  answering a little later. HYPOTHESIS strengthened: the hang needs the modem / Wi-Fi running at the reset.
- **FACT (trial L2, 13:00, logs/loader2-net.txt):** fresh boot (fastboot reboot from the loader), modem armed
  (found after 43 s), Wi-Fi auto-joined (4-way OK, en0 link up), iOS up ~2.5 min: "loader" -> loader 2.5 answered
  at +20 s again. So the modem / Wi-Fi running at the reset is NOT enough to hang it (L1 + L2: 2/2 OK). The
  HYPOTHESIS above is weakened; left: what came before the two failures (power-key restarts? the flash just
  before?), or a rare race (2 of ~15).
- **Desk work (transcript, 2026-11-07 ~13:10; times local):** THREE dead loader sessions, not two, all 05:17-05:31:
  H1 05:17:50 ("loader" ~10 s after phone.sh first said ios; then an unnamed fastboot device, serial ????????????),
  H2 05:25:00 (~6 s after pong; AdbWriteEndpointSync timeouts), H3 05:30:59 (~1 min after iOS). FACT: each came
  after a forced restart by the user (05:15/16 when the USB link died under Wi-Fi; after H1; after H2). FACT:
  every good trip (11 between 04:09 and 05:04, L1, L2) came after a software reset (the loader's cold
  ResetSystem, fastboot reboot) -- none after a forced restart. FACT: loader.efi is the same in every image
  (4894c29548c13fed, built 02:56: af1e6779, 3b6ea36f, 572a6527, 0c82c913) -- the loader binary is ruled out;
  the kernel never runs in that mode. FACT (loader.c): after the flag, usb_start() then usb_command_loop(),
  which resets after 120 s without a host command (1.0), the watchdog armed; in the hangs the logo stayed for
  minutes, no reset -- so the loader is stuck inside a call (USB start / its first transfers: Windows got the
  device descriptor, not the serial string), not idling in its loop. The resets are all EfiResetCold.
  HYPOTHESIS (best fit): the hang needs a forced (PMIC) restart earlier in the chain -- something it leaves
  (USB PHY / charger detection / PON state) survives the loader's soft cold reset. Second candidate: "loader"
  too soon after boot (H1, H2 within seconds), but the step-2 runs deployed right after "ios" too, and worked.
  Next: trial L3 = forced restart, settle in iOS >= 2 min, "loader". Recovery from a hang = a forced restart
  (05:24 it came back into iOS that way); then "oem prevlog" in the next loader session, in case logdump kept
  the dead session's last words.
- **FACT (trial L3, 13:08-13:11, logs/loader3-net.txt):** the user's forced restart (power held, from loader
  mode), iOS settled (pong 13:08), modem NOT armed, 2 min wait, "loader" at 13:10:27 -> at +20 s Windows lists
  "????????????  fastboot", then nothing ("waiting for any device"): the hang REPRODUCED. With L1/L2 (software
  reset before, OK): a forced restart earlier in the chain is what it needs (3 of 3 before + L3; 0 of 13 OK
  ones had one). Not the modem, not the uptime, not the loader binary.
- **FACT (trial L4, 13:14-13:18):** the user's forced restart out of L3's dead loader -> iOS; then a software
  "reboot" (13:14, iOS again 13:15), 2 min settled, "loader" 13:17:45 -> loader 2.5 answered at +20 s (product,
  version, max-download-size). So one software (cold ResetSystem) reset clears what the forced restart left.
  Reading: the bad state is made by the boot that follows a forced restart and lives only until the next reset
  -- i.e. something the boot chain (XBL/ABL/loader) sets differently after a PMIC reset, not damage.
- **Correction:** the "idle reset after 120 s" applies only after a kernel's return, and on vayu the watchdog is
  never armed (its SMCs return -1) -- so "no reset during the hangs" said nothing about where it hung.
- **Loader 2.6-marks** (xnuloader/loader.c, debug, flag path only; loader 83c3dd9a, image de64333e =
  ../backup-vayu/xnu-standalone-marks-de64333e.img, kernel 734bff34 unchanged): a bar per step through GOP Blt
  (1 flag cleared, 2 USB init event, 3 protocol, 4 start_ex, 5 buffers, 6 USB started, 7 logdump read, 8-11 write /
  written / flushed / read back, 12 command loop, 13 stack says connected, 14 gone, 15 a command arrived) and a
  square flipped every 0.5 s by usb_wait(). (Colours come out green/orange and white/blue: RGB order, cosmetic.)
  Control run 13:33 (software chain): OK, bars and a blinking square.
- **FACT (trial L5, 13:35-13:39, photo):** forced restart, iOS 2 min, "loader" -> ???????????? at +45 s, getvar
  timed out. Screen: 13 bars, text "log: 4096 bytes written to logdump (0), read back the same (0)", the square
  FROZEN. So: flag, USB start, the logdump write all fine; the command loop ran, Qualcomm's USB stack reported
  "connected" -- then this core never came back from a call into that stack (handle_event / send), before any
  command. The hang is inside Qualcomm's UEFI USB device driver during enumeration (the PC got the device
  descriptor, not the serial string). Not storage.
- **Loader 2.6-snap** (cdc08a07, image a296b56a = ../backup-vayu/xnu-standalone-snap-a296b56a.img): read-only
  dumps (GCC USB clocks/GDSC/BCRs, DWC3 + QSCRATCH when clocked, PMIC PON / PM8150B Type-C / USBIN / DCDC / misc
  through the observer channel, TPL high per read) at 1 before usb_start, 2 after it, 3 at the first "connected"
  (printed to the screen there); bars moved down, 16/17 around the receive's queueing (USB->send).
- **FACT (trial L6, 13:52, photo):** a GOOD chain (forced restart, then two software resets) with 2.6-snap HUNG
  the same way: ???????????? at +20 s; snap1-3 all printed; bars 1-13, 16, 17 (no 14, no 15); square frozen.
  So: the receive was queued (send returned), then the core never came back from handle_event. And the snapshot
  code -- which delays the pumping of the stack right after usb_start (snap2) and at "connected" (snap3, three
  long lines through the firmware's slow text console) -- made a good chain hang. HYPOTHESIS (best fit now):
  Qualcomm's UEFI USB stack wedges inside handle_event if it is not pumped promptly while the host enumerates;
  the forced-restart chain makes the gap after usb_start longer somehow (to measure). 2.5 already does slow work
  in that gap: three console lines and the logdump write+read-back (flush_log) between usb_start and the loop.
- **FACT (trial L7, 14:03, photo):** 2.6-order (5a2999b0: log written and console lines BEFORE usb_start, the loop
  right after, snapshot 1 still taken before USB) on a good chain: HUNG, same spot (bars 1-13, 16, 17, square
  frozen). snap1 (before usb_start): the controller already powered and clocked (GDSC on, master clock on), DSTS
  0x420004 (halted), GCTL 0x102000 -- left on by an earlier stage.
- **FACT (trial L8, 14:15):** 2.6-order-nosnap (loader 1c9e132f, image 0530ab82, flashed through stock fastboot;
  no register/PMIC reads at all): forced restart, iOS ~30 s, "loader" -> ???????????? at +20 s: HUNG. So the
  order (slow work before USB) does NOT fix it; the timing HYPOTHESIS is refuted for that gap. Still standing:
  stuck inside Qualcomm's UEFI USB driver (handle_event) after the first receive is queued; reliable after a
  forced restart, and seen twice on good chains with the snapshot loaders (PMIC reads suspected there).
- **FACT (trial L9, 14:24):** loader 2.7-corereset (c57af185, image b7820c77, flashed through stock fastboot):
  before usb_start, if powered and clocked, DEVTEN 0, RUN_STOP off until halted, DCTL.CSFTRST until clear (as
  vayu_usbnet.c dwc3_take). Forced restart, iOS ~30 s, "loader" -> ???????????? at +20 s: HUNG. A DWC3 core soft
  reset before Qualcomm's start does not fix it.

## Earlier (2026-11-07 ~05:00: Wi-Fi step 2 done -- the radio scans under iOS)

- **FACT (run wifi8, logs/wifi8-net.txt, git-ignored: it has nearby SSIDs):** modem up through TrustZone PAS, WLFW
  (chip 0x30224, fw WLAN.HL.3.0.c2-00417), BDF + MAC + CAL_REPORT, FW_READY, WLAN_CFG + MISSION, CE rings,
  HTC READY (22 endpoints, clamped to 8), CONNECT WMI/HTT, SERVICE_READY, INIT, WMI READY, HTT 3.70, passive scan
  26 channels: 6 BSSIDs on ch 6/13/36/40, -68..-82 dBm. iOS stayed up (sweetd/command port answer), 35 C, no PFR.
  Regulatory from the firmware: country CN (to fix later: the phone is in Hungary).
- `boot` holds xnu-standalone.img 9dba0c7e... (kernel 2dc1507a..., loader 4894c295, same root-flash/flashboot;
  ../backup-vayu/xnu-standalone-wifiscan-9dba0c7e.img). standalone.sh's default ARGS are NOT changed: the Wi-Fi
  args go in STANDALONE_EXTRA:
  `vayu_modem=3 vayu_modem_listen=86400 vayu_modem_fw_wait=600 vayu_rmtfs=2 vayu_wifi=2 vayu_wifi_qdss=1
  vayu_wifi_mac=1 vayu_wifi_bus=1 vayu_wifi_reattach=1 vayu_wifi_smmu=1 vayu_wifi_smmu_ttbrfix=1 vayu_wifi_ce=1
  vayu_wifi_ce_addrmask=1 vayu_wifi_htc_connect=1 vayu_wifi_wmi=8 vayu_wifi_scan=1 vayu_wifi_htc_lenient=1`
- Firmware: does not fit the 64 MB payload (UEFI's fixed window at 0xF0000000; with modem 38 MB zlib the payload
  was 70.6 MB). Now on the phone in /private/var/hakios/fw (HFS on darwin): modem.bNN, wlanmdsp.mbn, modem_pr/
  (MCFG, from ../backup-vayu/20261106/modem.img), *.jsn, uploaded with sweet-sh.py --put (235 files, sizes checked).
  hakios.image.c: hakios_image_file() falls back to /private/var/hakios/<dir>/<name> (kept in memory).
  vayu_modem.c: step 2 waits up to vayu_modem_fw_wait s (default 300) for fw/modem.mdt.
- **Arming (safety):** modem.mdt is NOT kept on the phone. Per test boot: put fw-poco-x3-pro/modem.mdt to
  /private/var/hakios/fw/modem.mdt, wait for "fw/modem.mdt found", rm it (the kernel keeps its copy). A crash then
  reboots into plain iOS with the modem waiting (it gives up after 600 s): no button press needed. Used 8 times.
- What each fix was (FACT, one run each): wifi1 plain: WLAN PD crash after CAL_REPORT (EX:wlan_process RT:0x3092
  PC 0xb0193960) -> wifi2 `vayu_wifi_qdss=1 vayu_wifi_mac=1` (rails + AOP qdss clock before the modem, MAC_ADDR):
  FW_READY; then the SoC froze at the first CE DMA (wifi2-5; wifi4/5 with the new debug `vayu_wifi_ce_slow=MS`
  in vayu_wifi_ce.c: logs each step and the first 400 CE accesses with a pause, found it after RX posting) ->
  wifi6 `vayu_wifi_smmu_ttbrfix=1` (TTBR0 had only the ASID: the WLAN SMMU context walked tables at PA 0): no
  freeze, HTC READY arrives -> wifi7 `vayu_wifi_ce_addrmask=1` (flag bits 0x3000... in the RX descriptor address)
  -> wifi8 `vayu_wifi_htc_lenient=1` (READY says 22 endpoints): scan. `vayu_wifi_bus=1` (SNOC keepalive) is in
  but was not shown to matter.
- Next (step 3 of the plan below): jasmine's iOS layer on top -- wifid scan results/join, RSSI_BOUNDS, LQM, ADT
  `wlan` node, configd en0 service, MAC from persist; then the arming goes away (modem.mdt stays) once the start
  is trusted. Also: regulatory domain (CN).

## Wi-Fi plan (2026-11-07, agreed with the user)

The author's vayu radio code underneath, ios-jasmine's iOS layer on top. Steps: 1 firmware + boot settings (done,
below); 2 radio and scan only; 3 jasmine's iOS layer (wifid answers incl. RSSI_BOUNDS 106 and LQM event 39, ADT
`wlan` node, configd en0 service, MAC from persist, Settings off/on = real leave), first join from Settings; 4 clean
leave/stop in jasmine's order (peer delete before vdev down); 5 on by default + jasmine's acceptance checks.
The author's kernel-side join to a fixed network with a PMK file (vayu_wifi_join/pmk_file) is NOT used (user).

- FACT: same chip family as jasmine (WCN3990, ath10k-snoc protocols, WLFW on the modem), different SoC around it:
  vayu boots the MPSS through TrustZone PAS (vayu_pas.c, pas-id 4), RPMh rails, other addresses.
- FACT: firmware reaches drivers only through hakios_image_file("fw", ...) = fw/ of the RAM disks md1/md0
  (hakios.image.c); compressed APFS files are read out into kernel memory. In the flashed boot md1 =
  root-flash.apfs (fw/: GPU, touch, BT, ipa_fws, bdwlan.bin) and md0 = flashboot.apfs (no fw/).
- FACT: missing from the images: modem.mdt + modem.bNN (77.5 MB, the modem driver's header: ~38 MB compressed),
  wlanmdsp.mbn (4.05 MB), and the TFTP tree the modem reads (modem_pr/mcfg/configs/... and *.jsn: not pulled,
  source ../backup-vayu/20261106/modem.img, FAT). day1.sh drops modem/wlanmdsp from root.apfs because the loader
  takes one download of at most 63 MB (0x3f00000); the boot partition is 128 MB, today's image 14 MB.
  regdb.bin is not needed (vayu_wifi_regdb=0 default).
- INFERENCE: the cheapest fit is the modem files compressed (not --plain) in root-flash.apfs: ~14 + 38 + ~3 MB <
  63 MB. Fallback: read fw from /private/var (HFS on darwin, sweetd `put` can fill it) by a vnode path.
- FACT: the author's exact run command lines are not in the repo (their runs were RAM boots with system.apfs /fw).
  INFERENCE for step 2 from the code: vayu_modem=3 vayu_modem_listen=86400 vayu_rmtfs=2 vayu_wifi=2 + the
  CE/HTC/WMI/scan chain (vayu_wifi_ce, vayu_wifi_htc_connect, vayu_wifi_wmi, vayu_wifi_scan=1); to be read out of
  the code before the run. No vayu_cell (mobile data hangs the SoC, author). Watch the temperature.

## Earlier (2026-11-07: the battery on in `boot`)

- **FACT (2026-11-07, later):** `boot` now 65d7eede... = 88bc4689 plus `vayu_wled=2` (88bc4689 kept in
  ../backup-vayu/xnu-standalone-battery-88bc4689.img). Before it the backlight stayed lit with the screen "off": iOS did
  send DisplayBrightnessFactor(WithFade) 0/1 on lock/wake, but no backlight driver ran. Now (logs/wled2-net.txt):
  WLED control channel 334 and sink 335 written by system 0 (us), strings 0-3 on modulator A, brightness 491/4095,
  "writes allowed", "backlight on". FACT (user, on the screen): dark on lock, back on wake, the brightness slider works.
- **FACT (logs/wled-net.txt):** with the screen off SpringBoard sets digitizerEnabled NO + WakeOnTapEnabled; vayu_nvt.c
  has no hook for it, so every touch is a normal touch and the screen wakes at once (pocket touches). Next for touch.

- **FACT (2026-11-07):** `boot` holds xnu-standalone.img 88bc4689... = 4b79c0ce plus `battery=1` on the command line (same
  kernel 87b9c382, loader 4894c295; 4b79c0ce kept in ../backup-vayu/xnu-standalone-usbshell-4b79c0ce.img). Deployed by
  `phone.sh deploy` alone (1 min 48 s). Before: no `battery=1`, so kern.hakios.battery_soc -1 and iOS's UserEventAgent
  "Unable to look up battery voltage". `buttons` needs nothing: it is on with touchscreen=1 and maps the SPMI arbiter
  that hakios.battery.c reads through.
- **FACT (logs/battery1-net.txt, on the PC's USB port):** fuel gauge 100% (raw 255/255), 4395 mV, -2..-7 mA, 32-33 C
  (rradc raw 0x20); charger PLUGGED IN, CHARGER_STATUS_1 7 ("disabled"), not charging; limits read only: FCC 1500 mA,
  USB ICL 1500 mA, AICL ICL 600 then 1050 mA, APSD 0x4 (CDP). USB stayed up with the loader's UEFI charger polls.
- **FACT:** battery_test: HakiosBattery is the kernel's IOPMPowerSource (CurrentCapacity 100, ExternalConnected,
  FullyCharged); IOPSGetPercentRemaining 100%, full, "AC Power"; but "powerd lists no power source" (IOPSCopyPowerSourcesList
  empty). HYPOTHESIS: run as root from sweetd rather than a real empty list; the status bar not looked at yet.
- **INFERENCE:** status 7 at 4.395 V is UEFI's/the PMIC's stop at full (not 5 "terminated"); whether it charges from a
  low battery under XNU, and at what current, is not seen yet (needs a run off the cable, then on it).

## Earlier (2026-11-07 ~03:10: the test loop is closed -- iOS, loader, flash, iOS with nobody at the phone)

- **FACT (2026-11-07 02:5x-03:04):** `boot` holds xnu-standalone.img 4b79c0ce... (loader 2.5 4894c295..., kernel
  87b9c382...). Twice without a hand on the phone (looptest + `phone.sh deploy`): iOS -> `sweet-cmd.py loader` -> our
  loader on USB in 3 s -> `fastboot flash boot` (flash:boot: 14080000 bytes, read back the same) -> reboot -> iOS
  answers at +50 s (var boot counter 17, 18).
- The tools (devices/poco-x3-pro/tools): `phone.sh state|loader|flash|reboot|deploy|sh|log` (the loop);
  sweet-sh.py (sweetd, TCP 5143: programs + built-ins ls cat sysctl put rm mkdir kill); sweet-cmd.py (kernel, TCP
  5141: reboot, loader, ping); sweet-netlog.py (kernel log, TCP 5140, whole boot then live). In our loader's USB
  mode xl works as after `xl enter` (xl run from RAM, xl log).
- Kernel (vayu_usbnet_ecm.c): the ports from ios-jasmine (0077/j0021/j0022). "reboot" and "loader" never go
  through iOS's shutdown: reboot_kernel() from the command thread hung after unmounting /dev (run 020558, 7.5 min);
  instead sync() then loader_live.stop (the "xl stop" path). "loader" first writes "XNULOADR" into darwin block
  3145727 (hakios.ufs.c hakios_ufs_loader_flag; the end of var_store's unused second slot).
- Loader 2.5: a standalone start finds the flag, clears it (the next start is iOS again whatever happens), starts
  USB and takes commands (usb_command_loop) -- a fresh-boot USB start, the path `fastboot boot` takes. flash:boot
  writes the partition named exactly "boot" from the last download (ANDROID! magic, size checked) through a 1 MB
  UEFI pool buffer, watchdog fed per chunk, read back. FACT: writing straight from PAYLOAD_BASE took the phone down
  mid-write (02:3x); FACT: staying in the loader after a run (reboot_mode 3, USB stack restarted after the
  handover) did not enumerate until a replug, then "unknown USB device" -- not used any more.
- Stock fastboot without buttons: NOT possible so far. FACT: PON SOFT_RB_SPARE (PM8150 0x88f) is SPMI channel 1,
  owned by system 1, not apps (run 020558); FACT: UEFI ResetSystem cold with ABL's RESET_PARAM mode 2 rebooted
  into iOS (loader 2.4; 2.5 tries warm first, untested). Not needed for the loop; stock fastboot (buttons) is the
  way back if a flashed boot does not start: ../backup-vayu/xnu-standalone-hfs.img (cd3e34b5, no USB shell).
- Next: whatever the user wants worked on -- the agent can now build, deploy and inspect on its own.

## Earlier (2026-11-07 ~01:50: iOS in `boot` with the USB shell; the agent reaches the phone itself)

- **FACT (2026-11-07 ~01:50):** xnu-standalone.img a4373c63... flashed into `boot` (user's OK), `fastboot reboot`:
  ping 169.254.7.2 at +77 s, sweetd answered (var boot counter 8, the four usbnet args in kern.bootargs, ps -A with
  SpringBoard). Loader 2.3's standalone USB start is confirmed. Rollback: ../backup-vayu/xnu-standalone-hfs.img.

USB shell (2026-11-07 01:1x-01:3x):
- FACT: the kernel's USB networking (vayu_usbnet=3, usb_handover=1) was CDC-ECM, which Windows has no driver for.
  vayu_usbnet_ecm.c now speaks CDC-NCM by default (usbnet_ecm=1: ECM): IAD + subclass 0x0d descriptors (product
  0xd00f), the NCM class requests (an ep0 OUT data stage for SET_NTB_INPUT_SIZE/SET_MAX_DATAGRAM_SIZE), NTB-16 in
  (any number of frames) and out (one per block, pad byte instead of a ZLP), layout from ios-jasmine's sweet_usb.
  Also jasmine's mbuf fix (one mbuf + cluster; mbuf_allocpacket's empty first mbuf panicked there).
- FACT: usbnet_static=1 usbnet_ip=0xa9fe0702: en2 = 169.254.7.2/16, no default route. Windows' UsbNcm adapter
  gives itself a 169.254 address (nobody answers its DHCP), so the PC needs no setup.
- FACT: loader 2.3 (loader.efi 118fa46c...): a one-shot (standalone) boot with usb_handover=1 starts the UEFI USB
  stack before the kernel, else the kernel's usb_take went unanswered (3 s, "left alone"). Tested only via xl so far.
- FACT: sweetd (userland/src/sweetd.c, from ios-jasmine, MIT, same author) is a launchd job (com.hakios.sweetd),
  root, TCP 5143; token userland/sweetd.token (made by build.sh, git-ignored, copied into the image as
  /redwood/etc/sweetd.token). iOS has only /bin/ps and /bin/df, and the flash has no Procursus prefix, so sweetd has
  built-ins: ls cat sysctl put rm mkdir kill. Client: devices/poco-x3-pro/tools/sweet-sh.py (Windows python;
  MSYS_NO_PATHCONV=1 from Git Bash), `--put LOCAL REMOTE [MODE]` uploads.
- FACT: xl runs 012613 and the next (240 s / 150 s, flashboot.apfs resident): Windows enumerated it, ping
  169.254.7.2 answered from ~45 s after the start until the run ended; sweetd ran sysctl/cat/ls and /bin/ps -A
  (var boot counter 7). Windows asks for string 0xEE (MS OS descriptor): stalled, harmless.
- Images: kernel 98cb2a20..., root-flash.apfs a447c783..., flashboot.apfs 2ed5d333... (unchanged);
  xnu-standalone.img a4373c63... (standalone.sh's default cmdline has the four usbnet args). NOT flashed yet: `boot`
  still holds cd3e34b5..., kept as ../backup-vayu/xnu-standalone-hfs.img (rollback).
- Next: Procursus (or a toolbox) via `put`; MS OS descriptors are not needed.

## Earlier (2026-11-07 ~01:00: iOS in `boot`, starts by itself, /private/var is HFS Plus on the flash)

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
