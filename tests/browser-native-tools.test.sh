#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
browser_root="$repo_root/browser"
copy_host="$browser_root/.local/bin/chromium-copy-url-host"
video_host="$browser_root/.local/bin/chromium-ytdlp-host"
copy_extension="$browser_root/.local/share/chromium-tools/extensions/copy-url"
video_extension="$browser_root/.local/share/chromium-tools/extensions/download-video"
test_root="$(mktemp -d -t browser-native-tools.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    [[ "$1" == "$2" ]] || fail "expected [$1], got [$2]"
}

assert_contains() {
    grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"
}

jq -e '.manifest_version == 3 and (.permissions | index("nativeMessaging") != null)' \
    "$copy_extension/manifest.json" >/dev/null
jq -e '.manifest_version == 3 and (.permissions | index("nativeMessaging") != null)' \
    "$video_extension/manifest.json" >/dev/null
node --check "$copy_extension/background.js"
node --check "$video_extension/background.js"
bash -n "$copy_host" "$video_host"
while IFS= read -r manifest; do
    jq -e . "$manifest" >/dev/null
done < <(find "$browser_root/.config" -path '*/NativeMessagingHosts/*.json' \
    -type f -print)

python3 - "$browser_root" <<'PY'
import base64
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
cases = (
    ("copy-url", "nlobndichollhdcdlbcndgdcfgonenfh", "copy_url"),
    ("download-video", "kgbmkkhmlonlobngnjpncdlgaipnabmc", "ytdlp"),
)
for directory, expected, host in cases:
    manifest = json.loads((root / ".local/share/chromium-tools/extensions" /
                           directory / "manifest.json").read_text())
    der = base64.b64decode(manifest["key"], validate=True)
    digest = hashlib.sha256(der).digest()[:16]
    actual = "".join(chr(ord("a") + nibble)
                     for byte in digest for nibble in (byte >> 4, byte & 15))
    assert actual == expected, (directory, actual, expected)
    native = json.loads((root / ".config/chromium/NativeMessagingHosts" /
                         f"io.github.fhlkfds.{host}.json").read_text())
    assert native["allowed_origins"] == [f"chrome-extension://{expected}/"]
PY

payload='{"url":"https://example.com/watch?v=1"}'
framed="$test_root/framed.bin"
python3 - "$payload" "$framed" <<'PY'
import pathlib
import struct
import sys
data = sys.argv[1].encode()
pathlib.Path(sys.argv[2]).write_bytes(struct.pack("<I", len(data)) + data)
PY
decoded="$(bash -c 'source "$1"; read_native_message' _ "$copy_host" < "$framed")"
assert_eq "$payload" "$decoded"

(
    # shellcheck source=/dev/null
    source "$copy_host"
    wl-copy() {
        printf '%s\n' "$*" > "$test_root/wl-copy-args"
        printf '%s' "$(</dev/stdin)" > "$test_root/clipboard"
    }
    notify-send() { printf '%s\n' "$*" > "$test_root/copy-notification"; }
    copy_url 'https://example.com/a?b=c'
)
assert_eq 'https://example.com/a?b=c' "$(<"$test_root/clipboard")"
assert_contains "$test_root/wl-copy-args" '--type text/plain'
assert_contains "$test_root/copy-notification" 'URL copied to clipboard'

(
    # shellcheck source=/dev/null
    source "$video_host"
    DOWNLOAD_DIR="$test_root/videos"
    simulate_ok=1

    yt-dlp() {
        if [[ " $* " == *' --simulate '* ]]; then
            ((simulate_ok == 1))
            return
        fi
        mkdir -p "$DOWNLOAD_DIR"
        printf video > "$DOWNLOAD_DIR/Test Video.mp4"
        printf 'BROWSER_PROG\t12.5%%\n'
        printf 'BROWSER_FILE\t%s\n' "$DOWNLOAD_DIR/Test Video.mp4"
        printf 'BROWSER_TITLE\t"Test Video"\n'
    }
    quickshell() { printf '%s\n' "$*" >> "$test_root/osd.log"; }
    ffmpeg() {
        local arg
        for arg in "$@"; do
            [[ "$arg" == *.jpg ]] && printf preview > "$arg"
        done
    }
    notify-send() {
        printf '%s\n' "$*" >> "$test_root/video-notifications"
        [[ "$*" == *'Download complete'* ]] && printf default
        return 0
    }
    setsid() { printf '%s\n' "$*" > "$test_root/player"; }
    date() { printf '1000\n'; }

    download_url 'https://example.com/video'
    [[ -f "$DOWNLOAD_DIR/Test Video.mp4" ]]

    printf outside > "$test_root/outside.mp4"
    if resolve_download_file "$test_root/outside.mp4" >/dev/null; then
        fail 'path outside download directory was accepted'
    fi

    simulate_ok=0
    download_url 'https://example.com/no-video'
)
assert_contains "$test_root/osd.log" 'ipc call videoDownload setProgress 0'
assert_contains "$test_root/osd.log" 'ipc call videoDownload close'
assert_contains "$test_root/video-notifications" 'Download complete Test Video'
assert_contains "$test_root/video-notifications" 'No video found for download'
assert_contains "$test_root/player" 'mpv --'
assert_contains "$test_root/player" "$test_root/videos/Test Video.mp4"

if command -v quickshell >/dev/null 2>&1; then
    mkdir -m 700 "$test_root/runtime" "$test_root/state"
    XDG_RUNTIME_DIR="$test_root/runtime" XDG_STATE_HOME="$test_root/state" \
        QT_QPA_PLATFORM=offscreen quickshell \
        -p "$repo_root/quickshell/.config/quickshell/VideoDownloadSmoke.qml" \
        >"$test_root/qml-smoke.log" 2>&1 || {
          sed -n '1,160p' "$test_root/qml-smoke.log" >&2
          fail 'Quickshell OSD smoke test failed'
        }
fi

printf 'ok: browser native tools fixtures\n'
