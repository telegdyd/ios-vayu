# Following upstream

This fork (`origin` = `telegdyd/ios-vayu`, branch `vayu-dev`) is HakiOS on the POCO X3 Pro (`vayu`). It follows
[oosexgang/hakios-xnu-kernel](https://github.com/oosexgang/hakios-xnu-kernel) as the remote `upstream`, branch `main`.

```bash
git remote add upstream https://github.com/oosexgang/hakios-xnu-kernel.git   # once
tools/sync-upstream.sh            # what upstream has that we have not, by area (reads only)
tools/sync-upstream.sh merge      # the merge, on a branch of its own (sync/upstream-<date>), never on vayu-dev
```

## The rule

- **Upstream's version by default.** Its refactors, fixes, naming and new features come in as they are.
- **Ours where it is vayu's or proven on the phone,** and upstream's change to the same place has not been tried on
  vayu. Each such place is listed below, with what upstream has there, so the next sync knows what to look at again.
- **A merge is not done until it builds and runs on the phone:** the kernel builds (`./xnu-build.sh`), and a deploy
  from iOS (`devices/poco-x3-pro/tools/phone.sh deploy`) comes up with the window server, touch, Wi-Fi and Metal as
  before. Only then is the sync branch merged into `vayu-dev`.
- **Merge, never rebase:** `vayu-dev` is published, and a merge keeps both histories as they were.

## The first sync (7 November 2026, upstream 63fc2b4)

Upstream rewrote its history at the end of October, so the two branches had no commit in common: our `8851317`
has the same tree as upstream's `466a9f8` (26 October). The merge was made against that point (a temporary
`git replace --graft 466a9f8 8851317`, removed afterwards), and it records `upstream/main` as a parent. From then
on `git merge-base vayu-dev upstream/main` is upstream's commit, and a sync is an ordinary merge.

`xnu/hakios.patch` is a diff against Apple's XNU, and a diff of diffs does not merge well as text. It was merged
the way it should be every time it conflicts: the base, our and upstream's patch each applied to Apple's
`xnu-8796.121.2`, the three trees merged by git, and the patch exported again (`xnu/export.sh` does the last step
from a kernel tree). In that merge `xnu/vayu-night.patch` and `xnu/hfs/xnu.patch` were folded into
`xnu/hakios.patch`, which is upstream's layout: one patch for Apple's files.

## Where this fork keeps its own version

| Place | Ours | Upstream's, not taken yet | To take it |
|---|---|---|---|
| `xnuloader/loader.c` | loader 2.8: USB mode, command port, flash staged in darwin and written at the next start, standalone resident image (2.2), vayu platform | its own resident image from the payload, `BLOCK_OP_WRITE_FAST` / `BLOCK_OP_FLUSH` for the data volume, its log under U-Boot, darwin found anywhere on LUN 0 | port piece by piece, each tried with `phone.sh deploy`; the mailbox struct (`write_reserved` / `write_caps`) must change in `loader.c` and `hakios.ufs.c` together |
| `/private/var` on the flash: `drivers/storage/hakios.ufs.c`, `userland/src/init.c`, `xnu/files/bsd/hfs/hfs_builtin.c` | `/dev/ufs_var`, a slice of darwin whose bounds the loader passes (`ufs_darwin_first`, `ufs_darwin_blocks`, `ufs_write_first`); `init` `var_hfs=1`; HFS's syncer on for `/dev/ufs_var` | `/dev/ufs_darwin_data`, darwin past a fixed 2042368 blocks (at least 20 GiB), its writes through the loader's fast path; `init` `var_hfs=DEV` | the same feature built twice: unify once the loader's fast path is in (above). Upstream's two read-path fixes in `hakios.ufs.c` (the bounce buffer allocated under the lock, reads bounded by the partition) are taken |
| `xnu/files/iokit/Kernel/MiniIOMobileFramebuffer.cpp` | 120 Hz (`fb_120`, `fb_120_idle`), `fb_crop`, `fb_zero` (VIG0 scanout), early dequeue and swap fences, frame budget, the Metal device (task 8) | `fb_filter=2` (nearest while frames come, bilinear when still), `fb_pri` thread priority, `IOMFBDisplayRefresh` in 2^-32 s, `fb_measure`, `fbsubtype` / screen size, beam scan, `kern.hakios.fb_surface`, `surfaceHolds()` bounds checks | the presenter loops differ in structure: port feature by feature onto ours, measuring on the panel; `surfaceHolds()` and `IOMFBDisplayRefresh` first |
| `userland/src/HakiosMetalCA.m`, `metal_test.m`, `HakiosMetal.plist`; `hakios-metal/` | upstream 63fc2b4's, plus the A640 port and tasks 8-11 (`docs/metal-roadmap.md`) | nothing newer at the time of the sync; `metal_test`'s `objects` and `blits` subtests | at the next sync, upstream's changes to these files are the ones to read first |
| `userland/build.sh` (Metal plug-in) | the plug-in from `src/HakiosMetalCA.m` with the core's compiler (task 9) | `HAKIOS_METAL=` search, `out/darwin`, M2V linked into the plug-in | when M2V is wanted on vayu |
| `devices/poco-x5-pro/uefi/` | kept: `devices/poco-x3-pro/uefi/build.sh` uses its `mu-silicium.patch` and `XnuLoader.[ch]` | moved to its own repository (`oosexgang/hakios-uefi`, `devices/manifest.conf`), and the vendor's UEFI binaries are no longer committed | point vayu's UEFI build at hakios-uefi; then drop this directory (and the binaries in it) |
| `devices/poco-x3-pro/` | in this tree | each phone a repository of its own (`devices/manifest.conf`, `tools/hakios-device.py`) | a later step: vayu as its own repository, `vayu_*.c` as its `drivers/` |
| `bsd/conf/files` (in `xnu/hakios.patch`) | the `vayu_*.c` drivers listed after the generated block, always built | the block between `# HakiOS drivers` and `# end of the HakiOS drivers` is written by `tools/hakios-config.py kernel` from `drivers/*/conf` | with vayu as a device repository its drivers get a `conf` and `CONFIG_HAKIOS_*` symbols |

Small differences, kept on purpose:

- `xl`: `firmware()` looks for the UEFI of the device in `DEVICE` (its `boot.conf`'s `UEFI_TARGET`), not only redwood's;
  without that vayu would be sent through U-Boot.
- `mkxnuimg.py`: per-device `boot.conf` (`UEFI_TARGET`, `FD_BASE`, `FD_SIZE`); upstream's has redwood's numbers fixed.
- `.gitignore`: upstream ignores everything in `devices/` but its own entries; `devices/poco-x3-pro/` and
  `devices/poco-x5-pro/` are let through.
- New upstream behaviour that is on by default and was not tried on vayu at the sync: `surf_wrap=1` (IOSurfaces around
  the window server's own pictures, `MiniIOSurface.cpp`); `surf_wrap=0` is the old way if it misbehaves.
