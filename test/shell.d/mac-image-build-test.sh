#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

installer="$ROOT/bin/omarchy-install-asahi-fresh"
runner="$ROOT/bin/omarchy-mac-run-deferred-steps"
helper="$ROOT/install/helpers/mac-image-build.sh"
hardware_all="$ROOT/install/hardware/all.sh"
hw_detect="$ROOT/bin/omarchy-hw-apple-silicon"
updater="$ROOT/bin/omarchy-update-asahi-repository"
post_pacman="$ROOT/install/post-install/pacman.sh"
hid_leaf="$ROOT/install/hardware/apple/fix-asahi-hid-race.sh"
btrfs_leaf="$ROOT/install/hardware/apple/fix-asahi-btrfs-race.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

OMARCHY_PATH="$ROOT" OMARCHY_INSTALL="$ROOT/install" source "$helper"

# Independent of omarchy_mac_hardware_step_paths: every hardware/*.sh path
# mentioned in all.sh, in file order, minus the static initramfs leaves.
expected_deferred_steps() {
  local relative
  while IFS= read -r relative; do
    [[ -n $relative ]] || continue
    omarchy_mac_deferred_step_rebuilds_initramfs "$relative" && continue
    printf '%s\n' "$relative"
  done < <(awk '
    {
      rest = $0
      while (match(rest, /hardware\/[-A-Za-z0-9._/]+\.sh/)) {
        print "install/" substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
  ' "$hardware_all")
}

bash -n "$installer"
bash -n "$runner"
bash -n "$helper"
bash -n "$hw_detect"
grep -Fq '# omarchy:hidden=true' "$runner" || fail "the deferred-steps runner is hidden from command listings"
grep -Fq '# omarchy:requires-sudo=true' "$runner" || fail "the deferred-steps runner requires root"
grep -Fq 'OMARCHY_MAC_TARGET=generic-apple-silicon' "$helper" ||
  fail "the helper documents the generic Apple Silicon image-build target"
! grep -Fq 'omarchy_mac_generic_target' "$helper" "$installer" "$runner" ||
  fail "the unused generic-target helper is gone"
grep -Fq 'omarchy_mac_export_image_identity' "$installer" ||
  fail "the installer exports the generic image-build identity"
grep -Fq '"$OMARCHY_INSTALL/hardware/all.sh"' "$installer" ||
  fail "the installer applies static boot leaves through hardware/all.sh"
! grep -Fq '/usr/share/omarchy/install/hardware/apple/fix-asahi-hid-race.sh' "$installer" ||
  fail "the installer does not hard-code static Apple boot leaf paths"
export_line=$(grep -n 'export OMARCHY_MAC_TARGET=generic-apple-silicon' "$installer" | head -n 1 | cut -d: -f1)
config_line=$(grep -n 'configure_package_repository /etc/pacman.conf' "$installer" | head -n 1 | cut -d: -f1)
[[ -n $export_line && -n $config_line ]] || fail "the installer exports identity and configures the repository"
(( export_line < config_line )) ||
  fail "the installer exports the generic identity before configure_package_repository"
! grep -Fq 'image-build-proc' "$installer" || fail "the installer does not invent a fake /proc tree"
! grep -Fq 'apple,omarchy-image' "$installer" || fail "the installer does not fake an Apple device-tree"
awk '
  /mark_initramfs_rebuild/ { mark = NR }
  /remaining=\("\$\{remaining\[@\]:1\}"\)/ { drop = NR }
  END { exit !(mark && drop && mark < drop) }
' "$runner" || fail "rebuild intent is recorded before a successful leaf is dropped"
pass "image-build commands are syntactically valid and hidden"

# --- run_logged parser accepts formatting variants ----------------------------

fmt_install="$test_tmp/fmt-install/hardware"
mkdir -p "$fmt_install"
cat >"$fmt_install/all.sh" <<'EOF'
# comment with hardware/ignored.sh should still parse run_logged lines
run_logged "$OMARCHY_INSTALL/hardware/network.sh"
  run_logged  "$OMARCHY_INSTALL/hardware/bluetooth.sh"
run_logged "$OMARCHY_INSTALL/hardware/apple/fix-speaker-pop.sh" || true
run_logged $OMARCHY_INSTALL/hardware/pacman.sh
EOF
fmt_paths=$(OMARCHY_INSTALL="$test_tmp/fmt-install" omarchy_mac_hardware_step_paths)
[[ $fmt_paths == $'install/hardware/network.sh\ninstall/hardware/bluetooth.sh\ninstall/hardware/apple/fix-speaker-pop.sh\ninstall/hardware/pacman.sh' ]] ||
  fail "run_logged parser accepts indented, extra-arg and unquoted lines" "$fmt_paths"
pass "run_logged parser accepts formatting variants"

# --- hardware/all.sh applies static drop-ins and defers probing leaves --------

sandbox="$test_tmp/all-root"
mkdir -p "$sandbox/etc" "$test_tmp/all-bin"
: >"$test_tmp/run-logged"
sed -e "s|/etc/mkinitcpio.conf.d|$sandbox/etc/mkinitcpio.conf.d|g" "$hid_leaf" >"$test_tmp/hid.sh"
sed -e "s|/etc/systemd/system|$sandbox/etc/systemd/system|g" "$btrfs_leaf" >"$test_tmp/btrfs.sh"
cat >"$test_tmp/all-bin/omarchy-hw-apple-silicon" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$test_tmp/all-bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
chmod +x "$test_tmp/all-bin"/*
run_logged() {
  printf '%s\n' "$1" >>"$test_tmp/run-logged"
  case $1 in
    */fix-asahi-hid-race.sh)
      bash -eE -c 'source "$1"' bash "$test_tmp/hid.sh"
      ;;
    */fix-asahi-btrfs-race.sh)
      bash -eE -c 'source "$1"' bash "$test_tmp/btrfs.sh"
      ;;
    *)
      fail "hardware setup ran a probing leaf during an image build: $1"
      ;;
  esac
}

OMARCHY_MAC_IMAGE_BUILD=1 \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_MAC_DEFERRED_STEPS="$sandbox/deferred-steps" \
  PATH="$test_tmp/all-bin:$PATH" \
  source "$hardware_all"
unset OMARCHY_MAC_TARGET OMARCHY_MAC_IMAGE_BUILD OMARCHY_MAC_DEFERRED_STEPS
[[ $(cat "$test_tmp/run-logged") == *$ROOT/install/hardware/apple/fix-asahi-hid-race.sh*$'\n'*$ROOT/install/hardware/apple/fix-asahi-btrfs-race.sh ]] ||
  fail "image-build hardware setup applies the HID and btrfs drop-ins" "$(cat "$test_tmp/run-logged")"
[[ -f $sandbox/etc/mkinitcpio.conf.d/apple_hid_modules.conf ]] ||
  fail "image-build hardware setup wrote the HID drop-in"
[[ -f $sandbox/etc/systemd/system/kmod-static-nodes.service.d/10-before-tmpfiles-setup-dev.conf ]] ||
  fail "image-build hardware setup wrote the btrfs drop-in"
[[ -f $sandbox/deferred-steps ]] || fail "image-build hardware setup wrote deferred-steps"
[[ $(stat -c '%a' "$sandbox/deferred-steps") == 644 ]] ||
  fail "deferred-steps is created 0644" "$(stat -c '%a' "$sandbox/deferred-steps")"
diff -u <(expected_deferred_steps) "$sandbox/deferred-steps" ||
  fail "deferred-steps lists probing hardware/all.sh scripts, not HID or btrfs"
! grep -Fq 'fix-asahi-hid-race.sh' "$sandbox/deferred-steps" ||
  fail "HID setup is not deferred"
! grep -Fq 'fix-asahi-btrfs-race.sh' "$sandbox/deferred-steps" ||
  fail "btrfs setup is not deferred"
while IFS= read -r apple; do
  name=$(basename "$apple")
  [[ $name == fix-asahi-hid-race.sh || $name == fix-asahi-btrfs-race.sh ]] && continue
  grep -Fxq "install/hardware/apple/$name" "$sandbox/deferred-steps" ||
    fail "deferred-steps includes $apple"
done < <(printf '%s\n' "$ROOT"/install/hardware/apple/*.sh)
pass "hardware/all.sh keeps static boot drop-ins and defers probing leaves"

# --- omarchy-hw-apple-silicon honors the generic image-build target -----------

hw_bin="$test_tmp/hw-bin"
hw_proc="$test_tmp/hw-proc"
mkdir -p "$hw_bin" "$hw_proc/device-tree"
cat >"$hw_bin/uname" <<'EOF'
#!/bin/bash
printf '%s\n' "${OMARCHY_TEST_ARCH:-aarch64}"
EOF
chmod +x "$hw_bin/uname"
printf 'linux,dummy-virt\0' >"$hw_proc/device-tree/compatible"

if OMARCHY_TEST_ARCH=aarch64 OMARCHY_PROC_ROOT="$hw_proc" PATH="$hw_bin:$PATH" \
  "$hw_detect"; then
  fail "without a target, a non-Apple device-tree is not Apple Silicon"
fi
pass "without a target, hardware detection probes the device-tree"

OMARCHY_TEST_ARCH=aarch64 OMARCHY_MAC_TARGET=generic-apple-silicon \
  OMARCHY_PROC_ROOT="$hw_proc" PATH="$hw_bin:$PATH" "$hw_detect" ||
  fail "generic-apple-silicon is Apple Silicon without probing /proc/device-tree"
pass "generic-apple-silicon reports Apple Silicon without a device-tree probe"

printf 'apple,j314s\0apple,arm-platform\0' >"$hw_proc/device-tree/compatible"
if OMARCHY_TEST_ARCH=aarch64 OMARCHY_MAC_TARGET=something-else \
  OMARCHY_PROC_ROOT="$hw_proc" PATH="$hw_bin:$PATH" "$hw_detect"; then
  fail "an unknown OMARCHY_MAC_TARGET is not Apple Silicon"
fi
if OMARCHY_TEST_ARCH=x86_64 OMARCHY_MAC_TARGET=generic-apple-silicon \
  OMARCHY_PROC_ROOT="$hw_proc" PATH="$hw_bin:$PATH" "$hw_detect"; then
  fail "generic-apple-silicon still requires aarch64"
fi
pass "an unknown target and a non-aarch64 host are not Apple Silicon"

# --- the real updater needs the generic identity without a device-tree --------

empty_proc="$test_tmp/empty-proc"
mkdir -p "$empty_proc" "$test_tmp/updater-bin"
cat >"$test_tmp/updater-bin/uname" <<'EOF'
#!/bin/bash
printf '%s\n' aarch64
EOF
chmod +x "$test_tmp/updater-bin/uname"
updater_path="$test_tmp/updater-bin:$ROOT/bin:$PATH"
status=0
OMARCHY_PROC_ROOT="$empty_proc" PATH="$updater_path" \
  "$updater" --yes --bootstrap >"$test_tmp/updater-no-target.out" 2>"$test_tmp/updater-no-target.err" || status=$?
(( status == 1 )) ||
  fail "without a generic target the updater refuses missing Apple hardware" \
    "status $status: $(cat "$test_tmp/updater-no-target.out" "$test_tmp/updater-no-target.err")"
pass "the real updater fails without Apple hardware or a generic target"

status=0
OMARCHY_MAC_TARGET=generic-apple-silicon OMARCHY_PROC_ROOT="$empty_proc" \
  OMARCHY_ASAHI_PACKAGE_KEY_FILE="$test_tmp/missing-arm.asc" \
  OMARCHY_ASAHI_KEY_FILE="$test_tmp/missing-release.gpg" \
  PATH="$updater_path" \
  "$updater" --yes --bootstrap >"$test_tmp/updater-generic.out" 2>"$test_tmp/updater-generic.err" || status=$?
(( status != 1 )) ||
  fail "generic-apple-silicon gets the updater past Apple hardware detection" \
    "$(cat "$test_tmp/updater-generic.out" "$test_tmp/updater-generic.err")"
pass "generic-apple-silicon lets the real updater past hardware detection"

# --- omarchy-mac-run-deferred-steps is fail-closed and resumable --------------

omarchy="$test_tmp/omarchy"
first_boot="$test_tmp/var/lib/omarchy/mac-first-boot"
log_dir="$test_tmp/var/log/omarchy"
mkdir -p "$omarchy/install/hardware/apple" "$omarchy/install/helpers" "$omarchy/bin" \
  "$first_boot" "$log_dir" "$test_tmp/bin" "$omarchy/etc"
cp "$ROOT/install/helpers/logging.sh" "$omarchy/install/helpers/logging.sh"
cp "$helper" "$omarchy/install/helpers/mac-image-build.sh"
cp "$hw_detect" "$omarchy/bin/omarchy-hw-apple-silicon"
sed -e "s|/etc/mkinitcpio.conf.d|$omarchy/etc/mkinitcpio.conf.d|g" "$hid_leaf" \
  >"$omarchy/install/hardware/apple/fix-asahi-hid-race.sh"
sed -e "s|/etc/systemd/system|$omarchy/etc/systemd/system|g" "$btrfs_leaf" \
  >"$omarchy/install/hardware/apple/fix-asahi-btrfs-race.sh"
cat >"$omarchy/install/hardware/apple/fix-speaker-pop.sh" <<'EOF'
printf 'speaker target=%s image=%s\n' "${OMARCHY_MAC_TARGET-unset}" "${OMARCHY_MAC_IMAGE_BUILD-unset}" >>"$MAC_IMAGE_BUILD_RAN"
EOF
mkdir -p "$test_tmp/apple-proc/device-tree"
printf 'apple,j314s\0apple,arm-platform\0' >"$test_tmp/apple-proc/device-tree/compatible"

cat >"$test_tmp/bin/uname" <<'EOF'
#!/bin/bash
printf '%s\n' aarch64
EOF
cat >"$test_tmp/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
cat >"$test_tmp/bin/mkinitcpio" <<'EOF'
#!/bin/bash
printf 'mkinitcpio %s\n' "$*" >>"$MAC_IMAGE_BUILD_MKINITCPIO"
EOF
chmod +x "$test_tmp/bin/uname" "$test_tmp/bin/sudo" "$test_tmp/bin/mkinitcpio"

runnable_runner="$test_tmp/omarchy-mac-run-deferred-steps"
sed -e 's@^(( EUID == 0 )) || fail .*@true # test-only root boundary@' "$runner" >"$runnable_runner"
chmod +x "$runnable_runner"

status=0
env -u OMARCHY_PATH bash "$runnable_runner" >"$test_tmp/missing-path.out" 2>"$test_tmp/missing-path.err" || status=$?
(( status != 0 )) || fail "the deferred runner requires OMARCHY_PATH"
grep -Fq 'OMARCHY_PATH is unset' "$test_tmp/missing-path.err" ||
  fail "the deferred runner reports a missing OMARCHY_PATH" "$(cat "$test_tmp/missing-path.err")"
pass "omarchy-mac-run-deferred-steps fails when OMARCHY_PATH is unset"

printf '%s\n' install/hardware/apple/fix-asahi-hid-race.sh install/hardware/apple/broken.sh >"$first_boot/deferred-steps"
cat >"$omarchy/install/hardware/apple/broken.sh" <<'EOF'
false
EOF
rm -rf "$omarchy/etc"
: >"$test_tmp/ran"
: >"$test_tmp/mkinitcpio.log"
status=0
MAC_IMAGE_BUILD_RAN="$test_tmp/ran" \
  MAC_IMAGE_BUILD_MKINITCPIO="$test_tmp/mkinitcpio.log" \
  OMARCHY_PATH="$omarchy" \
  OMARCHY_PROC_ROOT="$test_tmp/apple-proc" \
  OMARCHY_MAC_DEFERRED_STEPS="$first_boot/deferred-steps" \
  OMARCHY_MAC_FIRST_BOOT_LOG="$log_dir/mac-first-boot.log" \
  PATH="$test_tmp/bin:$PATH" \
  bash "$runnable_runner" >"$test_tmp/broken.out" 2>"$test_tmp/broken.err" || status=$?
(( status != 0 )) || fail "a failing deferred step fails the runner"
grep -Fq 'Deferred step failed: install/hardware/apple/broken.sh' "$test_tmp/broken.err" ||
  fail "a failing deferred step is reported" "$(cat "$test_tmp/broken.err")"
[[ -f $omarchy/etc/mkinitcpio.conf.d/apple_hid_modules.conf ]] ||
  fail "the HID leaf still ran before the failure"
[[ $(cat "$first_boot/deferred-steps") == $'install/hardware/apple/broken.sh' ]] ||
  fail "a failed step and nothing after it stay on the list" "$(cat "$first_boot/deferred-steps")"
[[ -f $first_boot/rebuild-initramfs ]] || fail "a HID leaf that succeeded before a failure still marks an initramfs rebuild"
[[ ! -s $test_tmp/mkinitcpio.log ]] || fail "a failed run does not rebuild the initramfs" "$(cat "$test_tmp/mkinitcpio.log")"
pass "a failed deferred step is kept so a rerun resumes"

# --- post-install/pacman.sh keeps the image's pinned repositories -------------

pacman_root="$test_tmp/pacman-root"
pacman_omarchy="$test_tmp/pacman-omarchy"
mkdir -p "$pacman_root/etc/pacman.d" "$pacman_omarchy/default/pacman" \
  "$pacman_omarchy/install/hardware" "$test_tmp/pacman-bin"
cat >"$pacman_root/etc/pacman.conf" <<'CONF'
[options]
Architecture = aarch64

[omarchy-aurora]
SigLevel = Required DatabaseOptional
Server = https://github.com/maralcbr/omarchy-pkgs/releases/download/aurora-packages-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

[omarchy]
SigLevel = Required DatabaseOptional
Server = https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-packages-stable-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

[asahi-alarm]
Server = https://example.test/asahi-alarm
CONF
cp "$pacman_root/etc/pacman.conf" "$test_tmp/pacman.conf.orig"
printf 'X86_PACMAN_CONF\n' >"$pacman_omarchy/default/pacman/pacman-stable.conf"
printf 'X86_MIRRORLIST\n' >"$pacman_omarchy/default/pacman/mirrorlist-stable"
cp "$ROOT/install/hardware/pacman.sh" "$pacman_omarchy/install/hardware/pacman.sh"
sed "s#/etc/#$pacman_root/etc/#g" "$post_pacman" >"$test_tmp/post-install-pacman.sh"
cat >"$test_tmp/pacman-bin/pacman-key" <<'EOF'
#!/bin/bash
echo "pacman-key $*" >>"$MAC_IMAGE_BUILD_PACMAN"
exit 1
EOF
cat >"$test_tmp/pacman-bin/lspci" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$test_tmp/pacman-bin"/*
: >"$test_tmp/pacman.calls"

OMARCHY_MAC_IMAGE_BUILD=1 \
  OMARCHY_MAC_TARGET=generic-apple-silicon \
  OMARCHY_PATH="$pacman_omarchy" \
  OMARCHY_INSTALL="$pacman_omarchy/install" \
  MAC_IMAGE_BUILD_PACMAN="$test_tmp/pacman.calls" \
  PATH="$test_tmp/pacman-bin:$PATH" \
  bash -eE -c 'source "$1"' bash "$test_tmp/post-install-pacman.sh"
diff -u "$test_tmp/pacman.conf.orig" "$pacman_root/etc/pacman.conf" ||
  fail "image-mode pacman.sh keeps the pinned [omarchy] and [omarchy-aurora] sections"
[[ ! -s $test_tmp/pacman.calls ]] ||
  fail "image-mode pacman.sh does not re-sign or rewrite the package repositories" "$(cat "$test_tmp/pacman.calls")"
pass "post-install/pacman.sh keeps the image's pinned pacman sections"

# --- Fake chroot: real updater, real apply-system hardware path, Aurora -------

sandbox="$test_tmp/root"
stub_bin="$test_tmp/bin"
bundle="$test_tmp/bundle"
calls="$test_tmp/calls"
assets="$test_tmp/assets"
mkdir -p "$stub_bin" "$bundle" "$test_tmp/tmp" "$assets"
rm -f "$stub_bin/uname" "$stub_bin/sudo" "$stub_bin/mkinitcpio"

runnable="$test_tmp/omarchy-install-asahi-fresh"
sed \
  -e 's@^(( EUID == 0 )) || fail .*@true # test-only root boundary@' \
  -e 's@^\[\[ \$(uname -m) == "aarch64" \]\] || fail .*@true # test-only architecture boundary@' \
  -e "s#\([ \"=<>]\)\(/proc/\|/usr/share/omarchy\|/boot/\|/var/lib/\|/etc/\|/run/lock/\|/sys/\|/usr/lib/modules/\|/home/\|/dev/tty\)#\1$sandbox\2#g" \
  "$installer" >"$runnable"

stub() {
  cat >"$stub_bin/$1"
  chmod +x "$stub_bin/$1"
}

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
    ignored=""
    while (($#)); do
      case "$1" in
        --ignore) ignored=$2; shift ;;
      esac
      shift
    done
    echo "pacman -Syu ignore=$ignored repositories=$(repositories)" >>"$FRESH_TEST_LOG"
    printf '%s\n' hyprland >>"$installed"
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

for logged in gpasswd usermod update-m1n1 omarchy-apple-silicon-boot-check; do
  stub "$logged" <<EOF
#!/bin/bash
echo "$logged \$*" >>"\$FRESH_TEST_LOG"
EOF
done

stub mkinitcpio <<'EOF'
#!/bin/bash
echo "mkinitcpio $*" >>"$FRESH_TEST_LOG"
printf 'usr/lib/modules/%s/kernel/hid.ko\n' "$FRESH_TEST_KERNEL_VERSION" >"$FRESH_TEST_ROOT/boot/initramfs-$FRESH_TEST_KERNEL.img"
EOF

stub update-grub <<'EOF'
#!/bin/bash
echo "update-grub $*" >>"$FRESH_TEST_LOG"
printf '# generated\nlinux /vmlinuz-%s root=UUID=test\ninitrd /initramfs-%s.img\n' "$FRESH_TEST_KERNEL" "$FRESH_TEST_KERNEL" >"$FRESH_TEST_ROOT/boot/grub/grub.cfg"
EOF

stub lsinitcpio <<'EOF'
#!/bin/bash
[[ $1 == -l ]] && cat "$2"
EOF

stub NetworkManager <<'EOF'
#!/bin/bash
echo "wifi.backend=none"
EOF

stub swapon <<'EOF'
#!/bin/bash
echo "/dev/zram0"
EOF

stub id <<'EOF'
#!/bin/bash
echo "$2 wheel"
EOF

stub chown <<'EOF'
#!/bin/bash
EOF

stub uname <<'EOF'
#!/bin/bash
printf '%s\n' aarch64
EOF

stub sudo <<'EOF'
#!/bin/bash
exec "$@"
EOF

stub omarchy-apply-system <<'EOF'
#!/bin/bash
echo "omarchy-apply-system $*" >>"$FRESH_TEST_LOG"
export OMARCHY_PATH="${OMARCHY_PATH:-$FRESH_TEST_ROOT/usr/share/omarchy}"
export OMARCHY_INSTALL="${OMARCHY_INSTALL:-$OMARCHY_PATH/install}"
export PATH="$OMARCHY_PATH/bin:$PATH"
source "$OMARCHY_INSTALL/helpers/logging.sh"
source "$OMARCHY_INSTALL/hardware/all.sh"
source "$OMARCHY_INSTALL/post-install/pacman.sh"
EOF

stable_commit=901e39bdc0dd42a93644bce14a07eeb9bb18a12c
release_dir="$assets/asahi-packages-stable-$stable_commit"
mkdir -p "$release_dir" "$assets/asahi-packages-channel-1" "$assets/asahi-packages-channel-2"
printf 'omarchy database for %s\n' "$stable_commit" >"$release_dir/omarchy.db"
printf 'signature\n' >"$release_dir/omarchy.db.sig"
cat >"$release_dir/CANDIDATE" <<EOF
format=1
channel=candidate
release_tag=asahi-packages-candidate-$stable_commit
source_commit=$stable_commit
workflow_run=33487927893
runner_arch=aarch64
signing_fingerprint=CAB18E175BFB9ACCE185234474DE0C737AC186E4
package_count=2
asset=omarchy.db|$(sha256sum "$release_dir/omarchy.db" | cut -d' ' -f1)
asset=omarchy.db.sig|$(sha256sum "$release_dir/omarchy.db.sig" | cut -d' ' -f1)
asset=omarchy.files|$(printf '%064d' 1)
asset=omarchy.files.sig|$(printf '%064d' 2)
package=1|aether|4.27.2-1|aarch64|aether-4.27.2-1-aarch64.pkg.tar.zst|$(printf '%064d' 3)|aether-4.27.2-1-aarch64.pkg.tar.zst.sig|$(printf '%064d' 4)
package=2|yay|12.6.0-1|aarch64|yay-12.6.0-1-aarch64.pkg.tar.zst|$(printf '%064d' 5)|yay-12.6.0-1-aarch64.pkg.tar.zst.sig|$(printf '%064d' 6)
EOF
printf 'signature\n' >"$release_dir/CANDIDATE.sig"
descriptor=$(sha256sum "$release_dir/CANDIDATE" | cut -d' ' -f1)
pinned_commit=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
printf 'format=1\nchannel=asahi-packages\nsequence=1\nstable_tag=asahi-packages-stable-%s\ndescriptor_sha256=%s\nsupersedes=\n' \
  "$stable_commit" "$descriptor" >"$assets/asahi-packages-channel-1/asahi-packages-channel"
printf 'signature\n' >"$assets/asahi-packages-channel-1/asahi-packages-channel.sig"
# An advanced channel that supersedes the builder's pin. Image mode must ignore it.
printf 'format=1\nchannel=asahi-packages\nsequence=2\nstable_tag=asahi-packages-stable-%s\ndescriptor_sha256=%s\nsupersedes=%s\n' \
  "$stable_commit" "$descriptor" "$pinned_commit" >"$assets/asahi-packages-channel-2/asahi-packages-channel"
printf 'signature\n' >"$assets/asahi-packages-channel-2/asahi-packages-channel.sig"

runtime="$test_tmp/runtime"
mkdir -p "$runtime/usr/bin" "$runtime/usr/share/omarchy/default" "$runtime/usr/share/omarchy/install"
cp "$ROOT/default/omarchy-release.gpg" "$runtime/usr/share/omarchy/default/omarchy-release.gpg"
cp "$ROOT/default/omarchy-arm-repository.asc" "$runtime/usr/share/omarchy/default/omarchy-arm-repository.asc"
cp "$updater" "$runtime/usr/bin/omarchy-update-asahi-repository"
cp "$hw_detect" "$runtime/usr/bin/omarchy-hw-apple-silicon"
cp "$ROOT/bin/omarchy-cmd-present" "$runtime/usr/bin/omarchy-cmd-present"
printf '%s\n' hyprland linux-aurora linux-aurora-headers m1n1-aurora omarchy-dev \
  >"$runtime/usr/share/omarchy/install/omarchy-base-asahi.packages"
cat >"$runtime/usr/bin/omarchy-apple-silicon-channel" <<'EOF'
#!/bin/bash
[[ ${1:-} == status ]] || exit 2
printf 'channel=rc\nkernel=linux-aurora\n'
exit 0
EOF
cat >"$runtime/usr/bin/uname" <<'EOF'
#!/bin/bash
printf '%s\n' aarch64
EOF
cat >"$runtime/usr/bin/curl" <<'EOF'
#!/bin/bash
output=""
url=""
while (($#)); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$url" >>"$FRESH_TEST_LOG"
case $url in
  https://example.test/asahi-packages-channel)
    source="$FRESH_TEST_ASSETS/asahi-packages-channel-2/asahi-packages-channel"
    ;;
  https://example.test/asahi-packages-channel.sig)
    source="$FRESH_TEST_ASSETS/asahi-packages-channel-2/asahi-packages-channel.sig"
    ;;
  https://github.com/maralcbr/omarchy-pkgs/releases/download/*)
    source="$FRESH_TEST_ASSETS/${url#https://github.com/maralcbr/omarchy-pkgs/releases/download/}"
    ;;
  *)
    exit 22
    ;;
esac
[[ -f $source && -n $output ]] || exit 22
cp "$source" "$output"
EOF
cat >"$runtime/usr/bin/gpg" <<'EOF'
#!/bin/bash
primary=C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC
subkey=CAB18E175BFB9ACCE185234474DE0C737AC186E4
release=5983B1CA32CB778F4D74D24ECFF35022CA5B5959
if [[ " $* " == *" --show-keys "* ]]; then
  if [[ $* == *omarchy-release.gpg* ]]; then
    printf 'pub:-:255:22:%s:::::::scESC::::::::0:\nfpr:::::::::%s:\n' "${release:24}" "$release"
  else
    printf 'pub:-:255:22:%s:::::::cSC::::::::0:\nfpr:::::::::%s:\n' "${primary:24}" "$primary"
  fi
  exit 0
fi
if [[ " $* " == *" --import "* ]]; then
  exit 0
fi
if [[ " $* " == *" --list-keys "* ]]; then
  printf 'pub:-:255:22:%s:::::::cSC::::::::0:\nfpr:::::::::%s:\nsub:-:255:22:%s:::::::s::::::::0:\nfpr:::::::::%s:\n' \
    "${primary:24}" "$primary" "${subkey:24}" "$subkey"
  exit 0
fi
file=${!#}
if [[ $(basename "$file") == asahi-packages-channel ]]; then
  echo "[GNUPG:] VALIDSIG $release 2026-01-01 0 4 0 1 22 00 $release"
  exit 0
fi
echo "[GNUPG:] VALIDSIG $subkey 2026-01-01 0 4 0 1 22 00 $primary"
EOF
cat >"$runtime/usr/bin/pacman-key" <<'EOF'
#!/bin/bash
echo "pacman-key $*" >>"$FRESH_TEST_LOG"
EOF
cat >"$runtime/usr/bin/pacman" <<'EOF'
#!/bin/bash
echo "updater-pacman $*" >>"$FRESH_TEST_LOG"
EOF
cat >"$runtime/usr/bin/pacman-conf" <<'EOF'
#!/bin/bash
conf=""
[[ ${1:-} != --config ]] || { conf=$2; shift 2; }
[[ -n $conf ]] || conf="$FRESH_TEST_ROOT/etc/pacman.conf"
[[ $1 == --repo-list ]] || exit 1
awk '/^[[:space:]]*\[[^]]+\][[:space:]]*$/ { gsub(/[][[:space:]]/, ""); if ($0 != "options") print }' "$conf"
EOF
cat >"$runtime/usr/bin/install" <<'EOF'
#!/bin/bash
args=()
while (($#)); do
  case "$1" in
    -o|-g) shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
exec /usr/bin/install "${args[@]}"
EOF
chmod +x "$runtime/usr/bin"/*
bsdtar -cf "$bundle/omarchy-dev-4.0.3-1-aarch64.pkg.tar.zst" -C "$runtime" usr
mkdir -p "$test_tmp/settings/usr/share/omarchy-settings"
bsdtar -cf "$bundle/omarchy-settings-dev-4.0.3-1-aarch64.pkg.tar.zst" -C "$test_tmp/settings" usr
for package in omarchy-keyring omarchy-nvim quickshell-git ttf-jetbrains-mono-nerd-basic; do
  : >"$bundle/$package-1-1-any.pkg.tar.zst"
done

builder_grub=$'# written by the image builder\nlinux /vmlinuz-KERNEL\ninitrd /initramfs-KERNEL.img'
kernel_name=linux-aurora
kernel_version=6.99.0-aurora

remap_install_tree() {
  local dest=$1 file
  mkdir -p "$dest"
  cp -a "$ROOT/install/." "$dest/"
  while IFS= read -r file; do
    sed -i \
      -e "s#\([ \"=<>':-]\)/etc/#\1$sandbox/etc/#g" \
      -e "s#\([ \"=<>':-]\)/var/lib/#\1$sandbox/var/lib/#g" \
      -e "s#\([ \"=<>':-]\)/var/log/#\1$sandbox/var/log/#g" \
      "$file"
  done < <(find "$dest" -type f -name '*.sh')
}

reset_sandbox() {
  rm -rf "$sandbox"
  mkdir -p "$sandbox"/{boot/grub,etc/pacman.d,etc/NetworkManager,run/lock,sys/module/zswap/parameters,home,dev} \
    "$sandbox/usr/share/omarchy/bin" "$sandbox/usr/lib/modules/$kernel_version" "$sandbox/var/lib"
  echo "4.0.3" >"$sandbox/usr/share/omarchy/version"
  echo "$kernel_name" >"$sandbox/usr/share/omarchy/apple-silicon-kernel"
  echo "kernel image" >"$sandbox/usr/lib/modules/$kernel_version/vmlinuz"
  cp "$sandbox/usr/lib/modules/$kernel_version/vmlinuz" "$sandbox/boot/vmlinuz-$kernel_name"
  printf '%s\n' "${builder_grub//KERNEL/$kernel_name}" >"$sandbox/boot/grub/grub.cfg"
  cat >"$sandbox/etc/pacman.conf" <<'CONF'
[options]
Architecture = aarch64

[omarchy-aurora]
SigLevel = Required DatabaseOptional
Server = https://github.com/maralcbr/omarchy-pkgs/releases/download/aurora-packages-cccccccccccccccccccccccccccccccccccccccc

[omarchy]
SigLevel = Required DatabaseOptional
Server = https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-packages-stable-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

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
  echo Y >"$sandbox/sys/module/zswap/parameters/enabled"
  printf '%s\n' base grub jq networkmanager iwd linux-aurora linux-aurora-headers m1n1-aurora >"$sandbox/installed"
  printf 'root:x:0:0::/root:/bin/bash\nalarm:x:1000:1000::/home/alarm:/bin/bash\n' >"$sandbox/passwd"
  remap_install_tree "$sandbox/usr/share/omarchy/install"
  cp "$hw_detect" "$sandbox/usr/share/omarchy/bin/omarchy-hw-apple-silicon"
  cp "$test_tmp/bin/uname" "$sandbox/usr/share/omarchy/bin/uname"
  cp "$test_tmp/bin/sudo" "$sandbox/usr/share/omarchy/bin/sudo"
  : >"$calls"
}

run_installer() {
  local name=$1 assignments=()
  shift
  while (($#)) && [[ $1 == *=* && $1 != -* ]]; do
    assignments+=("$1")
    shift
  done
  env -u FRESH_TEST_FAIL \
    PATH="$stub_bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin" \
    TMPDIR="$test_tmp/tmp" \
    FRESH_TEST_ROOT="$sandbox" \
    FRESH_TEST_LOG="$calls" \
    FRESH_TEST_ASSETS="$assets" \
    FRESH_TEST_KERNEL="$kernel_name" \
    FRESH_TEST_KERNEL_VERSION="$kernel_version" \
    OMARCHY_ASAHI_TESTING=1 \
    OMARCHY_ASAHI_ROOT="$sandbox" \
    OMARCHY_ASAHI_REPOSITORY_STATE="$sandbox/var/lib/omarchy/asahi-package-repository" \
    OMARCHY_ASAHI_PACKAGES_CHANNEL_URL="https://example.test/asahi-packages-channel" \
    OMARCHY_ASAHI_PACKAGE_SOURCE=1111111111111111111111111111111111111111 \
    OMARCHY_ASAHI_RELEASE_SEQUENCE=7 \
    OMARCHY_ASAHI_RELEASE_TAG=asahi-quattro-fe8d2bf8 \
    OMARCHY_ASAHI_RELEASE_SOURCE=2222222222222222222222222222222222222222 \
    "${assignments[@]}" bash "$runnable" --asahi-packages "$bundle" "$@" \
    >"$test_tmp/$name.out" 2>"$test_tmp/$name.err" </dev/null
}

reset_sandbox
status=0
run_installer named OMARCHY_MAC_IMAGE_BUILD=1 --user alice || status=$?
(( status != 0 )) || fail "an image build with --user succeeds"
grep -Fq 'OMARCHY_MAC_IMAGE_BUILD=1 requires --deferred-user' "$test_tmp/named.err" ||
  fail "an image build without --deferred-user is refused" "$(cat "$test_tmp/named.err")"
pass "an image build keeps --deferred-user"

reset_sandbox
cp "$sandbox/etc/pacman.conf" "$test_tmp/image-pacman.conf.orig"
status=0
run_installer image OMARCHY_MAC_IMAGE_BUILD=1 --deferred-user || status=$?
[[ $status == 0 ]] || fail "an image-build deferred install completes without device-tree, swap or zswap" "$(cat "$test_tmp/image.out" "$test_tmp/image.err")"
grep -Fq 'omarchy-apply-system --defer-provisioning --first-install' "$calls" ||
  fail "an image build still runs deferred-user system setup" "$(cat "$calls")"
! grep -Eq '^(useradd|passwd|runuser)' "$calls" || fail "an image build creates no account" "$(cat "$calls")"
deferred="$sandbox/var/lib/omarchy/mac-first-boot/deferred-steps"
[[ -f $deferred ]] || fail "the installer wrote deferred-steps"
[[ $(stat -c '%a' "$deferred") == 644 ]] || fail "the installer creates deferred-steps 0644"
diff -u <(expected_deferred_steps) "$deferred" || fail "the installer deferred probing hardware steps, not HID or btrfs"
[[ -f $sandbox/etc/mkinitcpio.conf.d/apple_hid_modules.conf ]] ||
  fail "the image contains the HID initramfs drop-in"
[[ -f $sandbox/etc/systemd/system/kmod-static-nodes.service.d/10-before-tmpfiles-setup-dev.conf ]] ||
  fail "the image contains the btrfs static-nodes drop-in"
[[ -f $sandbox/var/lib/omarchy/apple-hid-initramfs-ready ]] ||
  fail "the installer recorded the HID initramfs rebuild"
diff -u "$test_tmp/image-pacman.conf.orig" "$sandbox/etc/pacman.conf" ||
  fail "an advanced package channel leaves the image's pinned pacman.conf byte-identical"
grep -Fq 'aurora-packages-cccccccccccccccccccccccccccccccccccccccc' "$sandbox/etc/pacman.conf" ||
  fail "the image keeps the builder's [omarchy-aurora] pin" "$(cat "$sandbox/etc/pacman.conf")"
grep -Fq "asahi-packages-stable-$pinned_commit" "$sandbox/etc/pacman.conf" ||
  fail "the image keeps the builder's [omarchy] pin" "$(cat "$sandbox/etc/pacman.conf")"
! grep -Fq "$stable_commit" "$sandbox/etc/pacman.conf" ||
  fail "image mode does not advance [omarchy] to the fixture channel" "$(cat "$sandbox/etc/pacman.conf")"
grep -Eq 'image mode keeps the builder|Keeping the image' "$test_tmp/image.out" ||
  fail "image mode reports that it kept the builder's repository pins" "$(cat "$test_tmp/image.out")"
! grep -Fq 'https://example.test/asahi-packages-channel' "$calls" ||
  fail "image mode does not download an advanced package channel" "$(cat "$calls")"
grep -Fq 'pacman -Syu ignore=linux-aurora,linux-aurora-headers,m1n1-aurora' "$calls" ||
  fail "the first transaction holds the Aurora boot packages" "$(cat "$calls")"
grep -Fq 'Fresh Omarchy 4 installation complete' "$test_tmp/image.out" || fail "an image build reports completion"
! grep -Fq 'Reboot' "$test_tmp/image.out" || fail "an image build gives no reboot instruction"
pass "the fresh installer records probing steps, keeps HID/btrfs, and keeps pinned pacman sections"

# Hand the installer-produced deferred list to the runner (not a handcrafted list).
cp "$deferred" "$first_boot/deferred-steps"
chmod 0644 "$first_boot/deferred-steps"
rm -f "$first_boot/rebuild-initramfs"
: >"$test_tmp/ran"
: >"$test_tmp/mkinitcpio.log"
: >"$log_dir/mac-first-boot.log"
while IFS= read -r relative; do
  [[ -n $relative ]] || continue
  mkdir -p "$omarchy/$(dirname "$relative")"
  printf 'echo %q >>"$MAC_IMAGE_BUILD_RAN"\n' "$relative" >"$omarchy/$relative"
done <"$first_boot/deferred-steps"
cat >"$omarchy/install/hardware/apple/fix-speaker-pop.sh" <<'EOF'
printf 'speaker target=%s image=%s\n' "${OMARCHY_MAC_TARGET-unset}" "${OMARCHY_MAC_IMAGE_BUILD-unset}" >>"$MAC_IMAGE_BUILD_RAN"
EOF
status=0
MAC_IMAGE_BUILD_RAN="$test_tmp/ran" \
  MAC_IMAGE_BUILD_MKINITCPIO="$test_tmp/mkinitcpio.log" \
  OMARCHY_PATH="$omarchy" \
  OMARCHY_PROC_ROOT="$test_tmp/apple-proc" \
  OMARCHY_MAC_DEFERRED_STEPS="$first_boot/deferred-steps" \
  OMARCHY_MAC_FIRST_BOOT_LOG="$log_dir/mac-first-boot.log" \
  OMARCHY_MAC_IMAGE_BUILD=1 \
  OMARCHY_MAC_TARGET=generic-apple-silicon \
  PATH="$test_tmp/bin:$PATH" \
  bash "$runnable_runner" >"$test_tmp/deferred-run.out" 2>"$test_tmp/deferred-run.err" || status=$?
(( status == 0 )) ||
  fail "the runner completes the installer-produced deferred list" \
    "$(cat "$test_tmp/deferred-run.out" "$test_tmp/deferred-run.err")"
grep -Fq 'speaker target=unset image=unset' "$test_tmp/ran" ||
  fail "installer-produced deferred steps run in the live-machine environment" "$(cat "$test_tmp/ran")"
[[ $(grep -c . "$test_tmp/ran") == $(grep -c . "$deferred") ]] ||
  fail "the runner ran every installer-produced deferred step" "$(cat "$test_tmp/ran")"
[[ ! -s $first_boot/deferred-steps ]] ||
  fail "successful installer-produced steps are removed from the list" "$(cat "$first_boot/deferred-steps")"
[[ ! -s $test_tmp/mkinitcpio.log ]] ||
  fail "the production deferred list does not rebuild the initramfs" "$(cat "$test_tmp/mkinitcpio.log")"
: >"$test_tmp/ran"
: >"$test_tmp/mkinitcpio.log"
MAC_IMAGE_BUILD_RAN="$test_tmp/ran" \
  MAC_IMAGE_BUILD_MKINITCPIO="$test_tmp/mkinitcpio.log" \
  OMARCHY_PATH="$omarchy" \
  OMARCHY_PROC_ROOT="$test_tmp/apple-proc" \
  OMARCHY_MAC_DEFERRED_STEPS="$first_boot/deferred-steps" \
  OMARCHY_MAC_FIRST_BOOT_LOG="$log_dir/mac-first-boot.log" \
  PATH="$test_tmp/bin:$PATH" \
  bash "$runnable_runner"
[[ ! -s $test_tmp/ran ]] || fail "a second run does not repeat cleared installer-produced steps" "$(cat "$test_tmp/ran")"
pass "the runner executes the installer-produced deferred list"

reset_sandbox
rm -f "$sandbox/usr/share/omarchy/apple-silicon-kernel"
status=0
run_installer no-marker OMARCHY_MAC_IMAGE_BUILD=1 --deferred-user || status=$?
[[ $status == 0 ]] ||
  fail "an image build with no kernel marker completes" "$(cat "$test_tmp/no-marker.out" "$test_tmp/no-marker.err")"
grep -Fq 'pacman -Syu ignore=linux-aurora,linux-aurora-headers,m1n1-aurora' "$calls" ||
  fail "kernel marker absent defaults to the Aurora kernel" "$(cat "$calls")"
pass "kernel marker absent defaults to the Aurora kernel"
