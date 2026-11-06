#!/bin/bash
# vayu: the data volume of iOS (/private/var) as an HFS Plus image, made in WSL, for darwin-install.sh var to write
# into darwin's slice /dev/ufs_var (VAR_FIRST/VAR_BLOCKS there; ufs_var_first=/ufs_var_blocks= on the kernel's
# command line, var_hfs=1 for init to mount it). Case-sensitive (HFSX, as iOS's own data volume is) and journaled,
# owned by root, 0755. The file is sparse: mkfs writes only the volume's own structures, and only those are
# written to the phone; the rest is free space, which HFS Plus never reads before it has written it.
#
#   devices/poco-x3-pro/tools/var-volume.sh OUT       (needs mkfs.hfsplus: Debian's hfsprogs)
#
# The volume starts empty; init fills it at its first boot (the skeleton, then the last var_store save).
set -euo pipefail
OUT=${1:?usage: var-volume.sh OUT}
VAR_BLOCKS=$(sed -n 's/^VAR_FIRST=[0-9]* VAR_BLOCKS=\([0-9]*\)$/\1/p' "$(dirname "$0")/darwin-install.sh")
[ -n "$VAR_BLOCKS" ] || { echo "var-volume: no VAR_BLOCKS in darwin-install.sh" >&2; exit 1; }
[ ! -e "$OUT" ] || { echo "var-volume: $OUT exists" >&2; exit 1; }
truncate -s $((VAR_BLOCKS * 4096)) "$OUT"
mkfs.hfsplus -s -J -b 4096 -U 0 -G 0 -M 755 -v Data "$OUT"
echo "var-volume: $OUT: $((VAR_BLOCKS * 4096 >> 30)) GiB, $(du -k "$OUT" | cut -f1) KB of it written by mkfs"
