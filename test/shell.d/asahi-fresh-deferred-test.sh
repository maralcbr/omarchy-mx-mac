#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

installer="$ROOT/bin/omarchy-install-asahi-fresh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

sandbox="$test_tmp/root"
stub_bin="$test_tmp/bin"
bundle="$test_tmp/bundle"
calls="$test_tmp/calls"
mkdir -p "$stub_bin" "$bundle" "$test_tmp/tmp"

# --- A runnable installer confined to a sandbox root --------------------------
# Every absolute system path the installer touches moves under $sandbox, and the
# root and architecture boundaries are dropped, so the real script runs anywhere.
runnable="$test_tmp/omarchy-install-asahi-fresh"
sed \
  -e 's@^(( EUID == 0 )) || fail .*@true # test-only root boundary@' \
  -e 's@^\[\[ \$(uname -m) == "aarch64" \]\] || fail .*@true # test-only architecture boundary@' \
  -e "s#\([ \"=<>]\)\(/proc/\|/usr/share/omarchy\|/boot/\|/var/lib/\|/etc/\|/run/lock/\|/sys/\|/usr/lib/modules/\|/home/\|/dev/tty\)#\1$sandbox\2#g" \
  "$installer" >"$runnable"
! grep -Eq '(EUID == 0 \)\) \|\| fail|uname -m)' "$runnable" || fail "the sandbox copy drops the root and architecture boundaries"
! grep -Eq '[ "=<>](/proc/|/boot/|/var/lib/|/etc/|/run/lock/)' "$runnable" ||
  fail "the sandbox copy touches no system path" "$(grep -En '[ "=<>](/proc/|/boot/|/var/lib/|/etc/|/run/lock/)' "$runnable")"

# --- Stubs --------------------------------------------------------------------

stub() {
  cat >"$stub_bin/$1"
  chmod +x "$stub_bin/$1"
}

# Queries answer from an exact inventory of installed package names, so a
# wrong name fails; transactions add what they install to it.
stub pacman <<'EOF'
#!/bin/bash
installed="$FRESH_TEST_ROOT/installed"
repositories() {
  awk '/^[[:space:]]*\[[^]]+\][[:space:]]*$/ { gsub(/[][[:space:]]/, ""); if ($0 != "options") { printf "%s%s", sep, $0; sep = "," } }' "$FRESH_TEST_ROOT/etc/pacman.conf"
}
case "$1" in
  -Q)
    shift
    (($#)) || { sed 's/$/ 1/' "$installed"; exit 0; }
    for package in "$@"; do
      grep -Fxq -- "$package" "$installed" || { echo "error: package '$package' was not found" >&2; exit 1; }
    done
    ;;
  -Qlq)
    grep -Fxq -- "$2" "$installed" || exit 1
    printf '/usr/lib/modules/%s/\n/usr/lib/modules/%s/vmlinuz\n' "$FRESH_TEST_KERNEL_VERSION" "$FRESH_TEST_KERNEL_VERSION"
    ;;
  -Syu)
    shift
    ignored="" targets=()
    while (($#)); do
      case "$1" in
        --ignore) ignored=$2; shift ;;
        -*) ;;
        *) targets+=("$1") ;;
      esac
      shift
    done
    echo "pacman -Syu ignore=$ignored repositories=$(repositories)" >>"$FRESH_TEST_LOG"
    [[ ${FRESH_TEST_FAIL:-} != pacman-Syu ]] || exit 1
    printf '%s\n' "${targets[@]}" >>"$installed"
    ;;
  -U)
    echo "pacman -U" >>"$FRESH_TEST_LOG"
    for archive in "$@"; do
      [[ $archive == -* ]] || basename "$archive" | sed 's/-[^-]*-[^-]*-[^-]*\.pkg\.tar\..*$//' >>"$installed"
    done
    ;;
  *) echo "unexpected pacman $*" >>"$FRESH_TEST_LOG"; exit 1 ;;
esac
EOF

stub pacman-conf <<'EOF'
#!/bin/bash
conf="$FRESH_TEST_ROOT/etc/pacman.conf"
[[ ${1:-} != --config ]] || conf=$2
awk '/^[[:space:]]*\[[^]]+\][[:space:]]*$/ { gsub(/[][[:space:]]/, ""); if ($0 != "options") print }' "$conf"
EOF

stub getent <<'EOF'
#!/bin/bash
[[ $1 == passwd ]] || exit 2
awk -F: -v key="$2" '$1 == key || $3 == key { print; found = 1 } END { exit !found }' "$FRESH_TEST_ROOT/passwd" || exit 2
EOF

stub useradd <<'EOF'
#!/bin/bash
echo "useradd $*" >>"$FRESH_TEST_LOG"
while (($# > 1)); do
  case "$1" in
    --uid) uid=$2; shift 2 ;;
    --home-dir) home=$2; shift 2 ;;
    --shell) shell=$2; shift 2 ;;
    --comment) comment=$2; shift 2 ;;
    --groups) shift 2 ;;
    *) shift ;;
  esac
done
printf '%s:x:%s:%s:%s:%s:%s\n' "$1" "$uid" "$uid" "$comment" "$home" "$shell" >>"$FRESH_TEST_ROOT/passwd"
mkdir -p "$home"
EOF

stub usermod <<'EOF'
#!/bin/bash
echo "usermod $*" >>"$FRESH_TEST_LOG"
if [[ $1 == --comment ]]; then
  awk -F: -v OFS=: -v user="$3" -v comment="$2" '$1 == user { $5 = comment } { print }' "$FRESH_TEST_ROOT/passwd" >"$FRESH_TEST_ROOT/passwd.new"
  mv "$FRESH_TEST_ROOT/passwd.new" "$FRESH_TEST_ROOT/passwd"
fi
EOF

stub id <<'EOF'
#!/bin/bash
echo "$2 wheel"
EOF

for logged in gpasswd passwd runuser update-m1n1 omarchy-apply-system omarchy-apple-silicon-boot-check; do
  stub "$logged" <<EOF
#!/bin/bash
echo "$logged \$*" >>"\$FRESH_TEST_LOG"
[[ \${FRESH_TEST_FAIL:-} != $logged ]] || exit 1
EOF
done

stub mkinitcpio <<'EOF'
#!/bin/bash
echo "mkinitcpio $*" >>"$FRESH_TEST_LOG"
modules=$FRESH_TEST_KERNEL_VERSION
[[ ${FRESH_TEST_INITRAMFS:-} != stale ]] || modules=0.0.0-old
printf 'usr/lib/modules/%s/kernel/hid.ko\n' "$modules" >"$FRESH_TEST_ROOT/boot/initramfs-$FRESH_TEST_KERNEL.img"
EOF

stub update-grub <<'EOF'
#!/bin/bash
echo "update-grub $*" >>"$FRESH_TEST_LOG"
if [[ ${FRESH_TEST_GRUB:-} == broken ]]; then
  echo "# generated without a kernel" >"$FRESH_TEST_ROOT/boot/grub/grub.cfg"
else
  printf '# generated\nlinux /vmlinuz-%s root=UUID=test\ninitrd /initramfs-%s.img\n' "$FRESH_TEST_KERNEL" "$FRESH_TEST_KERNEL" >"$FRESH_TEST_ROOT/boot/grub/grub.cfg"
fi
EOF

stub lsinitcpio <<'EOF'
#!/bin/bash
[[ $1 == -l ]] && cat "$2"
EOF

stub NetworkManager <<'EOF'
#!/bin/bash
echo "wifi.backend=iwd"
EOF

stub swapon <<'EOF'
#!/bin/bash
EOF

stub tty <<'EOF'
#!/bin/bash
EOF

stub chown <<'EOF'
#!/bin/bash
EOF

# --- The verified bundle ------------------------------------------------------
# The runtime's own updaters are stubs that record what they were given and
# rewrite pacman.conf the way the real ones place their sections.
runtime="$test_tmp/runtime"
mkdir -p "$runtime/usr/bin" "$runtime/usr/share/omarchy/default" "$runtime/usr/share/omarchy/install"
: >"$runtime/usr/share/omarchy/default/omarchy-release.gpg"
: >"$runtime/usr/share/omarchy/default/omarchy-arm-repository.asc"
printf '%s\n' hyprland linux-asahi linux-asahi-headers m1n1 omarchy-dev >"$runtime/usr/share/omarchy/install/omarchy-base-asahi.packages"

cat >"$runtime/usr/bin/omarchy-update-asahi-repository" <<'EOF'
#!/bin/bash
echo "bootstrap $* sudo=$(command -v sudo) path=$OMARCHY_PATH" >>"$FRESH_TEST_LOG"
conf="$FRESH_TEST_ROOT/etc/pacman.conf"
awk '
  /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { skip = ($0 ~ /\[omarchy\]/) }
  !placed && /^[[:space:]]*\[[^]]+\][[:space:]]*$/ && !/\[options\]/ { print "[omarchy]\nServer = https://example.test/omarchy\n"; placed = 1 }
  !skip { print }
' "$conf" >"$conf.new"
mv "$conf.new" "$conf"
EOF

cat >"$runtime/usr/bin/omarchy-apple-silicon-channel" <<'EOF'
#!/bin/bash
echo "channel $*" >>"$FRESH_TEST_LOG"
[[ $1 == status ]] || exit 2
[[ -z ${FRESH_TEST_CHANNEL_STATUS:-} ]] || exit "$FRESH_TEST_CHANNEL_STATUS"
[[ -n ${FRESH_TEST_CHANNEL:-} ]] || exit 3
printf 'channel=%s\nkernel=%s\n' "$FRESH_TEST_CHANNEL" "$FRESH_TEST_KERNEL"
EOF

cat >"$runtime/usr/bin/omarchy-update-aurora-repository" <<'EOF'
#!/bin/bash
echo "aurora $* sudo=$(command -v sudo) path=$OMARCHY_PATH" >>"$FRESH_TEST_LOG"
[[ ${FRESH_TEST_FAIL:-} != aurora ]] || exit 2
conf="$FRESH_TEST_ROOT/etc/pacman.conf"
if [[ -n ${FRESH_TEST_AURORA_CONF:-} ]]; then
  cp "$FRESH_TEST_AURORA_CONF" "$conf"
  exit 0
fi
awk '
  /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { skip = ($0 ~ /\[omarchy-aurora\]/) }
  /^[[:space:]]*\[omarchy\][[:space:]]*$/ { print "[omarchy-aurora]\nServer = https://example.test/aurora\n" }
  !skip { print }
' "$conf" >"$conf.new"
mv "$conf.new" "$conf"
EOF
chmod +x "$runtime/usr/bin"/*

bsdtar -cf "$bundle/omarchy-dev-4.0.3-1-aarch64.pkg.tar.zst" -C "$runtime" usr
mkdir -p "$test_tmp/settings/usr/share/omarchy-settings"
bsdtar -cf "$bundle/omarchy-settings-dev-4.0.3-1-aarch64.pkg.tar.zst" -C "$test_tmp/settings" usr
for package in omarchy-keyring omarchy-nvim quickshell-git ttf-jetbrains-mono-nerd-basic; do
  : >"$bundle/$package-1-1-any.pkg.tar.zst"
done

# --- Sandbox ------------------------------------------------------------------

builder_grub=$'# written by the image builder\nlinux /vmlinuz-KERNEL\ninitrd /initramfs-KERNEL.img'

reset_sandbox() {
  local kernel=${1:-linux-asahi} version=${2:-6.99.0-asahi} m1n1=${3:-m1n1}
  [[ $kernel != linux-aurora || -n ${3:-} ]] || m1n1=m1n1-aurora

  rm -rf "$sandbox"
  mkdir -p "$sandbox"/{proc/device-tree,boot/grub,etc/pacman.d,etc/NetworkManager,run/lock,sys/module/zswap/parameters,home,dev} \
    "$sandbox/usr/share/omarchy" "$sandbox/usr/lib/modules/$version" "$sandbox/var/lib"
  printf 'apple,j314s\0apple,arm-platform\0' >"$sandbox/proc/device-tree/compatible"
  echo "4.0.3" >"$sandbox/usr/share/omarchy/version"
  [[ $kernel == linux-asahi ]] || echo "$kernel" >"$sandbox/usr/share/omarchy/apple-silicon-kernel"
  echo "kernel image $version" >"$sandbox/usr/lib/modules/$version/vmlinuz"
  cp "$sandbox/usr/lib/modules/$version/vmlinuz" "$sandbox/boot/vmlinuz-$kernel"
  printf '%s\n' "${builder_grub//KERNEL/$kernel}" >"$sandbox/boot/grub/grub.cfg"
  cat >"$sandbox/etc/pacman.conf" <<'CONF'
[options]
Architecture = aarch64

[asahi-alarm]
Server = https://example.test/asahi-alarm

[core]
Server = https://example.test/core

[extra]
Server = https://example.test/extra

[alarm]
Server = https://example.test/alarm

[aur]
Server = https://example.test/aur
CONF
  echo 'LANG=en_US.UTF-8' >"$sandbox/etc/locale.conf"
  printf 'UID_MIN 1000\nUID_MAX 60000\n' >"$sandbox/etc/login.defs"
  echo N >"$sandbox/sys/module/zswap/parameters/enabled"
  printf '%s\n' base grub jq networkmanager iwd "$kernel" "$kernel-headers" "$m1n1" >"$sandbox/installed"
  printf 'root:x:0:0::/root:/bin/bash\nalarm:x:1000:1000::/home/alarm:/bin/bash\n' >"$sandbox/passwd"
  kernel_name=$kernel
  kernel_version=$version
  : >"$calls"
}

# Leading NAME=VALUE arguments configure the stubs; the rest reach the installer.
run_installer() {
  local name=$1 assignments=()
  shift
  while (($#)) && [[ $1 == *=* && $1 != -* ]]; do
    assignments+=("$1")
    shift
  done
  env -u FRESH_TEST_FAIL -u FRESH_TEST_CHANNEL -u FRESH_TEST_CHANNEL_STATUS -u FRESH_TEST_AURORA_CONF \
    -u FRESH_TEST_GRUB -u FRESH_TEST_INITRAMFS \
    PATH="$stub_bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin" \
    TMPDIR="$test_tmp/tmp" \
    FRESH_TEST_ROOT="$sandbox" \
    FRESH_TEST_LOG="$calls" \
    FRESH_TEST_KERNEL="$kernel_name" \
    FRESH_TEST_KERNEL_VERSION="$kernel_version" \
    OMARCHY_ASAHI_PACKAGE_SOURCE=1111111111111111111111111111111111111111 \
    OMARCHY_ASAHI_RELEASE_SEQUENCE=7 \
    OMARCHY_ASAHI_RELEASE_TAG=asahi-quattro-fe8d2bf8 \
    OMARCHY_ASAHI_RELEASE_SOURCE=2222222222222222222222222222222222222222 \
    "${assignments[@]}" bash "$runnable" --asahi-packages "$bundle" "$@" \
    >"$test_tmp/$name.out" 2>"$test_tmp/$name.err" </dev/null
}

expect_success() {
  [[ $1 == 0 ]] || fail "$2" "$(cat "$test_tmp/$3.out" "$test_tmp/$3.err")"
}

expect_failure() {
  local status=$1 name=$2 message=$3 description=$4
  [[ $status != 0 ]] || fail "$description (it succeeded)" "$(cat "$test_tmp/$name.out")"
  grep -Fq -- "$message" "$test_tmp/$name.err" || fail "$description" "$(cat "$test_tmp/$name.err")"
}

called() {
  grep -Eq "$1" "$calls"
}

call_line() {
  local line
  line=$(grep -En "$1" "$calls" | head -n 1 | cut -d: -f1)
  [[ -n $line ]] || fail "a call matching $1 was made" "$(cat "$calls")"
  echo "$line"
}

state_dir="$sandbox/var/lib/omarchy/fresh-install"

# --- Deferred mode ------------------------------------------------------------

bash -n "$runnable"
"$installer" --help 2>&1 | grep -Fq -- '--deferred-user' || fail "the fresh installer documents --deferred-user"

reset_sandbox
status=0
run_installer combined --deferred-user --user alice || status=$?
expect_failure "$status" combined "--user and --deferred-user cannot be combined" "a deferred install refuses a named user"
[[ ! -s $calls && ! -e $state_dir ]] || fail "a refused combination changes nothing"
pass "--deferred-user cannot be combined with --user"

reset_sandbox
status=0
run_installer deferred --deferred-user || status=$?
expect_success "$status" "a deferred install completes without a terminal or a user" deferred
! called '^(useradd|passwd|runuser|usermod --comment)' || fail "a deferred install creates, unlocks or provisions no account" "$(cat "$calls")"
[[ ! -e $sandbox/etc/sudoers.d/10-omarchy-wheel && ! -e $sandbox/var/lib/sddm/state.conf ]] ||
  fail "a deferred install leaves the owner's sudo grant and greeter state to provisioning"
called '^omarchy-apply-system --defer-provisioning --first-install$' || fail "root system setup runs for a deferred owner" "$(cat "$calls")"
grep -Fxq 'omarchy-apple-silicon-boot-check linux-asahi' "$calls" ||
  fail "a deferred install checks the linux-asahi boot chain, m1n1 stage 2 included" "$(cat "$calls")"
! called '^omarchy-apply-system --install-user' || fail "root system setup never names a user"
bootstrap_line=$(call_line '^bootstrap ')
transaction_line=$(call_line '^pacman -Syu')
apply_line=$(call_line '^omarchy-apply-system')
mkinitcpio_line=$(call_line '^mkinitcpio -P$')
grub_line=$(call_line '^update-grub')
m1n1_line=$(call_line '^update-m1n1')
(( bootstrap_line < transaction_line && transaction_line < apply_line && apply_line < mkinitcpio_line &&
  mkinitcpio_line < grub_line && grub_line < m1n1_line )) ||
  fail "a deferred install regenerates the boot files after system setup and the initramfs" "$(cat "$calls")"
[[ $(cat "$sandbox/boot/grub/grub.cfg") != "${builder_grub//KERNEL/$kernel_name}" ]] || fail "the builder's GRUB configuration is replaced"
called '^gpasswd -d alarm wheel$' && called '^usermod -L alarm$' || fail "a deferred install still retires the stock administrator"
[[ ! -e $state_dir && -f $sandbox/var/lib/omarchy/asahi-quattro-release ]] || fail "a deferred install completes its checkpoint and records the release"
grep -Fxq 'pacman -Syu ignore=linux-asahi,linux-asahi-headers,m1n1 repositories=omarchy,asahi-alarm,core,extra,alarm,aur' "$calls" ||
  fail "the first transaction holds the Asahi boot packages" "$(cat "$calls")"
grep -Fq 'Fresh Omarchy 4 installation complete' "$test_tmp/deferred.out" || fail "a deferred install reports completion"
! grep -Fq 'Reboot' "$test_tmp/deferred.out" || fail "a deferred install gives no reboot instruction"
pass "a deferred install sets up the system without an account, a terminal or a reboot instruction"

grep -Eq '^bootstrap --yes --bootstrap sudo=[^ ]+/sudo/sudo path=[^ ]+/usr/share/omarchy$' "$calls" ||
  fail "the runtime's bootstrap runs with --yes, the sudo stand-in and the runtime's files" "$(cat "$calls")"
bootstrap_invocations=$(grep -F -- '--bootstrap' "$installer")
[[ -n $bootstrap_invocations ]] && ! grep -Fv -- '--yes' <<<"$bootstrap_invocations" | grep -q . ||
  fail "every --bootstrap invocation carries --yes" "$bootstrap_invocations"
pass "--bootstrap is always called with --yes"

# --- Retries on the fixed deferred identity -----------------------------------

reset_sandbox
status=0
run_installer interrupted FRESH_TEST_FAIL=omarchy-apply-system --deferred-user || status=$?
[[ $status != 0 && -d $state_dir ]] || fail "an interrupted deferred install keeps its checkpoint"
[[ $(head -n 1 "$state_dir/release") == "identity=deferred" ]] ||
  fail "a deferred checkpoint is keyed on the fixed deferred identity" "$(cat "$state_dir/release")"

status=0
run_installer named-over-deferred --user deferred || status=$?
expect_failure "$status" named-over-deferred "belongs to a different release or user" \
  "a named install, even of a user called deferred, cannot resume a deferred checkpoint"

# What the first attempt left behind or the builder shipped is not what this
# attempt must keep: a new kernel image and a regenerated GRUB.
echo "kernel image $kernel_version rebuilt" >"$sandbox/usr/lib/modules/$kernel_version/vmlinuz"
cp "$sandbox/usr/lib/modules/$kernel_version/vmlinuz" "$sandbox/boot/vmlinuz-$kernel_name"
echo "# regenerated by an earlier attempt" >"$sandbox/boot/grub/grub.cfg"
: >"$calls"
status=0
run_installer resumed --deferred-user || status=$?
expect_success "$status" "a deferred retry resumes across a changed kernel and GRUB" resumed
called '^update-grub' && called '^update-m1n1' || fail "a deferred retry regenerates the boot files again"
[[ ! -e $state_dir ]] || fail "a resumed deferred install completes its checkpoint"
pass "a deferred retry resumes on its fixed identity and tolerates kernel and GRUB changes"

reset_sandbox
status=0
run_installer m1n1-fails FRESH_TEST_FAIL=update-m1n1 --deferred-user || status=$?
expect_failure "$status" m1n1-fails "Could not regenerate the m1n1 boot image" "a failed boot regeneration fails the install"
[[ -d $state_dir && ! -e $state_dir/completing ]] || fail "a failed boot regeneration keeps the checkpoint"
pass "a failed boot regeneration fails the attempt and keeps it resumable"

reset_sandbox
status=0
run_installer boot-chain-fails FRESH_TEST_FAIL=omarchy-apple-silicon-boot-check --deferred-user || status=$?
expect_failure "$status" boot-chain-fails "The boot files do not match the installed linux-asahi and its m1n1" "a boot chain that does not match fails the install"
[[ -d $state_dir && ! -e $state_dir/completing ]] || fail "a boot chain mismatch keeps the checkpoint"
pass "a deferred install fails and stays resumable when m1n1 stage 2 does not match"

# --- Boot verification in deferred mode ---------------------------------------

reset_sandbox
status=0
run_installer broken-grub FRESH_TEST_GRUB=broken --deferred-user || status=$?
expect_failure "$status" broken-grub "The GRUB configuration does not boot linux-asahi" "a regenerated GRUB that misses the kernel fails"
[[ -d $state_dir && ! -e $sandbox/var/lib/omarchy/asahi-quattro-release ]] || fail "a failed boot check records no release"

reset_sandbox
status=0
run_installer stale-initramfs FRESH_TEST_INITRAMFS=stale --deferred-user || status=$?
expect_failure "$status" stale-initramfs "initramfs does not carry the modules of 6.99.0-asahi" "an initramfs for another kernel fails"

reset_sandbox
echo "a kernel the package does not own" >"$sandbox/boot/vmlinuz-linux-asahi"
status=0
run_installer foreign-kernel --deferred-user || status=$?
expect_failure "$status" foreign-kernel "/boot/vmlinuz-linux-asahi is not the installed linux-asahi kernel" "a boot kernel the package does not own fails"
pass "a deferred install checks the kernel, initramfs and GRUB it regenerated against the installed kernel"

# --- Aurora repository ------------------------------------------------------

reset_sandbox linux-aurora 6.99.0-aurora
status=0
run_installer aurora FRESH_TEST_CHANNEL=rc --deferred-user || status=$?
expect_success "$status" "an rc install completes with [omarchy-aurora] ahead of [omarchy]" aurora
channel_line=$(call_line '^channel status$')
aurora_line=$(call_line '^aurora ')
bootstrap_line=$(call_line '^bootstrap ')
transaction_line=$(call_line '^pacman -Syu')
(( bootstrap_line < channel_line && channel_line < aurora_line && aurora_line < transaction_line )) ||
  fail "the Aurora updater runs after the [omarchy] bootstrap and before the first transaction" "$(cat "$calls")"
grep -Eq '^aurora  sudo=[^ ]+/sudo/sudo path=[^ ]+/usr/share/omarchy$' "$calls" ||
  fail "the Aurora updater runs from the verified runtime with the sudo stand-in" "$(cat "$calls")"
grep -Fxq 'pacman -Syu ignore=linux-aurora,linux-aurora-headers,m1n1-aurora repositories=omarchy-aurora,omarchy,asahi-alarm,core,extra,alarm,aur' "$calls" ||
  fail "the first transaction holds the Aurora boot packages and reads [omarchy-aurora] then [omarchy] first" "$(cat "$calls")"
called '^update-grub' || fail "an rc install regenerates GRUB for linux-aurora"
grep -Fxq 'omarchy-apple-silicon-boot-check linux-aurora' "$calls" ||
  fail "an rc install checks the linux-aurora boot chain" "$(cat "$calls")"
pass "an rc Mac pins [omarchy-aurora] directly ahead of [omarchy] before its first transaction"

# Each kernel requires its own m1n1 build; the other one's is no substitute.
for mismatch in "linux-aurora 6.99.0-aurora m1n1 m1n1-aurora" "linux-asahi 6.99.0-asahi m1n1-aurora m1n1"; do
  read -r kernel version installed_m1n1 required_m1n1 <<<"$mismatch"
  reset_sandbox "$kernel" "$version" "$installed_m1n1"
  status=0
  run_installer m1n1-mismatch FRESH_TEST_CHANNEL=rc --deferred-user || status=$?
  expect_failure "$status" m1n1-mismatch "Required Asahi package is not installed: $required_m1n1" \
    "$kernel with $installed_m1n1 is refused"
  [[ ! -s $calls ]] || fail "a missing m1n1 build changes nothing ($kernel)" "$(cat "$calls")"
done
pass "each kernel requires, holds and verifies its own m1n1 package"

for channel in stable ""; do
  reset_sandbox
  status=0
  run_installer "not-rc-$channel" FRESH_TEST_CHANNEL="$channel" --deferred-user || status=$?
  expect_success "$status" "a Mac without an rc record installs" "not-rc-$channel"
  called '^channel status$' || fail "the channel record is read"
  ! called '^aurora ' || fail "the Aurora updater runs only for an rc record (record: ${channel:-none})"
done
pass "a stable or unrecorded Mac never runs the Aurora updater"

reset_sandbox linux-aurora 6.99.0-aurora
status=0
run_installer untrusted-record FRESH_TEST_CHANNEL_STATUS=2 --deferred-user || status=$?
expect_failure "$status" untrusted-record "channel record cannot be trusted; no packages were installed" "an untrusted channel record stops the install"
! called '^(aurora|pacman -Syu)' || fail "an untrusted channel record installs nothing"

reset_sandbox linux-aurora 6.99.0-aurora
status=0
run_installer aurora-fails FRESH_TEST_CHANNEL=rc FRESH_TEST_FAIL=aurora --deferred-user || status=$?
expect_failure "$status" aurora-fails "Could not pin the Aurora kernel repository; no packages were installed" "a failed Aurora pin stops the install"
! called '^pacman -Syu' || fail "a failed Aurora pin installs nothing"
pass "an untrusted record or a failed Aurora pin stops before any package transaction"

layout() {
  local sections=("$@") section
  for section in "${sections[@]}"; do
    printf '[%s]\nServer = https://example.test/%s\n\n' "$section" "$section"
  done >"$test_tmp/layout.conf"
}

layout omarchy omarchy-aurora asahi-alarm core extra alarm aur
reset_sandbox linux-aurora 6.99.0-aurora
status=0
run_installer omarchy-first FRESH_TEST_CHANNEL=rc FRESH_TEST_AURORA_CONF="$test_tmp/layout.conf" --deferred-user || status=$?
expect_success "$status" "[omarchy] first is still accepted" omarchy-first

for rejected in "omarchy-aurora asahi-alarm omarchy core extra alarm aur" "asahi-alarm omarchy-aurora omarchy core extra alarm aur" "omarchy-aurora omarchy-aurora omarchy core"; do
  read -ra sections <<<"$rejected"
  layout "${sections[@]}"
  reset_sandbox linux-aurora 6.99.0-aurora
  status=0
  run_installer misordered FRESH_TEST_CHANNEL=rc FRESH_TEST_AURORA_CONF="$test_tmp/layout.conf" --deferred-user || status=$?
  expect_failure "$status" misordered "must come before every other repository, except an [omarchy-aurora] directly ahead of it" \
    "a repository order of $rejected is refused"
  ! called '^pacman -Syu' || fail "a refused repository order installs nothing ($rejected)"
done
pass "only [omarchy-aurora] directly ahead of [omarchy] may lead it"

# --- Named installs are unchanged ---------------------------------------------

reset_sandbox
: >"$sandbox/dev/tty"
status=0
run_installer named --user alice || status=$?
expect_success "$status" "a named install completes as before" named
called '^useradd --uid 1001 ' && called '^passwd alice$' || fail "a named install creates the user and sets its password" "$(cat "$calls")"
called '^omarchy-apply-system --install-user alice --first-install$' || fail "a named install runs system setup for its user"
called '^runuser -u alice -- env .* omarchy-provision-user --force --first-install$' || fail "a named install provisions its user"
! called '^(update-grub|update-m1n1)' || fail "a named install leaves GRUB and m1n1 to the base system"
! called '^omarchy-apply-system --defer-provisioning' || fail "a named install never defers provisioning"
[[ -f $sandbox/etc/sudoers.d/10-omarchy-wheel ]] && grep -Fxq 'User=alice' "$sandbox/var/lib/sddm/state.conf" ||
  fail "a named install grants wheel and seeds the greeter"
grep -Fq 'Reboot, then sign in as alice' "$test_tmp/named.out" || fail "a named install still says to reboot"
pass "a named install still creates, unlocks and provisions its user"

reset_sandbox
status=0
run_installer no-terminal --user alice || status=$?
expect_failure "$status" no-terminal "A controlling terminal is required to set the user password" "a named install still needs a terminal"

reset_sandbox
: >"$sandbox/dev/tty"
status=0
run_installer named-interrupted FRESH_TEST_FAIL=omarchy-apply-system --user alice || status=$?
[[ $status != 0 && $(head -n 1 "$state_dir/release") == "user=alice" ]] || fail "a named checkpoint is keyed on its user"
echo "# regenerated" >"$sandbox/boot/grub/grub.cfg"
status=0
run_installer named-grub-changed --user alice || status=$?
expect_failure "$status" named-grub-changed "The GRUB configuration changed after the interrupted installation" \
  "a named retry still refuses a changed GRUB"
status=0
run_installer deferred-over-named --deferred-user || status=$?
expect_failure "$status" deferred-over-named "belongs to a different release or user" "a deferred install cannot resume a named checkpoint"
pass "a named install still needs a terminal and unchanged boot files across retries"
