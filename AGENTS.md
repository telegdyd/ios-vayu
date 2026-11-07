# Working on ios-vayu

iOS (HakiOS, Darwin 16.5 user space) on the POCO X3 Pro (`vayu`, SM8150-AC / Snapdragon 860, Adreno 640).
This tree is the author's vayu fork of HakiOS (`author` remote,
github.com/nomorecoolnicknames/hackios-xnu-kernel-vayu, branch `main`); our work goes on branch `vayu-dev`.

- Read `NOTES.md` before starting: goal, decisions, current state, where things are, next action.
  The author's own handoff is `docs/HANDOFF-2026-11-02.md` (Russian); the device page is
  `devices/poco-x3-pro/README.md` (its status table is older than the handoff; the handoff wins).
- The user switches agents often. Update the active handoff at the top of `NOTES.md` after each
  milestone and before stopping: commits, run IDs/log names, exact build and boot results, unfinished
  work. Label claims FACT (seen, with the artifact), INFERENCE or HYPOTHESIS.
- Commit completed changes (on `vayu-dev`). Never push to `author`; publishing our own GitHub repo
  needs the user's OK.
- Two checkouts of the same repository:
  - this Windows one (`C:\Users\teleg\Documents\Code\Poco X3 Pro\ios-vayu`): edit and commit here, and
    drive the phone from Git Bash (`xl`, adb, fastboot are Windows programs);
  - the build one in WSL Debian, `~/vayu`, with this checkout as its `win` remote: `git -C ~/vayu pull win
    vayu-dev` before building. Images (`sysimage/`, `userland/*.apfs`) must be built in WSL's own
    filesystem (file names with `:`), then copied here.
- The phone boots everything from RAM (`fastboot boot` of the UEFI, then the loader). Keep bootloaders
  (xbl, abl, devcfg, ...), modem, persist, modemst/fsg and the partition backups intact: Xiaomi EDL is
  auth-locked, a broken bootloader chain cannot be repaired at home. The user wants iOS installed on the
  phone eventually (Android may go); confirm every destructive step with the user before running it.
- Deploys: `FLASH_BOOT=yes devices/poco-x3-pro/tools/phone.sh deploy [IMAGE]` from a settled iOS (staged in
  darwin, written by the loader at the next start, verified; NOTES.md "Flash from iOS"). Never through our
  loader's USB mode (no "loader" on the command port, no `phone.sh loader|flash`, no `flash:boot`): it hangs
  after any forced restart (NOTES.md, "Loader-mode hang (parked)"). If `boot` does not start, vayu's stock
  fastboot, which the user enters (volume down + power).
- Keep device dumps, serial numbers, IMEI/SIM identifiers, Wi-Fi secrets and Apple/vendor files out of git.
- C: is small (~26 GB free at setup). Check `df` before large downloads or builds.
