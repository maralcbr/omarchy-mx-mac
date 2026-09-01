#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
proc_root="$test_tmp/proc"
diag_root="$test_tmp/root"
mkdir -p "$stub_bin" "$proc_root/device-tree"

printf 'apple,j314s\0apple,arm-platform\0' >"$proc_root/device-tree/compatible"
printf 'Apple MacBook Pro (14-inch, M1 Pro, 2021)\0' >"$proc_root/device-tree/model"

cat >"$stub_bin/uname" <<'EOF'
#!/bin/bash
printf '%s\n' "${OMARCHY_TEST_ARCH:-aarch64}"
EOF

cat >"$stub_bin/pacman-conf" <<'EOF'
#!/bin/bash
printf '%s\n' ${OMARCHY_TEST_REPOS:-omarchy asahi-alarm core extra alarm}
EOF

cat >"$stub_bin/pacman" <<'EOF'
#!/bin/bash
printf '%s 1.0-1\n' "$2"
EOF

cat >"$stub_bin/systemctl" <<'EOF'
#!/bin/bash
case "$*" in
  *is-failed*) exit 1 ;;
  *is-active*speakersafetyd*) exit "${OMARCHY_TEST_SPEAKERSAFETYD:-0}" ;;
  *) exit 0 ;;
esac
EOF

cat >"$stub_bin/nmcli" <<'EOF'
#!/bin/bash
printf 'wlp1s0f0:wifi:connected\nlo:loopback:unmanaged\n'
EOF

# The Asahi speaker path appears as a wireplumber filter chain, not a plain
# sink; OMARCHY_TEST_NO_DSP drops it to leave raw hardware sinks only.
cat >"$stub_bin/wpctl" <<'EOF'
#!/bin/bash
printf 'Audio\n ├─ Devices:\n │      55. Built-in Audio [alsa]\n │  \n ├─ Sinks:\n │      59. Built-in Audio Headphones [vol: 1.00]\n │  \n ├─ Sources:\n │      60. Built-in Audio Headset Microphone [vol: 1.00]\n │  \n'
if [[ -z ${OMARCHY_TEST_NO_DSP:-} ]]; then
  printf ' ├─ Filters:\n │    - filter-chain-1774-18\n │  *   70. audio_effect.j314-convolver [Audio/Sink]\n │      71. effect_output.j314-convolver [Stream/Output/Audio]\n │  \n'
fi
printf ' └─ Streams:\n'
EOF

cat >"$stub_bin/bluetoothctl" <<'EOF'
#!/bin/bash
printf 'Controller AA:BB:CC:DD:EE:FF omarchy [default]\n'
EOF

cat >"$stub_bin/NetworkManager" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$stub_bin/omarchy-cmd-present" <<'EOF'
#!/bin/bash
[[ $1 == "omarchy-migrate" ]]
EOF

cat >"$stub_bin/omarchy-migrate" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$stub_bin"/*

build_diag_root() {
  rm -rf "$diag_root"
  mkdir -p "$diag_root/lib/firmware/brcm" \
    "$diag_root/etc/NetworkManager/conf.d" \
    "$diag_root/usr/share/omarchy" \
    "$diag_root/usr/share/vulkan/icd.d" \
    "$diag_root/sys/class/backlight/apple-panel-bl" \
    "$diag_root/sys/class/power_supply/macsmc-battery" \
    "$diag_root/sys/class/power_supply/macsmc-ac" \
    "$diag_root/dev/dri"
  touch "$diag_root/lib/firmware/brcm/brcmfmac4378b1-pcie.apple,j314s.bin"
  printf '[device]\nwifi.backend=iwd\n' \
    >"$diag_root/etc/NetworkManager/conf.d/wifi_backend.conf"
  printf '4.0.1-mac.2\n' >"$diag_root/usr/share/omarchy/version"
  printf '{}\n' >"$diag_root/usr/share/vulkan/icd.d/asahi_icd.aarch64.json"
  printf '128\n' >"$diag_root/sys/class/backlight/apple-panel-bl/brightness"
  printf '255\n' >"$diag_root/sys/class/backlight/apple-panel-bl/max_brightness"
  printf '87\n' >"$diag_root/sys/class/power_supply/macsmc-battery/capacity"
  printf 'Charging\n' >"$diag_root/sys/class/power_supply/macsmc-battery/status"
  printf '1\n' >"$diag_root/sys/class/power_supply/macsmc-ac/online"
  touch "$diag_root/dev/dri/card0" "$diag_root/dev/dri/renderD128" \
    "$diag_root/dev/video0"
}

run_diag() {
  OMARCHY_PROC_ROOT="$proc_root" OMARCHY_DIAG_ROOT="$diag_root" \
    PATH="$stub_bin:/usr/bin:/bin" "$ROOT/bin/omarchy-debug-apple" "$@"
}

build_diag_root
output=$(run_diag) || fail "a healthy Apple Silicon system passes" "$output"
[[ $output == *"PASS  repo-asahi-alarm"* ]] ||
  fail "the [asahi-alarm] repository check is reported" "$output"
[[ $output == *"PASS  vendor-firmware"* ]] ||
  fail "the vendor firmware service check is reported" "$output"
[[ $output == *"PASS  speakersafetyd"* ]] ||
  fail "the speaker safety check is reported" "$output"
[[ $output == *"PASS  audio-dsp"* && $output == *"j314-convolver"* ]] ||
  fail "the Asahi DSP filter chain is recognized" "$output"
[[ $output == *"PASS  battery"* && $output == *"87%"* ]] ||
  fail "the battery probe reads macsmc-battery" "$output"
[[ $output == *", 0 failed,"* ]] ||
  fail "a healthy system reports zero failures" "$output"
pass "a healthy Apple Silicon system passes every check"

if output=$(OMARCHY_TEST_REPOS="core extra alarm" run_diag); then
  fail "a missing [asahi-alarm] repository must fail the report" "$output"
fi
[[ $output == *"FAIL  repo-asahi-alarm"* ]] ||
  fail "the missing repository is named in the report" "$output"
pass "a missing [asahi-alarm] repository fails the report"

if output=$(OMARCHY_TEST_NO_DSP=1 run_diag); then
  fail "raw sinks without the Asahi DSP chain must fail the report" "$output"
fi
[[ $output == *"FAIL  audio-dsp"* ]] ||
  fail "a missing Asahi DSP chain is named in the report" "$output"
pass "raw sinks without the Asahi DSP chain fail the report"

if output=$(OMARCHY_TEST_SPEAKERSAFETYD=3 run_diag); then
  fail "an inactive speakersafetyd must fail the report" "$output"
fi
[[ $output == *"FAIL  speakersafetyd"* ]] ||
  fail "the inactive speaker safety service is named" "$output"
pass "an inactive speakersafetyd fails the report"

rm "$diag_root/lib/firmware/brcm/brcmfmac4378b1-pcie.apple,j314s.bin"
if output=$(run_diag); then
  fail "missing Wi-Fi firmware must fail the report" "$output"
fi
[[ $output == *"FAIL  wifi-firmware"* ]] ||
  fail "the missing Wi-Fi firmware is named" "$output"
pass "missing Wi-Fi firmware fails the report"
build_diag_root

output=$(run_diag --json) || fail "JSON mode succeeds on a healthy system" "$output"
[[ $output == *'"failed": 0'* && $output == *'"id": "repo-asahi-alarm"'* ]] ||
  fail "JSON mode reports structured checks" "$output"
pass "JSON mode reports structured checks"

if output=$(OMARCHY_TEST_ARCH=x86_64 run_diag 2>&1); then
  fail "a non-Apple machine is rejected" "$output"
fi
[[ $output == *"not an Apple Silicon Mac"* ]] ||
  fail "the non-Apple rejection is explained" "$output"
pass "a non-Apple machine is rejected with a clear message"
