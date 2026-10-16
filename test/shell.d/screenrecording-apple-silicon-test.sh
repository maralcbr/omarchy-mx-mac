#!/bin/bash
#
# gpu-screen-recorder can't capture on Apple Silicon, so screen recording uses
# wf-recorder there, and everything that detects a running recording matches
# either recorder.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'kill $(cat "$tmp"/*.pid 2>/dev/null) 2>/dev/null || true; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/videos" "$tmp/home"
export CALL_LOG="$tmp/calls" TMP_DIR="$tmp"

stub() {
  printf '#!/bin/bash\n%s\n' "$2" >"$tmp/bin/$1"
  chmod +x "$tmp/bin/$1"
}

# A recorder stub logs its arguments, creates the output file and keeps running
# until the test kills it, so the script sees a recording that started.
recorder_stub() {
  stub "$1" '
printf "%s" "'"$1"'" >>"$CALL_LOG"; printf " [%s]" "$@" >>"$CALL_LOG"; echo >>"$CALL_LOG"
prev=""
for arg; do
  [[ $prev == "-f" || $prev == "-o" ]] && [[ $arg == *.mp4 ]] && : >"$arg"
  prev=$arg
done
echo $$ >"$TMP_DIR/'"$1"'.pid"
exec sleep 30'
}

recorder_stub wf-recorder
recorder_stub gpu-screen-recorder
stub pgrep 'exit 1'
stub pkill 'exit 1'
stub pactl '
case "$1" in
get-default-sink) echo speakers ;;
get-default-source) echo microphone ;;
load-module) printf "pactl load-module" >>"$CALL_LOG"; printf " [%s]" "${@:2}" >>"$CALL_LOG"; echo >>"$CALL_LOG"; echo $((RANDOM + 1)) ;;
esac'
stub hyprctl 'echo "[{\"focused\": true, \"width\": ${OMARCHY_TEST_WIDTH:-3024}, \"height\": ${OMARCHY_TEST_HEIGHT:-1964}}]"'
stub omarchy-hyprland-monitor-focused 'echo eDP-1'
stub omarchy-capture-region 'echo "${OMARCHY_TEST_REGION:-10,20 300x200}"'
stub omarchy-shell 'exit 0'
stub omarchy-notification-send 'exit 0'

record() {
  local apple=$1
  shift
  stub omarchy-hw-apple-silicon "exit $apple"
  : >"$CALL_LOG"
  env HOME="$tmp/home" OMARCHY_SCREENRECORD_DIR="$tmp/videos" XDG_RUNTIME_DIR="$tmp" \
    PATH="$tmp/bin:$ROOT/bin:/usr/bin:/bin" \
    bash "$ROOT/bin/omarchy-capture-screenrecording" "$@" >"$tmp/out" 2>&1 ||
    fail "the recording starts" "$(cat "$tmp/out")"
  kill $(cat "$tmp"/*.pid 2>/dev/null) 2>/dev/null || true
  rm -f "$tmp"/*.pid "$tmp/omarchy-screenrecord-mix-modules"
  calls=$(<"$CALL_LOG")
}

record 0 --fullscreen
[[ $calls == "wf-recorder [-o] [eDP-1] [-c] [libx264] "*"[-f] [$tmp/videos/screenrecording-"*".mp4] [-y]" ]] ||
  fail "Apple Silicon records the focused monitor with wf-recorder" "$calls"
[[ $calls != *gpu-screen-recorder* && $calls != *--audio* ]] || fail "no gpu-screen-recorder and no audio without audio flags" "$calls"
pass "Apple Silicon records the focused monitor with wf-recorder"

record 0
[[ $calls == "wf-recorder [-g] [10,20 300x200] "* ]] || fail "Apple Silicon records a picked region with wf-recorder" "$calls"
pass "Apple Silicon records a picked region with wf-recorder"

OMARCHY_TEST_REGION="monitor:HDMI-A-1" record 0 --resolution=1920x1080
[[ $calls == "wf-recorder [-o] [HDMI-A-1] [-F] [scale=1920:1080:force_original_aspect_ratio=decrease:force_divisible_by=2] "* ]] ||
  fail "Apple Silicon caps the size like gpu-screen-recorder's -s" "$calls"
OMARCHY_TEST_WIDTH=5120 OMARCHY_TEST_HEIGHT=2880 record 0 --fullscreen
[[ $calls == "wf-recorder [-o] [eDP-1] [-F] [scale=3840:2160:force_original_aspect_ratio=decrease:force_divisible_by=2] "* ]] ||
  fail "Apple Silicon caps a monitor above 4K at 4K like gpu-screen-recorder" "$calls"
pass "Apple Silicon caps the recording size with a scale filter"

record 0 --fullscreen --with-desktop-audio
[[ $calls == *"[--audio=speakers.monitor]"* && $calls != *load-module* ]] ||
  fail "desktop audio records the default sink's monitor" "$calls"
pass "Apple Silicon records desktop audio from the default sink's monitor"

record 0 --fullscreen --with-microphone-audio
[[ $calls == *"[--audio=microphone]"* && $calls != *load-module* ]] ||
  fail "microphone audio records the default source" "$calls"
pass "Apple Silicon records the microphone from the default source"

record 0 --fullscreen --with-desktop-audio --with-microphone-audio
[[ $calls == *"pactl load-module [module-null-sink] [sink_name=omarchy_screenrecord_mix]"* &&
  $calls == *"[module-loopback] [source=speakers.monitor] [sink=omarchy_screenrecord_mix]"* &&
  $calls == *"[module-loopback] [source=microphone] [sink=omarchy_screenrecord_mix]"* &&
  $calls == *"[--audio=omarchy_screenrecord_mix.monitor]"* ]] ||
  fail "desktop and microphone are mixed into one track" "$calls"
pass "Apple Silicon mixes desktop and microphone audio into one track"

record 1 --fullscreen --with-desktop-audio
[[ $calls == "gpu-screen-recorder [-w] [eDP-1] "*"[-a] [default_output] [-ac] [aac]" && $calls != *wf-recorder* ]] ||
  fail "other machines keep gpu-screen-recorder" "$calls"
pass "other machines keep recording with gpu-screen-recorder"

pattern=$(sed -n 's/^RECORDER_PATTERN="\(.*\)"$/\1/p' "$ROOT/bin/omarchy-capture-screenrecording")
[[ $pattern == "^(gpu-screen-recorder|wf-recorder)" ]] || fail "the script matches either recorder" "$pattern"
grep -Fq "\"when\":\"pgrep -f '$pattern'\"" "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "the menu's Stop Screenrecording entry matches either recorder"
grep -Fq "\"pgrep\", \"--quiet\", \"-f\", \"$pattern\"" "$ROOT/shell/plugins/bar/indicators/ScreenRecording.qml" ||
  fail "the bar indicator matches either recorder"
pass "the script, the menu stop entry and the bar indicator match either recorder"

grep -Fq -- "--load-scripts=no" "$ROOT/bin/omarchy-capture-screenrecording" ||
  fail "the webcam overlay keeps mpv-mpris off, so dictation doesn't pause it"
grep -Fq -- "'--vf=lavfi=[crop=ih*8/9:ih,format=yuv420p]'" "$ROOT/bin/omarchy-capture-screenrecording" ||
  fail "the webcam overlay copies frames out of the V4L2 buffer"
pass "the webcam overlay isn't an MPRIS player and owns its frames"

# --- The wf-recorder migration --------------------------------------------------
migration=$(grep -l 'Install wf-recorder so screen recording works on Apple Silicon' "$ROOT"/migrations/*.sh)
name=${migration##*/}
grep -Fq "    $name) printf 'run" "$ROOT/bin/omarchy-migrate" || fail "the migration runs on Apple Silicon" "$name"

migrate() {
  stub omarchy-hw-apple-silicon "exit $1"
  stub omarchy-pkg-present "exit $2"
  stub omarchy-pkg-add 'printf "pkg-add [%s]\n" "$@" >>"$CALL_LOG"'
  : >"$CALL_LOG"
  PATH="$tmp/bin:/usr/bin:/bin" bash "$migration" >/dev/null 2>&1 || fail "the migration succeeds" "$(cat "$CALL_LOG")"
  calls=$(<"$CALL_LOG")
}

migrate 0 1
[[ $calls == "pkg-add [wf-recorder]" ]] || fail "the migration installs wf-recorder on a Mac without it" "$calls"
migrate 0 0
[[ -z $calls ]] || fail "the migration leaves an installed wf-recorder alone" "$calls"
migrate 1 1
[[ -z $calls ]] || fail "the migration does nothing off Apple Silicon" "$calls"
pass "the migration installs wf-recorder on Apple Silicon Macs that miss it"
