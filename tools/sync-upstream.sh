#!/bin/bash
# Follow upstream HakiOS (oosexgang/hakios-xnu-kernel) without losing this fork's work. UPSTREAM.md says the rule.
#
#   tools/sync-upstream.sh [status]   fetch, then what upstream has that we have not: by area, and every commit that
#                                     touches a place this fork keeps its own version of (UPSTREAM.md's table)
#   tools/sync-upstream.sh merge      a branch sync/upstream-<date> from the current branch, and upstream merged into it
#                                     (no commit: the conflicts and the watched places are listed for you to go through)
#   tools/sync-upstream.sh patch      during that merge: xnu/hakios.patch merged through real XNU trees (base, ours and
#                                     upstream's patch each applied to Apple's tag, merged by git, exported again)
#
# env: UPSTREAM (remote, default upstream), BRANCH (default main), XNU_CLONE (a git clone of Apple's xnu that has the base
#      commit; default xnu-src/xnu-8796.121.2)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
UPSTREAM=${UPSTREAM:-upstream}
BRANCH=${BRANCH:-main}
REF=$UPSTREAM/$BRANCH
XNU_BASE=c54f35ca767986246321eb901baf8f5ff7923f6a        # tag xnu-8796.121.2 (xnu/apply.sh)

# the places this fork keeps its own version of (UPSTREAM.md): upstream's commits to them are read before merging
WATCHED=(
	xnuloader/loader.c
	drivers/storage/hakios.ufs.c userland/src/init.c xnu/files/bsd/hfs/hfs_builtin.c
	xnu/files/iokit/Kernel/MiniIOMobileFramebuffer.cpp
	userland/src/HakiosMetalCA.m userland/src/metal_test.m userland/src/HakiosMetal.plist hakios-metal
	userland/build.sh xl mkxnuimg.py .gitignore xnu/hakios.patch
	devices/poco-x5-pro
)

need_remote() {
	git remote get-url "$UPSTREAM" >/dev/null 2>&1 || {
		echo "sync-upstream: no remote '$UPSTREAM': git remote add $UPSTREAM https://github.com/oosexgang/hakios-xnu-kernel.git" >&2
		exit 1
	}
	git fetch -q "$UPSTREAM"
}

status() {
	need_remote
	local base new
	base=$(git merge-base HEAD "$REF") || { echo "sync-upstream: HEAD and $REF have no commit in common (UPSTREAM.md: the first sync)" >&2; exit 1; }
	new=$(git rev-list --count HEAD.."$REF")
	echo "sync-upstream: $REF is $(git log -1 --format='%h, %ad' --date=short "$REF"); in common with HEAD: $(git log -1 --format='%h %ad' --date=short "$base")"
	echo "sync-upstream: $new commits of upstream's not here, $(git rev-list --count "$REF"..HEAD) of ours not there"
	[ "$new" -gt 0 ] || return 0
	echo
	echo "== files upstream changed, by area"
	git diff --name-only "$base" "$REF" | awk -F/ '{ a = ($1 == "drivers" || $1 == "devices" || $1 == "docs" || $1 == "tools") && NF > 2 ? $1 "/" $2 : $1; n[a]++ }
		END { for (a in n) printf "%5d  %s\n", n[a], a }' | sort -rn
	echo
	echo "== upstream's commits to the places this fork keeps its own version of (read these first)"
	local any=0
	for p in "${WATCHED[@]}"; do
		local log
		log=$(git log --format='      %h %ad %s' --date=short "$base..$REF" -- "$p" | cut -c1-150)
		[ -n "$log" ] || continue
		any=1
		echo "  $p"
		echo "$log"
	done
	[ $any = 1 ] || echo "  (none)"
	echo
	echo "== all of upstream's new commits"
	git log --no-merges --format='  %h %ad %an: %s' --date=short "$base..$REF" | cut -c1-160
}

merge() {
	need_remote
	[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "sync-upstream: the tree has changes: commit them first" >&2; exit 1; }
	local from branch
	from=$(git rev-parse --abbrev-ref HEAD)
	branch=sync/upstream-$(date +%Y%m%d)
	git rev-parse -q --verify "refs/heads/$branch" >/dev/null && branch=$branch-$(date +%H%M)
	git checkout -q -b "$branch"
	echo "sync-upstream: on $branch (from $from); merging $REF ($(git rev-parse --short "$REF"))"
	if git -c merge.renameLimit=10000 merge --no-ff --no-commit "$REF"; then
		echo "sync-upstream: merged without conflicts (not committed)"
	fi
	local conflicts
	conflicts=$(git diff --name-only --diff-filter=U)
	if [ -n "$conflicts" ]; then
		echo
		echo "== conflicts ($(echo "$conflicts" | wc -l))"
		echo "$conflicts" | sed 's/^/  /'
		echo "$conflicts" | grep -qx xnu/hakios.patch && echo "  (xnu/hakios.patch: tools/sync-upstream.sh patch merges it through real XNU trees)"
	fi
	echo
	echo "== watched places upstream changed in this merge (UPSTREAM.md: ours unless upstream's was tried on vayu)"
	for p in "${WATCHED[@]}"; do
		git diff --quiet "$(git merge-base HEAD MERGE_HEAD)" MERGE_HEAD -- "$p" 2>/dev/null || echo "  $p"
	done
	echo
	echo "sync-upstream: next: resolve, ./xnu-build.sh, a deploy from iOS (devices/poco-x3-pro/tools/phone.sh deploy),"
	echo "sync-upstream: then commit here and merge $branch into $from; update UPSTREAM.md's table for what was kept"
}

patch_merge() {
	git rev-parse -q --verify MERGE_HEAD >/dev/null || { echo "sync-upstream: no merge in progress" >&2; exit 1; }
	local clone=${XNU_CLONE:-xnu-src/xnu-8796.121.2} work tmp base
	git -C "$clone" cat-file -e "$XNU_BASE^{commit}" 2>/dev/null || { echo "sync-upstream: $clone has no $XNU_BASE (XNU_CLONE=)" >&2; exit 1; }
	base=$(git merge-base HEAD MERGE_HEAD)
	tmp=$(mktemp -d)
	work=$tmp/xnu
	git show "$base:xnu/hakios.patch" > "$tmp/base.patch"
	git show "HEAD:xnu/hakios.patch" > "$tmp/ours.patch"
	git show "MERGE_HEAD:xnu/hakios.patch" > "$tmp/theirs.patch"
	git init -q "$work"
	(
		cd "$work"
		git config user.name sync; git config user.email sync@localhost
		git fetch -q --depth 1 "$(cd "$OLDPWD" && cd "$clone" && pwd)" "$XNU_BASE"
		for side in base ours theirs; do
			git checkout -q -f --detach "$XNU_BASE"
			git apply --whitespace=nowarn "$tmp/$side.patch"
			git add -A
			git commit -q -m "$side"
			git branch -f "p$side" HEAD
		done
		for side in ours theirs; do      # both made on top of base, so the merge has the right ancestor
			git branch -f "p$side" "$(git commit-tree "p$side^{tree}" -p pbase -m "$side")"
		done
		git checkout -q pours
		git merge -q --no-edit ptheirs >/dev/null 2>&1 || true
	)
	local left
	left=$(git -C "$work" diff --name-only --diff-filter=U)
	if [ -n "$left" ]; then
		echo "sync-upstream: Apple's files that still conflict, in $work:"
		echo "$left" | sed 's/^/  /'
		echo "sync-upstream: resolve them there, commit, then: git -C $work -c core.abbrev=12 diff --binary --no-renames --no-color \\"
		echo "    --no-ext-diff --diff-filter=MDT $XNU_BASE -- . > xnu/hakios.patch"
		exit 1
	fi
	git -C "$work" -c core.abbrev=12 diff --binary --no-renames --no-color --no-ext-diff --diff-filter=MDT "$XNU_BASE" -- . > xnu/hakios.patch
	git add xnu/hakios.patch
	rm -rf "$tmp"
	echo "sync-upstream: xnu/hakios.patch merged through the trees ($(grep -c '^diff --git' xnu/hakios.patch) of Apple's files changed)"
}

case "${1:-status}" in
status) status ;;
merge) merge ;;
patch) patch_merge ;;
*) sed -n '2,13p' "$0"; exit 1 ;;
esac
