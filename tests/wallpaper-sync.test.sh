#!/usr/bin/env bash
# Two fixture machines sync wallpapers through a local bare remote. Nothing
# here touches the real ~/Pictures, ~/dotfiles or GitHub.

set -euo pipefail

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sync=$repo_root/hypr/.local/bin/wallpaper-sync
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

stub_bin=$test_root/bin
notes=$test_root/notifications
mkdir -p "$stub_bin"
cat > "$stub_bin/notify-send" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "$WALLPAPER_TEST_NOTES"
STUB
chmod +x "$stub_bin/notify-send"

export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid

seed=$test_root/seed
git init -q -b main "$seed"
mkdir -p "$seed/wallpaper/theme" "$seed/hypr"
printf 'a\n' > "$seed/wallpaper/a.jpg"
printf 'b\n' > "$seed/wallpaper/b.png"
printf 't\n' > "$seed/wallpaper/theme/t.jpg"
printf 'cfg\n' > "$seed/hypr/config"
git -C "$seed" add .
git -C "$seed" commit -qm initial
git clone -q --bare "$seed" "$test_root/remote.git"

# machine NAME: a home with its own ~/dotfiles clone.
machine() {
  mkdir -p "$test_root/$1"
  git clone -q "$test_root/remote.git" "$test_root/$1/dotfiles"
}

run_sync() {
  local name=$1 home=$test_root/$1
  HOME=$home DOTS_REPO=$home/dotfiles WALLPAPER_SYNC_HOST=$name \
    WALLPAPER_SYNC_SETTLE=${WALLPAPER_TEST_SETTLE:-0} XDG_RUNTIME_DIR=$test_root \
    WALLPAPER_TEST_NOTES=$notes PATH="$stub_bin:$PATH" "$sync"
}

pics() { printf '%s\n' "$test_root/$1/Pictures/Wallpapers"; }
remote_has() { git -C "$test_root/remote.git" cat-file -e "main:wallpaper/$1" 2>/dev/null; }

# --- Machine "desk" was deployed by the old `stow wallpaper`: Stow links into
# ~/dotfiles, one wallpaper added since, and a wallpaper on its feature branch.
machine desk
git -C "$test_root/desk/dotfiles" switch -q -c feature
printf 'wip\n' > "$test_root/desk/dotfiles/hypr/config"
mkdir -p "$(pics desk)/theme"
for file in a.jpg b.png; do
  ln -s "../../dotfiles/wallpaper/$file" "$(pics desk)/$file"
done
ln -s "../../../dotfiles/wallpaper/theme/t.jpg" "$(pics desk)/theme/t.jpg"
printf 'new\n' > "$(pics desk)/new.jpg"

run_sync desk
[[ -L $(pics desk) ]] || fail 'Wallpapers was not replaced by a symlink'
[[ $(readlink "$(pics desk)") == "$test_root/desk/Pictures/.wallpaper-sync/wallpaper" ]] ||
  fail 'Wallpapers symlink points to the wrong place'
[[ $(<"$(pics desk)/a.jpg") == a && $(<"$(pics desk)/theme/t.jpg") == t ]] ||
  fail 'tracked wallpapers missing after migration'
remote_has new.jpg || fail 'new wallpaper was not pushed'
[[ ! -e $test_root/desk/Pictures/.wallpaper-sync/hypr ]] ||
  fail 'sparse worktree checked out non-wallpaper packages'
[[ $(git -C "$test_root/desk/dotfiles" branch --show-current) == feature &&
  $(git -C "$test_root/desk/dotfiles" status --porcelain) == ' M hypr/config' ]] ||
  fail 'sync disturbed the main checkout'

# --- Machine "laptop" is fresh. Its first run must only pull, never delete.
machine laptop
run_sync laptop
for file in a.jpg b.png new.jpg theme/t.jpg; do
  [[ -f $(pics laptop)/$file ]] || fail "laptop did not receive $file"
done

# Deleting on one machine deletes everywhere.
rm "$(pics laptop)/a.jpg"
run_sync laptop
remote_has a.jpg && fail 'deletion was not pushed'
run_sync desk
[[ ! -e $(pics desk)/a.jpg ]] || fail 'deletion did not reach the other machine'

# Same name, different images on both machines: both are kept.
printf 'desk version\n' > "$(pics desk)/clash.jpg"
printf 'laptop version\n' > "$(pics laptop)/clash.jpg"
run_sync desk
run_sync laptop
[[ $(<"$(pics laptop)/clash.jpg") == 'desk version' &&
  $(<"$(pics laptop)/clash-laptop.jpg") == 'laptop version' ]] ||
  fail 'name clash was not resolved with a host suffix'
remote_has clash-laptop.jpg || fail 'renamed clash was not pushed'

# The same image added on both machines is not duplicated.
printf 'same\n' > "$(pics desk)/same.jpg"
printf 'same\n' > "$(pics laptop)/same.jpg"
run_sync desk
run_sync laptop
[[ -f $(pics laptop)/same.jpg && ! -e $(pics laptop)/same-laptop.jpg ]] ||
  fail 'identical wallpaper was duplicated'

# Partial downloads and files over 50 MB stay local.
printf 'half\n' > "$(pics desk)/wallhaven-x.jpg.part"
truncate -s 60M "$(pics desk)/huge.png"
: > "$notes"
run_sync desk
remote_has wallhaven-x.jpg.part && fail 'partial download was pushed'
remote_has huge.png && fail 'oversized wallpaper was pushed'
grep -Fq 'huge.png' "$notes" || fail 'oversized wallpaper was not reported'
rm "$(pics desk)/wallhaven-x.jpg.part" "$(pics desk)/huge.png"

# Another machine pushes between this one's fetch and push: retry and win.
cat > "$test_root/desk/dotfiles/.git/hooks/pre-push" <<HOOK
#!/usr/bin/env bash
[[ -e "$test_root/raced" ]] && exit 0
touch "$test_root/raced"
printf 'race\n' > "$(pics laptop)/race.jpg"
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE HOME="$test_root/laptop" \
  DOTS_REPO="$test_root/laptop/dotfiles" WALLPAPER_SYNC_HOST=laptop \
  WALLPAPER_SYNC_SETTLE=0 XDG_RUNTIME_DIR="$test_root/laptop" "$sync"
HOOK
chmod +x "$test_root/desk/dotfiles/.git/hooks/pre-push"
printf 'mine\n' > "$(pics desk)/mine.jpg"
run_sync desk
[[ -e $test_root/raced ]] || fail 'race hook did not run'
{ remote_has race.jpg && remote_has mine.jpg; } || fail 'push race lost a wallpaper'
rm "$test_root/desk/dotfiles/.git/hooks/pre-push"

# A legacy directory holding something that is not a wallpaper is left alone.
machine other
mkdir -p "$(pics other)/notes"
ln -s /etc/hostname "$(pics other)/notes/link"
: > "$notes"
if run_sync other 2>/dev/null; then fail 'unknown entries did not stop migration'; fi
[[ -d $(pics other) && ! -L $(pics other) && -L $(pics other)/notes/link ]] ||
  fail 'migration changed a directory it refused'
grep -Fq 'still has entries' "$notes" || fail 'refused migration was not reported'

# Hidden directories and tracked edits must obey the same exclusions as new files.
mkdir -p "$(pics desk)/.private"
printf 'private\n' > "$(pics desk)/.private/image.jpg"
run_sync desk
remote_has .private/image.jpg && fail 'hidden-directory image was published'
truncate -s 110M "$(pics desk)/b.png"
run_sync desk
[[ $(git -C "$test_root/remote.git" cat-file -s main:wallpaper/b.png) == 2 ]] ||
  fail 'oversized tracked edit was published'
[[ $(stat -c %s "$(pics desk)/b.png") == 115343360 ]] || fail 'excluded local edit was lost'
printf 'b\n' > "$(pics desk)/b.png"

# A remote image with a skipped oversized local name must not overwrite it.
truncate -s 110M "$(pics desk)/large-clash.png"
printf 'small remote image\n' > "$(pics laptop)/large-clash.png"
run_sync laptop
run_sync desk
[[ $(<"$(pics desk)/large-clash.png") == 'small remote image' &&
  $(stat -c %s "$(pics desk)/large-clash-desk.png") == 115343360 ]] ||
  fail 'incoming image overwrote an excluded oversized addition'
rm "$(pics desk)/large-clash-desk.png"

# Refusal must happen before moving images or removing existing Stow links.
machine mixed
mkdir -p "$(pics mixed)"
ln -s "$test_root/mixed/dotfiles/wallpaper/b.png" "$(pics mixed)/b.png"
printf 'keep\n' > "$(pics mixed)/keep.jpg"
printf 'private notes\n' > "$(pics mixed)/notes.txt"
if run_sync mixed 2>/dev/null; then fail 'regular non-wallpaper did not stop migration'; fi
[[ -L $(pics mixed)/b.png && -f $(pics mixed)/keep.jpg && -f $(pics mixed)/notes.txt ]] ||
  fail 'refused migration partially changed the folder'
remote_has notes.txt && fail 'migration published non-wallpaper data'

# Older Stow installs can fold the entire wallpaper directory into one link.
machine folded
mkdir -p "$test_root/folded/Pictures"
ln -s "$test_root/folded/dotfiles/wallpaper" "$(pics folded)"
run_sync folded
[[ $(readlink "$(pics folded)") == "$test_root/folded/Pictures/.wallpaper-sync/wallpaper" ]] ||
  fail 'folded Stow directory was not migrated'

# An existing host suffix must never discard a new image.
run_sync laptop
printf 'old suffix\n' > "$(pics desk)/repeat-laptop.jpg"
printf 'desk image\n' > "$(pics desk)/repeat.jpg"
printf 'laptop image\n' > "$(pics laptop)/repeat.jpg"
run_sync desk
run_sync laptop
[[ $(<"$(pics laptop)/repeat.jpg") == 'desk image' &&
  $(<"$(pics laptop)/repeat-laptop.jpg") == 'old suffix' &&
  $(<"$(pics laptop)/repeat-laptop-2.jpg") == 'laptop image' ]] ||
  fail 'occupied host suffix lost a wallpaper'

# A failed upload leaves a commit locally. Another machine may use its name
# before the next run, or between fetch and push.
run_sync desk
cat > "$test_root/desk/dotfiles/.git/hooks/pre-push" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$test_root/desk/dotfiles/.git/hooks/pre-push"
printf 'offline desk\n' > "$(pics desk)/offline.jpg"
if run_sync desk 2>/dev/null; then fail 'failed upload reported success'; fi
rm "$test_root/desk/dotfiles/.git/hooks/pre-push"
printf 'online laptop\n' > "$(pics laptop)/offline.jpg"
run_sync laptop
run_sync desk
[[ $(<"$(pics desk)/offline.jpg") == 'online laptop' &&
  $(<"$(pics desk)/offline-desk.jpg") == 'offline desk' ]] ||
  fail 'retry of a committed name clash lost an image'

# The bounded settling wait must defer an ongoing copy, never publish it.
machine busy
run_sync busy
printf 'in progress\n' > "$(pics busy)/copy.jpg"
# Model a copy preserving old mtimes: ctime must still keep the wait active.
find "$(readlink "$(pics busy)")" -exec touch -t 200001010000 {} +
sleep_bin=$test_root/sleep-bin
mkdir -p "$sleep_bin"
cat > "$sleep_bin/sleep" <<'STUB'
#!/usr/bin/env bash
touch -t 200001010000 "$WALLPAPER_TEST_COPY"
STUB
chmod +x "$sleep_bin/sleep"
if WALLPAPER_TEST_SETTLE=30 WALLPAPER_TEST_COPY="$(pics busy)/copy.jpg" \
  PATH="$sleep_bin:$PATH" run_sync busy 2>/dev/null; then fail 'ongoing copy was not deferred'; fi
remote_has copy.jpg && fail 'ongoing copy was published'

# Repository overrides inherited from a hook/shell must not redirect Git.
before=$(git -C "$test_root/desk/dotfiles" rev-parse HEAD)
GIT_DIR="$test_root/desk/dotfiles/.git" GIT_WORK_TREE="$test_root/desk/dotfiles" \
  GIT_INDEX_FILE="$test_root/desk/dotfiles/.git/index" run_sync folded
[[ $(git -C "$test_root/desk/dotfiles" rev-parse HEAD) == "$before" &&
  $(git -C "$test_root/desk/dotfiles" status --porcelain) == ' M hypr/config' ]] ||
  fail 'inherited Git environment changed the dotfiles checkout'

# An interrupted --no-checkout setup must not be interpreted as deleting images.
machine interrupted
git -C "$test_root/interrupted/dotfiles" worktree add -q --no-checkout --detach \
  "$test_root/interrupted/Pictures/.wallpaper-sync" origin/main
before=$(git -C "$test_root/remote.git" rev-parse main)
if run_sync interrupted 2>/dev/null; then fail 'incomplete worktree was reused'; fi
[[ $(git -C "$test_root/remote.git" rev-parse main) == "$before" ]] ||
  fail 'incomplete setup pushed deletions'

# An excluded tracked edit can conflict during autostash application. Report
# failure and preserve the stash and unresolved index across subsequent runs.
machine excluded
run_sync excluded
truncate -s 110M "$(pics excluded)/b.png"
printf 'changed remotely\n' > "$(pics laptop)/b.png"
run_sync laptop
if run_sync excluded >"$test_root/excluded.log" 2>&1; then fail 'autostash conflict reported success'; fi
excluded_tree=$test_root/excluded/Pictures/.wallpaper-sync
[[ $(git -C "$excluded_tree" status --porcelain) == *'UU wallpaper/b.png'* ]] ||
  fail 'autostash conflict was silently cleared'
[[ $(git -C "$excluded_tree" cat-file -s stash:wallpaper/b.png) == 115343360 ]] ||
  fail 'autostash lost the excluded edit'
if run_sync excluded 2>/dev/null; then fail 'unresolved autostash conflict was silently reset'; fi
[[ $(git -C "$excluded_tree" status --porcelain) == *'UU wallpaper/b.png'* ]] ||
  fail 'subsequent run erased the unresolved index'

# Empty repositories and removing the final wallpaper must remain usable.
git -C "$seed" rm -qr wallpaper
git -C "$seed" commit -qm 'empty wallpaper library'
git clone -q --bare "$seed" "$test_root/empty-remote.git"
git clone -q "$test_root/empty-remote.git" "$test_root/empty/dotfiles"
run_sync empty
printf 'last\n' > "$(pics empty)/last.jpg"
run_sync empty
git clone -q "$test_root/empty-remote.git" "$test_root/empty-receiver/dotfiles"
run_sync empty-receiver
rm "$(pics empty)/last.jpg"
run_sync empty
run_sync empty
run_sync empty-receiver
run_sync empty-receiver
[[ ! -e $(pics empty)/last.jpg ]] || fail 'final image deletion was not preserved'
[[ -d $(pics empty-receiver) ]] || fail 'remote deletion left a dangling Wallpapers symlink'

printf 'wallpaper-sync tests passed\n'
