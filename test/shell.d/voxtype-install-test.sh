#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_home=$(mktemp -d)
test_bin=$(mktemp -d)
test_omarchy_path=$(mktemp -d)
log_file=$(mktemp)
confirm_queue=$(mktemp)

cleanup() {
  rm -rf "$test_home" "$test_bin" "$test_omarchy_path"
  rm -f "$log_file" "$confirm_queue"
}
trap cleanup EXIT

mkdir -p "$test_omarchy_path/default/voxtype"
echo "# stub config" >"$test_omarchy_path/default/voxtype/config.toml"

# gum answers confirm prompts in order from the queue, one yes/no per line, and
# ignores every other subcommand.
cat >"$test_bin/gum" <<'EOF'
#!/bin/bash
if [[ $1 == "confirm" ]]; then
  echo "confirm:$2" >>"$TEST_LOG"
  answer=$(head -n1 "$CONFIRM_QUEUE")
  sed -i '1d' "$CONFIRM_QUEUE"
  [[ $answer == "yes" ]]
  exit $?
fi
exit 0
EOF

for cmd in omarchy-pkg-add omarchy-pkg-aur-add omarchy-restart-shell omarchy-notification-send voxtype; do
  cat >"$test_bin/$cmd" <<EOF
#!/bin/bash
echo "$cmd:\$*" >>"\$TEST_LOG"
EOF
done

cat >"$test_bin/omarchy-pkg-aur-add" <<'EOF'
#!/bin/bash
echo "omarchy-pkg-aur-add:$*" >>"$TEST_LOG"
exit "${AUR_BUILD_STATUS:-0}"
EOF

cat >"$test_bin/omarchy-pkg-aur-accessible" <<'EOF'
#!/bin/bash
exit "${AUR_ACCESSIBLE:-0}"
EOF

# PREBUILT_AVAILABLE says whether the repositories carry voxtype-bin;
# INSTALLED lists the Voxtype packages already installed.
cat >"$test_bin/omarchy-pkg-available" <<'EOF'
#!/bin/bash
echo "omarchy-pkg-available:$*" >>"$TEST_LOG"
[[ $* == voxtype-bin ]] && exit "${PREBUILT_AVAILABLE:-1}"
exit 1
EOF

cat >"$test_bin/omarchy-pkg-present" <<'EOF'
#!/bin/bash
for pkg in "$@"; do
  [[ " ${INSTALLED:-} " == *" $pkg "* ]] || exit 1
done
exit 0
EOF

cat >"$test_bin/omarchy-hw-vulkan" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$test_bin/hyprctl" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$test_bin/uname" <<'EOF'
#!/bin/bash
if [[ $1 == "-m" ]]; then
  echo "$TEST_UNAME_M"
else
  exec /usr/bin/uname "$@"
fi
EOF

chmod +x "$test_bin/"*

install_status=0
run_install() {
  local arch=$1 answers=$2 aur_accessible=${3:-0} aur_build_status=${4:-0}
  : >"$log_file"
  printf '%s\n' $answers >"$confirm_queue"
  install_status=0
  HOME="$test_home" OMARCHY_PATH="$test_omarchy_path" PATH="$test_bin:$ROOT/bin:$PATH" \
    TEST_LOG="$log_file" CONFIRM_QUEUE="$confirm_queue" AUR_ACCESSIBLE="$aur_accessible" AUR_BUILD_STATUS="$aur_build_status" \
    TEST_UNAME_M="$arch" bash "$ROOT/bin/omarchy-voxtype-install" >/dev/null || install_status=$?
}

assert_status() {
  (( install_status == $1 )) || fail "$2" "exited $install_status, expected $1"
}

run_install x86_64 "yes"
assert_status 0 "an x86_64 install succeeds"
grep -qx 'omarchy-pkg-add:wtype voxtype-bin' "$log_file" || fail "x86_64 installs the prebuilt voxtype-bin"
grep -q '^omarchy-pkg-aur-add:' "$log_file" && fail "x86_64 does not build from the AUR"
grep -q '^omarchy-pkg-available:' "$log_file" && fail "x86_64 installs voxtype-bin without an availability probe"
grep -q '^omarchy-notification-send:' "$log_file" || fail "x86_64 install sends the ready notification"
pass "x86_64 installs the prebuilt voxtype-bin"

PREBUILT_AVAILABLE=0 run_install aarch64 "yes"
assert_status 0 "an aarch64 prebuilt install succeeds"
grep -qx 'omarchy-pkg-add:wtype voxtype-bin' "$log_file" || fail "aarch64 installs voxtype-bin from the [omarchy] repository"
grep -q '^omarchy-pkg-aur-add:' "$log_file" && fail "aarch64 with voxtype-bin available does not build from the AUR"
[[ $(grep -c '^confirm:' "$log_file") == 1 ]] || fail "aarch64 with voxtype-bin available asks nothing about a source build"
grep -qx 'voxtype:setup systemd' "$log_file" || fail "aarch64 prebuilt install finishes Voxtype setup"
pass "aarch64 installs the prebuilt voxtype-bin when the repositories carry it"

INSTALLED="voxtype" PREBUILT_AVAILABLE=0 run_install aarch64 "yes"
assert_status 0 "an aarch64 install over a source build succeeds"
grep -qx 'omarchy-pkg-add:wtype' "$log_file" || fail "a Mac with a source-built voxtype only adds wtype"
grep -q 'voxtype-bin' "$log_file" && fail "a source-built voxtype is not replaced by the conflicting voxtype-bin"
grep -q '^omarchy-pkg-aur-add:' "$log_file" && fail "a source-built voxtype is not rebuilt"
grep -qx 'voxtype:setup systemd' "$log_file" || fail "a source-built voxtype still gets set up"
pass "aarch64 keeps a voxtype already built from source"

INSTALLED="voxtype voxtype-bin" run_install aarch64 "yes"
assert_status 0 "an aarch64 reinstall of voxtype-bin succeeds"
grep -qx 'omarchy-pkg-add:wtype voxtype-bin' "$log_file" || fail "an installed voxtype-bin is kept"
grep -q '^omarchy-pkg-aur-add:' "$log_file" && fail "an installed voxtype-bin is not replaced by a source build"
pass "aarch64 keeps an installed voxtype-bin"

run_install aarch64 "yes yes"
assert_status 0 "an aarch64 source build succeeds"
grep -qx 'omarchy-pkg-available:voxtype-bin' "$log_file" || fail "aarch64 checks the repositories for voxtype-bin first"
grep -qxF 'confirm:Build Voxtype from source instead? This can take 10-20 minutes.' "$log_file" ||
  fail "aarch64 asks before starting the source build"
grep -qx 'omarchy-pkg-add:wtype' "$log_file" || fail "aarch64 installs wtype from the repositories"
grep -qx 'omarchy-pkg-aur-add:voxtype' "$log_file" || fail "aarch64 builds voxtype from the AUR"
grep -q '^omarchy-pkg-add:.*voxtype-bin' "$log_file" && fail "aarch64 without voxtype-bin in its repositories never requests it"
grep -qx 'voxtype:setup systemd' "$log_file" || fail "aarch64 install finishes Voxtype setup"
pass "aarch64 without voxtype-bin in its repositories builds voxtype from the AUR"

run_install aarch64 "yes no"
assert_status 0 "declining the source build is not an error"
grep -Eq '^omarchy-pkg-(add|aur-add):' "$log_file" && fail "declining the source build installs nothing"
grep -q '^voxtype:' "$log_file" && fail "declining the source build runs no Voxtype setup"
pass "declining the aarch64 source build installs nothing"

run_install aarch64 "yes yes" 1
assert_status 1 "an unreachable AUR fails the install"
grep -Eq '^omarchy-pkg-(add|aur-add):' "$log_file" && fail "an unreachable AUR installs nothing"
pass "an unreachable AUR stops the aarch64 install before any package change"

run_install aarch64 "yes yes" 0 1
assert_status 1 "a failed source build fails the install"
grep -qx 'omarchy-pkg-aur-add:voxtype' "$log_file" || fail "a failed source build was attempted"
grep -q '^omarchy-pkg-add:' "$log_file" && fail "a failed source build leaves wtype uninstalled"
grep -q '^voxtype:' "$log_file" && fail "a failed source build runs no Voxtype setup"
pass "a failed aarch64 source build stops before wtype and Voxtype setup"

run_install aarch64 "no"
assert_status 0 "declining the install is not an error"
[[ $(grep -c '^confirm:' "$log_file") == 1 ]] || fail "declining the install asks nothing further"
grep -Eq '^omarchy-pkg-(add|aur-add):' "$log_file" && fail "declining the install installs nothing"
pass "declining the install changes nothing"
