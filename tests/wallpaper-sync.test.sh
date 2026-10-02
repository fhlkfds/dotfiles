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
    WALLPAPER_SYNC_SETTLE=0 XDG_RUNTIME_DIR=$test_root \
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

printf 'wallpaper-sync tests passed\n'
