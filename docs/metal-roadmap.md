# Metal on vayu: the task list

Goal: a working, hardware-accelerated Metal device on the POCO X3 Pro (Adreno 640, a6xx gen2):
`MTLCreateSystemDefaultDevice()` returns a device, real Metal programs and system frameworks draw and
compute with it, and it is fast because it uses the A640 well.

Decision (2026-11-07, user): the **HakiOS direct driver** (`hakios-metal`: Metal objects → our own
runtime → PM4 command streams; AIR → NIR → ir3). It is the path closest to the hardware. Turnip and
metal2vulkan are **not** a competing option. They and freedreno are references for what correct A640
command streams look like. The background is `../../METAL-IMPLEMENTATION-RECOMMENDATION.md` (outside
this repository).

## How to use this file

One agent takes **one task**: the first one not marked done whose dependencies are done. Each task
ends in something the next agent can build on (a commit, a log, a document) and in an update here.

Every agent, every task:

1. Read `AGENTS.md`, the active handoff at the top of `NOTES.md`, and this file. Follow `AGENTS.md`:
   commit on `vayu-dev`, never push to `author`, build images in WSL's `~/vayu`, boot from RAM only,
   ask the user before anything that writes to the phone's partitions.
2. Label claims **FACT** (seen, with the log or run ID), **INFERENCE** or **HYPOTHESIS**. "Passes on
   the fake GPU" and "passes on the phone" are different facts. Say which one you have.
3. When finished: tick the task's box, fill in its **Result** line (commit, run ID, log name, what is
   still open), add a line to the `NOTES.md` handoff, and commit. If the task turned out wrong or too
   big, split it here and say why instead of stretching it.
4. Run only the drivers a test needs. The full driver set overheats the phone in about a minute.
   Keep the GL window server (`src/eagl.c`) working as the fallback until task 11 replaces it on
   purpose.

## What already exists (start here, don't redo it)

- **Kernel GPU service.** The fork starts the Adreno with `gpu=1 vayu_gpu=1 vayu_keep=1`
  (`bsd/dev/vayu_adreno.c`, IOKit service `RedwoodGPU`, an msm-DRM-like interface). The GL window
  server already draws through it: Mesa freedreno via `tools/mesa/hakios-drm`, `userland/src/eagl.c`.
- **AIR → NIR frontend** inside our Mesa (`tools/mesa/air`, `air-frontend.patch`, `air-ir3.patch`;
  `docs/air.md`, `docs/air-report.md`). It reads 456/456 system `.metallib` modules and turns 321 of
  them into ir3 code. Its on-GPU results were recorded on the author's Adreno 7c+ Gen 3, not on vayu.
  Section 7 of `docs/air.md` lists what it requires of a runtime.
- **How iOS finds Metal** (`docs/ru/metal.md`, `userland/src/metal_test.m`, `rc.jobs.metal`): an
  `IOAcceleratorES` service with `MetalPluginName`/`MetalPluginClassName` → a bundle in
  `/System/Library/Extensions` → a subclass of `_MTLDevice` → `-initWithAcceleratorPort:`. A bare
  `IOAcceleratorES` stub is in `xnu/files/iokit/Kernel/MiniIOMobileFramebuffer.cpp`.
- **A640 port of hakios-metal, vendored in task 1** (`hakios-metal/`, pinned upstream
  `63fc2b4633bac3af8e57dadab9f5a8d4cb940438`; see `hakios-metal/VAYU.md`):
  `docs/vayu-patches/0040-hakios-metal-a640-gen2-port.patch` (chip id
  0x06040001, gen2 chip facts, no LPAC, the `RedwoodGPU` transport, `probe --stages`) and
  `0043-hakios-metal-a640-fixtures.patch` (test shaders regenerated for FD640). Task 1
  built the arm64 library/probe and passed 261 host tests plus fake-probe stages 1–4;
  no vayu hardware validation yet. Additional upstream fixtures are not yet ported.
- **Upstream** keeps hakios-metal in `oosexgang/hakios-xnu-kernel`, `main`, `hakios-metal/`, with
  `docs/reference/metal.md` (integration) and `metal-measurements.md`. The old standalone repository
  `oosexgang/hakios-metal` points there.

## Tasks

### Phase A: the driver source, building and checked

- [x] **1. Bring hakios-metal into the tree and build it.**
  Depends on: nothing.
  Do: choose and pin an upstream revision of `hakios-metal/` and record why that one. Bring it in on
  `vayu-dev` (as a subtree or vendored directory, with its licence and a note in
  `THIRD_PARTY_LICENSES.md`). Apply 0040 and 0043, resolving conflicts against current upstream and
  writing down every hunk that no longer applies, and why. Build the library, `probe` and the host
  tests in WSL. Find out whether upstream hakios-metal has its own AIR frontend or uses Mesa's, and
  how that relates to our `tools/mesa/air`. Choose one, and say which.
  Done when: one build command produces the library and tests from a clean `~/vayu`; the host test
  suite passes against `fake_gpu` (FACT, with output); the choice of AIR frontend is written down.
  Result: **FACT (2026-11-07, `docs/metal-step1-build.log`):** vendored `hakios-metal/`
  from upstream `63fc2b4633bac3af8e57dadab9f5a8d4cb940438`, MIT notices preserved;
  0040/0043 applied (one compiler diagnostic hunk resolved manually). Clean WSL driver
  build: `make -C ~/vayu/hakios-metal -j3 vayu-check CXX=clang++` after `make clean`:
  arm64 iOS archive and probe built, 261 host tests / 0 failed checks, fake probe
  `--stages 4` / 0 failures. Provenance, complete patch ledger and AIR decision:
  `hakios-metal/VAYU.md`. Use the existing Mesa frontend in `tools/mesa/air`, not a
  duplicate; its API is older than upstream's and needs reconciliation before
  `MESA=1`. This baseline intentionally tests the no-compiler refusal and committed
  fixtures, not live AIR compilation or hardware. WSL pull refused existing local
  changes; only the new driver was synced for this build. No phone operations.

- [x] **2. Inventory what the driver implements.**
  Depends on: 1.
  Do: read the pinned source (not its README) and write `docs/metal-driver-inventory.md`. For each
  Metal feature: implemented, partial, or missing, with file:line. Cover: buffers, textures and
  formats, samplers, render and compute pipelines, function constants, argument buffers, MRT,
  blending, depth/stencil, MSAA, framebuffer fetch, indirect draws, blits, heaps, events/fences,
  IOSurface import, drawables, shader/pipeline caching, and the private interfaces Metal.framework
  calls on a `_MTLDevice`. Then the hardware features that decide speed: GMEM rendering and when it
  picks GMEM versus direct-to-memory, bin sizing, the binning pass/visibility stream, UBWC
  compression, LRZ, load/store elision and resolves, async submission.
  Done when: the document exists and tasks 13–16 below are corrected to match it.
  Result: **FACT (2026-11-07, source at `bc19b43`):**
  `docs/metal-driver-inventory.md` covers core/API/plugin and hardware features with
  file:line evidence. The core already has restricted GMEM, hardware binning,
  Mesa-dependent UBWC, timing/counters, async submission and load/store elision;
  LRZ is disabled. The bundled Objective-C plugin still has placeholder textures,
  samplers and pipelines and no render/compute encoders. Tasks 8–10 and 13–17
  now describe these actual gaps. Source audit only; no new hardware/test results.

- [x] **3. Check the A640 chip facts against Mesa.**
  Depends on: 1.
  Do: compare every A640-specific constant and choice in the ported code (GMEM size and layout,
  CCU offsets, gen2 register differences, cache flush/invalidate events, UBWC settings, firmware
  expectations, the absence of LPAC) against Mesa's freedreno device tables and gen2 code paths for
  a640, at the Mesa version our tree uses. List each one with its source, and fix mismatches.
  Do not take constants from A642L/A635 (gen4) or A740.
  Done when: a table of constants and sources is in `docs/metal-driver-inventory.md`; mismatches are
  fixed and committed; host tests still pass.
  Result: **FACT (2026-11-07):** A640/gen2 comparison table added to
  `docs/metal-driver-inventory.md`, using this tree's Mesa 25.0.7 (archive hash
  verified). Fixed the missing indirect-draw firmware WFM workaround and GMEM
  framebuffer-fetch base (`0x100000`, previously inherited zero); fixed A635
  defaults in two shader tools. GMEM/CCU/magic/cache/LPAC/UBWC facts otherwise
  match. `docs/metal-step3-register-check.log`: 1879 header constants match,
  80 marked non-header constants. `docs/metal-step3-build.log`: 261 host tests,
  zero failed checks; iOS library/probe cross-built; fake stages 1–4 pass.
  No phone used, no MESA=1/live compiler validation. Firmware remains the existing
  kernel's responsibility. Task 4 is next and requires phone captures.

- [x] **4. Capture reference command streams from freedreno on the phone.**
  Depends on: nothing (can run alongside 1–3).
  Do: freedreno already draws correctly on this phone through the GL path. Add a way to dump its
  submissions (Mesa's own cmdstream dump / `FD_RD_DUMP`, or a hook in `hakios-drm`) and capture a
  clear, a textured triangle, MRT, blending, and a compute dispatch with `gltest`-style jobs. Store
  the captures and decoder output (`cffdump`/`crashdec` from Mesa, built on the PC) outside git if
  large, with an index in `docs/`. These are the A640 "known good" streams that hakios-metal's
  output is diffed against.
  Done when: the captures decode on the PC and the index says which test each one is.
  Result: **FACT (2026-11-07, run `metal-step4`):** all five new off-screen
  `gl_reference` cases pass on FD640 / Mesa 25.0.7: clear, textured triangle,
  MRT, blending (all pixels checked), compute (all 64 SSBO values checked).
  Existing `FD_RD_DUMP=enable,full` suffices; no DRM patch needed. Ten submissions
  retrieved, byte counts/gzip CRCs/hashes verified; native Mesa 25.0.7 `cffdump`
  decodes all as chip `0x06040001`, exit 0, empty stderr. Raw captures and full
  decodes: ignored `logs/metal-step4/`; tracked index, manifest, decode summary
  and validation log: `docs/metal-reference-captures.md`, `docs/metal-step4-*`.
  Graphics references use GMEM; hardware binning/sysmem not covered. No reboot
  or partition commands; phone responsive afterward at 34 C. Task 5 is next.

### Phase B: the driver on the phone's GPU

- [ ] **5. Transport on the phone: `probe --stages`.**
  Depends on: 1.
  Do: put `probe` into the root image and run it from an rc.jobs file, first with SpringBoard not
  running, then with the GL window server holding the GPU. Each stage must be seen: open
  `RedwoodGPU`, allocate and map buffers, submit, wait on the fence, read back, close, all with no
  leaks across repeated runs. Fix the kernel side (`vayu_adreno.c`, `RedwoodGPU`) only where the
  ABI really lacks something, and write down the ABI that hakios-metal depends on.
  Done when: FACT logs of every stage passing, alone and alongside SpringBoard; the ABI is written
  down.
  Result: —

- [ ] **6. Compute on the phone.**
  Depends on: 3, 5.
  Do: run the compute fixtures (`fill_id`, `tex_copy`, `tex_fill`, `tex_sample_gid`, …) on the
  Adreno and compare their results with the CPU reference. When one is wrong, diff its submission
  against the task 4 captures before changing the compiler.
  Done when: every compute fixture matches on the phone (FACT, with run ID); failures that remain
  are listed with a diagnosis.
  Result: —

- [ ] **7. Rendering on the phone.**
  Depends on: 6.
  Do: in order, clear and read back; a flat triangle; attributes; a textured triangle; blending;
  depth; MRT (`tri_mrt*`); framebuffer fetch; a direct-to-memory pass and a GMEM pass of the same
  scene. Compare pixels with the CPU reference, and compare submissions with task 4 where they
  disagree.
  Done when: every render fixture matches on the phone, in both GMEM and direct-to-memory modes
  (FACT).
  Result: —

### Phase C: Metal.framework sees a device

- [ ] **8. Register the device with iOS.**
  Depends on: 5.
  Do: give the kernel's `IOAcceleratorES` (or a service that inherits from it) the
  `MetalPluginName`/`MetalPluginClassName` properties and an accelerator port Metal can open. Install
  the plugin bundle from hakios-metal (`/System/Library/Extensions/<name>.bundle`) with a class
  inheriting from `_MTLDevice` that answers `-initWithAcceleratorPort:`. Follow upstream's
  `docs/reference/metal.md`; where it describes redwood, adapt it rather than copy it. Watch for the
  window server starting to use Metal by itself once a device exists: keep it on GL behind a flag
  until task 11.
  The bundled plugin still advertises A642L and fixed/stub capabilities: correct
  the name and implement truthful A640 limits/private capability answers using the
  inventory. Audit both `metal=` and `HakiosMetal.clients` so backboardd stays on GL.
  Done when: `metal_test` on the phone prints a non-nil device with the expected name, family and
  limits; SpringBoard still comes up on GL.
  Result: —

- [ ] **9. A real Metal program draws and computes.**
  Depends on: 7, 8.
  Do: extend `metal_test` (or add `metal_app`) to use only the public API: command queue, buffers,
  textures, a `.metallib` built on the PC, a render pipeline, a compute pipeline, blits, completion
  handlers, `waitUntilCompleted`. Pipelines compile at creation (`docs/air.md` section 7, item 1),
  and the shader cache persists across runs.
  Replace the bundled plugin's placeholder textures, samplers, depth/stencil and
  render/compute pipeline objects; add real render/compute encoders, resource
  binding, function constants and argument encoders as the test needs. The C++/C
  implementations are present but those public Objective-C paths are not wired.
  Reuse the graphics-stage disk cache and add compute cache coverage: persistent
  compute compilation is not supplied by `compileAir` today (inventory).
  Before enabling `MESA=1`, reconcile our older `tools/mesa/air` API with the pinned
  driver's newer metadata requirements (task 1 findings in `hakios-metal/VAYU.md`),
  and validate the compiler-enabled host/iOS builds and A640 shader fixtures.
  Done when: the program's render and compute results match expected values on the phone, and a
  second run shows the cache warm (FACT).
  Result: —

- [ ] **10. IOSurface textures and CAMetalLayer.**
  Depends on: 9.
  Do: import IOSurfaces (`MiniIOSurface`) as Metal textures with correct tiling, layout, cache
  ownership and fences between the GPU and the display. Present through `CAMetalLayer`
  `nextDrawable`/`presentDrawable:` in a full-screen test app, with the layer composited by the GL
  window server.
  Wire the existing core surface import to the plugin's IOSurface texture selector
  and implement drawable lifetime/presentation; these are absent from the bundled
  plugin. Verify the vayu surface-import ABI instead of assuming upstream support.
  Done when: an animated Metal app is visible on the panel with no tearing or corruption, and the
  frame intervals are logged (FACT).
  Result: —

### Phase D: the system on Metal

- [ ] **11. CoreAnimation's window server on Metal.**
  Depends on: 10.
  Do: let backboardd/QuartzCore use the Metal device instead of `eagl.c`, behind a boot-arg so GL
  stays one flag away. Work through what CoreAnimation needs: its shaders (from the system
  `.metallib`s, see `docs/air-report.md`), blur, filters, YCbCr formats, detached layers,
  framebuffer fetch. Bring over the jasmine CoreAnimation fixes listed in `NOTES.md` where they
  still apply.
  Done when: SpringBoard, Settings, app switching, Control Centre and blur work on Metal with no
  visible errors; the GL flag still works (FACT, with screenshots or photos and logs).
  Result: —

- [ ] **12. System frameworks and third-party apps.**
  Depends on: 11.
  Do: go through the Metal-only callers listed in `docs/ru/metal.md` section 7 (CoreImage's Metal
  path, CameraUI's viewfinder, AppleDepth, Espresso/CoreML GPU) plus a few third-party Metal apps and
  games the user picks. For each, record whether it works, how it fails, and what's missing; this is
  the driver's to-do list.
  Done when: a coverage table in `docs/metal-driver-inventory.md`, with the user's chosen apps in it.
  Result: —

### Phase E: performance from the hardware

Each task: measure before and after on the same scene, resolution, clocks, temperature and wallpaper.
Report median, p95 and p99 frame interval, GPU time, bytes of memory traffic where available, and CPU
encode time. Keep each one behind a flag until it's shown to be correct and faster.

- [ ] **13. Instrumentation.**
  Depends on: 9.
  Do: reuse the core's pass/draw timestamps, operation/allocation counters and C
  profiling queries (`docs/metal-driver-inventory.md`). Validate timer register
  0x0980 and the assumed 19.2 MHz conversion on A640, and account for serialized
  per-draw profiling overhead. Wire real plugin GPU times (currently zero). Add CPU
  encode/submit time, fence waits and copied-byte/traffic accounting where measurable,
  logged in the style of `MiniIOMobileFramebuffer`'s five-second lines. A fixed benchmark
  scene set: a UI-like compositing scene, a fill-bound scene, a geometry-heavy scene, a compute
  workload.
  Done when: one command runs the set on the phone and prints a comparable summary.
  Result: —

- [ ] **14. GMEM: choosing it, bin sizes, the binning pass.**
  Depends on: 3, 4, 7, 13.
  Do: validate and tune the existing color-only GMEM planner, bin sizes, draw-count
  threshold/timing tuner and optional hardware VSC binning path on A640. Compare
  streams with task 4 and Mesa's gen2 behavior, including fixed VSC pitches and
  overflow recovery. Keep explicit sysmem fallback for depth/stencil, MSAA,
  compressed targets, queries and non-replayable draws; extend eligibility only
  with pixel and timing evidence. These paths already exist; see the inventory.
  Done when: eligible scenes match sysmem, exclusions fall back correctly, VSC
  stress/overflow is safe, and controlled measurements justify each enabled path.
  Result: —

- [ ] **15. UBWC compression for render targets and textures.**
  Depends on: 3, 7, 9, 13.
  Do: validate the existing Mesa-dependent single-level, single-sample 2D
  RGBA8/BGRA8 UBWC layout, sampled staging uploads and compressed render-target
  writes on A640. Add missing compressed clears and GMEM load/store support only
  with layout/command-stream evidence; expand formats/mips/MSAA separately.
  Includes IOSurfaces only where the display and other users can read the compressed
  layout; otherwise resolve explicitly and measure what that costs. Current surface
  import is linear, and the no-Mesa baseline cannot allocate UBWC textures.
  Done when: supported paths pass readback/aliasing tests and show measured traffic
  or frame-time gains, with unsupported layouts refused or resolved explicitly.
  Result: —

- [ ] **16. LRZ, load/store elision, and fewer flushes.**
  Depends on: 14.
  Do: implement LRZ (currently disabled), including allocation/layout, clear,
  direction tracking and invalidation rules; keep ordinary depth tests correct
  and extend beyond the current color-only GMEM path only after validation.
  Reuse existing touched-attachment masks, tile clears, render-area shrinking,
  DontCare load elision and StoreDontCare suppression. Extend resolve/store-action
  coverage and reduce conservative flushes only with a resource-hazard argument
  and A640 readback evidence; do not remove required framebuffer-fetch barriers.
  Done when: LRZ and each elision/flush change pass correctness comparisons across
  depth direction changes, clears, partial tiles and dependent passes, and improve
  controlled measurements behind individual flags.
  Result: —

- [ ] **17. CPU side: async submission, pooling, deferred encoding.**
  Depends on: 13. Measure the existing asynchronous commits/waiter, BO/slab and
  program pools, optional deferred recorder, constant uploads and register-state
  reuse first. Fix plugin scheduling semantics, bound memory growth and add texture
  pooling or broader persistent pipeline caches where measurements justify them
  (lessons in Chlorophyll's `docs/FIXES.md` and upstream's `metal-measurements.md`).
  Result: —

- [ ] **18. Presentation without the CPU copy.**
  Depends on: 11, 13. Revisit `fb_zero=1` (direct scanout of an IOSurface) now that Metal owns the
  frames. It hung the phone twice before (`docs/t120b-scroll-budget.md`, last section), so keep it
  behind its gate, try it in RAM boots only, and stop at the first hang to diagnose rather than retry.
  Result: —

## Open questions (whoever learns the answer writes it here)

- **Answered (task 1, source):** the driver links the parent tree's Mesa AIR frontend;
  our `tools/mesa/air` is the same lineage but has an older API. Keep this one frontend
  and reconcile the newer metadata before compiler-enabled builds (task 9).
- Did 0040/0043 ever run on vayu's GPU, or only on `fake_gpu`? (task 1 or 5)
- Does QuartzCore switch to Metal on its own once a device is registered? (task 8)
- Which third-party Metal apps or games matter to the user? (task 12)
