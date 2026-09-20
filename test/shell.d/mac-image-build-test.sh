#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

installer="$ROOT/bin/omarchy-install-asahi-fresh"
runner="$ROOT/bin/omarchy-mac-run-deferred-steps"
helper="$ROOT/install/helpers/mac-image-build.sh"
hardware_all="$ROOT/install/hardware/all.sh"
hw_detect="$ROOT/bin/omarchy-hw-apple-silicon"
post_pacman="$ROOT/install/post-install/pacman.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

expected_steps() {
  sed -n 's/^run_logged "\$OMARCHY_INSTALL\/\(hardware\/.*\)"$/install\/\1/p' "$hardware_all"
}

bash -n "$installer"
bash -n "$runner"
bash -n "$helper"
bash -n "$hw_detect"
grep -Fq '# omarchy:hidden=true' "$runner" || fail "the deferred-steps runner is hidden from command listings"
grep -Fq '# omarchy:requires-sudo=true' "$runner" || fail "the deferred-steps runner requires root"
grep -Fq 'OMARCHY_MAC_TARGET=generic-apple-silicon' "$helper" ||
  fail "the helper documents the generic Apple Silicon image-build target"
grep -Fq 'omarchy_mac_export_image_identity' "$installer" ||
  fail "the installer exports the generic image-build identity"
! grep -Fq 'image-build-proc' "$installer" || fail "the installer does not invent a fake /proc tree"
! grep -Fq 'apple,omarchy-image' "$installer" || fail "the installer does not fake an Apple device-tree"
pass "image-build commands are syntactically valid and hidden"

# --- hardware/all.sh records every hardware leaf and runs none of them --------

sandbox="$test_tmp/all-root"
mkdir -p "$sandbox"
: >"$test_tmp/run-logged"
run_logged() {
  printf '%s\n' "$1" >>"$test_tmp/run-logged"
  fail "hardware setup ran during an image build: $1"
}

OMARCHY_MAC_IMAGE_BUILD=1 \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_MAC_DEFERRED_STEPS="$sandbox/deferred-steps" \
  source "$hardware_all"
unset OMARCHY_MAC_TARGET OMARCHY_MAC_IMAGE_BUILD OMARCHY_MAC_DEFERRED_STEPS
[[ ! -s $test_tmp/run-logged ]] || fail "image-build hardware setup invoked run_logged" "$(cat "$test_tmp/run-logged")"
[[ -f $sandbox/deferred-steps ]] || fail "image-build hardware setup wrote deferred-steps"
[[ $(stat -c '%a' "$sandbox/deferred-steps") == 644 ]] ||
  fail "deferred-steps is created 0644" "$(stat -c '%a' "$sandbox/deferred-steps")"
diff -u <(expected_steps) "$sandbox/deferred-steps" ||
  fail "deferred-steps lists exactly the hardware/all.sh scripts"
while IFS= read -r apple; do
  grep -Fxq "install/hardware/apple/$(basename "$apple")" "$sandbox/deferred-steps" ||
    fail "deferred-steps includes $apple"
done < <(printf '%s\n' "$ROOT"/install/hardware/apple/*.sh)
pass "hardware/all.sh defers every hardware step during an image build"

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

# --- omarchy-mac-run-deferred-steps runs each line once and clears the list ---

omarchy="$test_tmp/omarchy"
first_boot="$test_tmp/var/lib/omarchy/mac-first-boot"
log_dir="$test_tmp/var/log/omarchy"
mkdir -p "$omarchy/install/hardware/apple" "$omarchy/install/helpers" "$first_boot" "$log_dir" "$test_tmp/bin"
cp "$ROOT/install/helpers/logging.sh" "$omarchy/install/helpers/logging.sh"
cp "$helper" "$omarchy/install/helpers/mac-image-build.sh"
cat >"$omarchy/install/hardware/apple/fix-asahi-hid-race.sh" <<'EOF'
printf 'hid target=%s image=%s\n' "${OMARCHY_MAC_TARGET-unset}" "${OMARCHY_MAC_IMAGE_BUILD-unset}" >>"$MAC_IMAGE_BUILD_RAN"
EOF
cat >"$omarchy/install/hardware/apple/fix-asahi-btrfs-race.sh" <<'EOF'
printf 'btrfs\n' >>"$MAC_IMAGE_BUILD_RAN"
EOF
cat >"$omarchy/install/hardware/apple/fix-speaker-pop.sh" <<'EOF'
printf 'speaker\n' >>"$MAC_IMAGE_BUILD_RAN"
EOF
printf '%s\n' \
  install/hardware/apple/fix-asahi-hid-race.sh \
  install/hardware/apple/fix-asahi-btrfs-race.sh \
  install/hardware/apple/fix-speaker-pop.sh >"$first_boot/deferred-steps"
chmod 0644 "$first_boot/deferred-steps"
: >"$test_tmp/ran"
: >"$test_tmp/mkinitcpio.log"

cat >"$test_tmp/bin/true-root" <<'EOF'
#!/bin/bash
exec "$@"
EOF
cat >"$test_tmp/bin/mkinitcpio" <<'EOF'
#!/bin/bash
printf 'mkinitcpio %s\n' "$*" >>"$MAC_IMAGE_BUILD_MKINITCPIO"
EOF
chmod +x "$test_tmp/bin/true-root" "$test_tmp/bin/mkinitcpio"

# Drop the root boundary the same way the fresh-installer suite does.
runnable_runner="$test_tmp/omarchy-mac-run-deferred-steps"
sed -e 's@^(( EUID == 0 )) || fail .*@true # test-only root boundary@' "$runner" >"$runnable_runner"
chmod +x "$runnable_runner"

MAC_IMAGE_BUILD_RAN="$test_tmp/ran" \
  MAC_IMAGE_BUILD_MKINITCPIO="$test_tmp/mkinitcpio.log" \
  OMARCHY_PATH="$omarchy" \
  OMARCHY_MAC_DEFERRED_STEPS="$first_boot/deferred-steps" \
  OMARCHY_MAC_FIRST_BOOT_LOG="$log_dir/mac-first-boot.log" \
  OMARCHY_MAC_IMAGE_BUILD=1 \
  OMARCHY_MAC_TARGET=generic-apple-silicon \
  PATH="$test_tmp/bin:$PATH" \
  bash "$runnable_runner"
[[ $(cat "$test_tmp/ran") == $'hid target=unset image=unset\nbtrfs\nspeaker' ]] ||
  fail "deferred steps ran in order with the installer's live-machine environment" "$(cat "$test_tmp/ran")"
[[ ! -s $first_boot/deferred-steps ]] || fail "successful deferred steps are removed from the list" "$(cat "$first_boot/deferred-steps")"
[[ -f $first_boot/deferred-steps ]] || fail "the deferred-steps file remains after it is cleared"
grep -Fq 'Completed install/hardware/apple/fix-asahi-hid-race.sh' "$log_dir/mac-first-boot.log" ||
  fail "first-boot log records completed steps" "$(cat "$log_dir/mac-first-boot.log")"
[[ $(cat "$test_tmp/mkinitcpio.log") == $'mkinitcpio -P' ]] ||
  fail "HID and btrfs leaves rebuild the initramfs once" "$(cat "$test_tmp/mkinitcpio.log")"
[[ ! -e $first_boot/rebuild-initramfs ]] || fail "a successful initramfs rebuild clears the marker"
grep -Fq 'Rebuilt the initramfs' "$log_dir/mac-first-boot.log" ||
  fail "first-boot log records the initramfs rebuild" "$(cat "$log_dir/mac-first-boot.log")"
: >"$test_tmp/ran"
: >"$test_tmp/mkinitcpio.log"
MAC_IMAGE_BUILD_RAN="$test_tmp/ran" \
  MAC_IMAGE_BUILD_MKINITCPIO="$test_tmp/mkinitcpio.log" \
  OMARCHY_PATH="$omarchy" \
  OMARCHY_MAC_DEFERRED_STEPS="$first_boot/deferred-steps" \
  OMARCHY_MAC_FIRST_BOOT_LOG="$log_dir/mac-first-boot.log" \
  PATH="$test_tmp/bin:$PATH" \
  bash "$runnable_runner"
[[ ! -s $test_tmp/ran ]] || fail "a second run does not repeat cleared steps" "$(cat "$test_tmp/ran")"
[[ ! -s $test_tmp/mkinitcpio.log ]] || fail "a second run does not rebuild the initramfs again" "$(cat "$test_tmp/mkinitcpio.log")"
pass "omarchy-mac-run-deferred-steps runs remaining steps once and clears them"

printf '%s\n' install/hardware/apple/fix-asahi-hid-race.sh install/hardware/apple/broken.sh >"$first_boot/deferred-steps"
cat >"$omarchy/install/hardware/apple/broken.sh" <<'EOF'
false
EOF
: >"$test_tmp/ran"
: >"$test_tmp/mkinitcpio.log"
status=0
MAC_IMAGE_BUILD_RAN="$test_tmp/ran" \
  MAC_IMAGE_BUILD_MKINITCPIO="$test_tmp/mkinitcpio.log" \
  OMARCHY_PATH="$omarchy" \
  OMARCHY_MAC_DEFERRED_STEPS="$first_boot/deferred-steps" \
  OMARCHY_MAC_FIRST_BOOT_LOG="$log_dir/mac-first-boot.log" \
  PATH="$test_tmp/bin:$PATH" \
  bash "$runnable_runner" >"$test_tmp/broken.out" 2>"$test_tmp/broken.err" || status=$?
(( status != 0 )) || fail "a failing deferred step fails the runner"
grep -Fq 'Deferred step failed: install/hardware/apple/broken.sh' "$test_tmp/broken.err" ||
  fail "a failing deferred step is reported" "$(cat "$test_tmp/broken.err")"
[[ $(cat "$test_tmp/ran") == $'hid target=unset image=unset' ]] ||
  fail "steps before a failure still ran" "$(cat "$test_tmp/ran")"
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

# --- Fake chroot: the fresh installer with OMARCHY_MAC_IMAGE_BUILD=1 ----------

sandbox="$test_tmp/root"
stub_bin="$test_tmp/bin"
bundle="$test_tmp/bundle"
calls="$test_tmp/calls"
mkdir -p "$stub_bin" "$bundle" "$test_tmp/tmp"
rm -f "$stub_bin/true-root"

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

for logged in gpasswd usermod update-m1n1 omarchy-apply-system omarchy-apple-silicon-boot-check; do
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
exit 3
EOF
chmod +x "$runtime/usr/bin"/*
bsdtar -cf "$bundle/omarchy-dev-4.0.3-1-aarch64.pkg.tar.zst" -C "$runtime" usr
mkdir -p "$test_tmp/settings/usr/share/omarchy-settings"
bsdtar -cf "$bundle/omarchy-settings-dev-4.0.3-1-aarch64.pkg.tar.zst" -C "$test_tmp/settings" usr
for package in omarchy-keyring omarchy-nvim quickshell-git ttf-jetbrains-mono-nerd-basic; do
  : >"$bundle/$package-1-1-any.pkg.tar.zst"
done

builder_grub=$'# written by the image builder\nlinux /vmlinuz-KERNEL\ninitrd /initramfs-KERNEL.img'

reset_sandbox() {
  rm -rf "$sandbox"
  mkdir -p "$sandbox"/{boot/grub,etc/pacman.d,etc/NetworkManager,run/lock,sys/module/zswap/parameters,home,dev} \
    "$sandbox/usr/share/omarchy/install/hardware" "$sandbox/usr/share/omarchy/install/helpers" \
    "$sandbox/usr/lib/modules/6.99.0-asahi" "$sandbox/var/lib"
  echo "4.0.3" >"$sandbox/usr/share/omarchy/version"
  echo "kernel image" >"$sandbox/usr/lib/modules/6.99.0-asahi/vmlinuz"
  cp "$sandbox/usr/lib/modules/6.99.0-asahi/vmlinuz" "$sandbox/boot/vmlinuz-linux-asahi"
  printf '%s\n' "${builder_grub//KERNEL/linux-asahi}" >"$sandbox/boot/grub/grub.cfg"
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
  echo Y >"$sandbox/sys/module/zswap/parameters/enabled"
  printf '%s\n' base grub jq networkmanager iwd linux-asahi linux-asahi-headers m1n1 >"$sandbox/installed"
  printf 'root:x:0:0::/root:/bin/bash\nalarm:x:1000:1000::/home/alarm:/bin/bash\n' >"$sandbox/passwd"
  cp "$helper" "$sandbox/usr/share/omarchy/install/helpers/mac-image-build.sh"
  cp "$hardware_all" "$sandbox/usr/share/omarchy/install/hardware/all.sh"
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
    FRESH_TEST_KERNEL=linux-asahi \
    FRESH_TEST_KERNEL_VERSION=6.99.0-asahi \
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
status=0
run_installer image OMARCHY_MAC_IMAGE_BUILD=1 --deferred-user || status=$?
[[ $status == 0 ]] || fail "an image-build deferred install completes without device-tree, swap or zswap" "$(cat "$test_tmp/image.out" "$test_tmp/image.err")"
grep -Fq 'omarchy-apply-system --defer-provisioning --first-install' "$calls" ||
  fail "an image build still runs deferred-user system setup" "$(cat "$calls")"
! grep -Eq '^(useradd|passwd|runuser)' "$calls" || fail "an image build creates no account" "$(cat "$calls")"
deferred="$sandbox/var/lib/omarchy/mac-first-boot/deferred-steps"
[[ -f $deferred ]] || fail "the installer wrote deferred-steps"
[[ $(stat -c '%a' "$deferred") == 644 ]] || fail "the installer creates deferred-steps 0644"
diff -u <(expected_steps) "$deferred" || fail "the installer deferred exactly the hardware steps"
grep -Fq 'Fresh Omarchy 4 installation complete' "$test_tmp/image.out" || fail "an image build reports completion"
! grep -Fq 'Reboot' "$test_tmp/image.out" || fail "an image build gives no reboot instruction"
pass "the fresh installer records hardware steps and skips live-machine probes"
