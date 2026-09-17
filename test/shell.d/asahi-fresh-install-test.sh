#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

installer="$ROOT/bin/omarchy-install-asahi-fresh"
wrapper="$ROOT/install-omarchy-mx-mac"
vm_runner="$ROOT/test/vm/asahi-fresh/run"
vm_installer="$ROOT/test/vm/asahi-fresh/guest/install"
vm_candidate="$ROOT/test/vm/asahi-fresh/guest/candidate-repository"
vm_verify="$ROOT/test/vm/asahi-fresh/guest/verify"
vm_launcher="$ROOT/test/vm/asahi-fresh/container/start-vm"

bash -n "$installer" "$wrapper" "$vm_runner" "$vm_installer" "$vm_candidate" "$vm_verify" "$vm_launcher"
"$installer" --help 2>&1 | grep -Fq -- '--asahi-packages DIR'
pass "fresh Asahi installer exposes the verified bundle entrypoint"

grep -Fq 'omarchy-base-asahi.packages' "$installer" || fail "fresh installer reads the Asahi package closure"
grep -Fq 'pacman -Syu --needed --noconfirm' "$installer" || fail "fresh installer resolves the runtime package transaction"
grep -Fq -- '--ignore "$kernel_package,$kernel_package-headers,m1n1"' "$installer" || fail "fresh installer excludes protected boot packages from the system upgrade"
grep -Fq '$package == "$kernel_package" || $package == "$kernel_package-headers"' "$installer" || fail "fresh installer omits the installed kernel from explicit targets"
grep -Fq '$package == "linux-asahi" || $package == "linux-asahi-headers"' "$installer" || fail "fresh installer omits the Asahi kernel from explicit targets"
grep -Fq '$package == "m1n1"' "$installer" || fail "fresh installer omits m1n1 from explicit targets"
grep -Fq 'pacman -U --needed --noconfirm "${archives[@]}"' "$installer" || fail "fresh installer uses one exact six-package transaction"
if grep -Fq 'makepkg' "$installer"; then
  fail "fresh installer must not compile packages on the target machine"
fi
if grep -Fq 'NOPASSWD: /usr/bin/pacman' "$installer"; then
  fail "fresh installer must not grant passwordless package installation to any account"
fi
if grep -Fq '$target_user ALL=(root) NOPASSWD: /usr/bin/pacman' "$installer"; then
  fail "fresh installer must not grant package installation to the target user"
fi
pass "fresh Asahi installer installs the runtime closure and exact release bundle"

if grep -Fq 'useradd --system' "$installer"; then
  fail "fresh installer must not create a build account"
fi

runtime_line=$(grep -n -m1 'pacman -Syu --needed --noconfirm' "$installer" | cut -d: -f1)
target_collision_line=$(grep -Fn -m1 'fail "User already exists outside this release installation: $target_user"' "$installer" | cut -d: -f1)
(( target_collision_line < runtime_line )) || fail "fresh installer rejects unrelated target users before package mutations"
checkpoint_line=$(grep -n -m1 'mv -T "$checkpoint_tmp" "$state_dir"' "$installer" | cut -d: -f1)
(( checkpoint_line < runtime_line )) || fail "fresh installer checkpoints boot hashes before package mutations"
grep -Fq 'flock -n "$install_lock"' "$installer" || fail "fresh installer serializes concurrent runs"
grep -Fq '$(<"$state_dir/target-user") == "$target_identity"' "$installer" || fail "fresh installer validates the recorded target identity"
grep -Fq 'touch "$state_dir/completing"' "$installer" || fail "fresh installer checkpoints completion cleanup"
grep -Fq 'owner_token=$(od -An -N32 -tx1 /dev/urandom' "$installer" || fail "fresh installer creates a random ownership token"
grep -Fq '.omarchy-fresh-install-owner' "$installer" || fail "fresh installer binds resumed target and cache resources to the checkpoint"
bundle_line=$(grep -n -m1 'pacman -U --needed --noconfirm' "$installer" | cut -d: -f1)
user_line=$(grep -n -m1 'useradd --uid "$target_uid"' "$installer" | cut -d: -f1)
(( runtime_line < bundle_line && bundle_line < user_line )) || fail "settings and runtime packages are installed before user creation"
pass "fresh user receives package-populated skel defaults"

grep -Fq 'omarchy-apply-system --install-user "$target_user" --first-install' "$installer" || fail "fresh installer runs root finalization"
grep -Fq 'omarchy-provision-user --force --first-install' "$installer" || fail "fresh installer runs user finalization"
apply_system_line=$(grep -n -m1 'omarchy-apply-system --install-user' "$installer" | cut -d: -f1)
hid_rebuild_line=$(grep -n -m1 '^mkinitcpio -P$' "$installer" | cut -d: -f1)
provision_user_line=$(grep -n -m1 'omarchy-provision-user --force --first-install' "$installer" | cut -d: -f1)
(( apply_system_line < hid_rebuild_line && hid_rebuild_line < provision_user_line )) || fail "fresh installer rebuilds the initramfs after Apple HID setup"
grep -Fq '/var/lib/omarchy/apple-hid-initramfs-ready' "$installer" || fail "fresh installer records the successful Apple HID rebuild"
grep -Fq 'OMARCHY_SETUP_CONTEXT=fresh-install' "$installer" || fail "fresh installer does not select the ISO payload context"
grep -Fq 'package_source_commit=$OMARCHY_ASAHI_PACKAGE_SOURCE' "$installer" || fail "fresh installer binds resume state to the package source"
grep -Fq '/var/lib/sddm/state.conf' "$installer" || fail "fresh installer seeds the SDDM last-user state"
grep -Fq 'Session=omarchy.desktop' "$installer" || fail "fresh installer records the Omarchy session as last"
pass "fresh installer runs the Quattro system and user finalizers"

grep -Fq 'kernel_package=linux-asahi' "$installer" || fail "fresh installer defaults to the Asahi kernel"
grep -Fq 'asahi_kernel_sha256=$(sha256sum "/boot/vmlinuz-$kernel_package")' "$installer" || fail "fresh installer protects the selected kernel"
grep -Fq '/boot/grub/grub.cfg' "$installer" || fail "fresh installer protects GRUB"
grep -Fq 'sha256sum --check --status <<<"$asahi_kernel_sha256"' "$installer" || fail "fresh installer verifies the Asahi kernel hash"
grep -Fq 'sha256sum --check --status <<<"$grub_sha256"' "$installer" || fail "fresh installer verifies the GRUB hash"
validation_line=$(grep -n 'sha256sum --check --status <<<"$grub_sha256"' "$installer" | tail -1 | cut -d: -f1)
alarm_retirement_line=$(grep -n -m1 'usermod -L alarm' "$installer" | cut -d: -f1)
completion_line=$(grep -n 'rm -rf "$state_dir"' "$installer" | tail -1 | cut -d: -f1)
(( validation_line < completion_line )) || fail "fresh installer retains resume state until final validation passes"
(( validation_line < alarm_retirement_line && alarm_retirement_line < completion_line )) || fail "fresh installer retires the stock administrator only after successful finalization"
resume_check_line=$(grep -n -m1 'changed after the interrupted installation' "$installer" | cut -d: -f1)
runtime_line=$(grep -n -m1 'pacman -Syu --needed --noconfirm' "$installer" | cut -d: -f1)
(( resume_check_line < runtime_line )) || fail "fresh installer validates protected boot files before resuming mutations"
grep -Fq 'asahi-alarm core extra alarm aur' "$installer" || fail "fresh installer requires the Asahi repositories"
grep -Fq 'swapon --show --noheadings' "$installer" || fail "fresh installer rejects swap"
grep -Fq '/sys/module/zswap/parameters/enabled' "$installer" || fail "fresh installer rejects zswap"
pass "fresh installer enforces the Apple Silicon platform boundary"

grep -Fq 'installer_args=(--fresh "${installer_args[@]}")' "$wrapper" || fail "root stable installer selects the fresh path"
if grep -Fq 'v3.8.4' "$installer" "$wrapper"; then
  fail "final fresh installer depends on legacy Omarchy"
fi
pass "stable installer enters Quattro directly without Omarchy 3"

grep -Fq 'stable_version=$(<"$root/version")' "$vm_runner" || fail "VM runner reads the candidate stable version"
grep -Fq 'OMARCHY_VM_STABLE_VERSION="$stable_version"' "$vm_runner" || fail "VM runner passes the candidate stable version"
grep -Fq 'grep -Fxq "version=$OMARCHY_VM_STABLE_VERSION"' "$vm_installer" || fail "VM validates the published stable version without a stale hardcode"
pass "fresh-install VM tracks the candidate stable version"

grep -Fq 'vm_memory_mb=${OMARCHY_VM_MEMORY_MB:-6144}' "$vm_runner" || fail "VM runner keeps the 6 GiB default"
grep -Fq 'docker exec -e OMARCHY_VM_MEMORY_MB="$vm_memory_mb"' "$vm_runner" || fail "VM runner passes the memory override"
grep -Fq 'memory_mb=${OMARCHY_VM_MEMORY_MB:-6144}' "$vm_launcher" || fail "VM launcher accepts the memory override"
grep -Fq -- '-m "$memory_mb"' "$vm_launcher" || fail "QEMU uses the configured guest memory"
pass "fresh-install VM supports constrained hosts"

grep -Fq 'candidate_tag=${OMARCHY_VM_CANDIDATE_TAG:-}' "$vm_runner" || fail "VM runner accepts an exact package candidate tag"
grep -Fq 'candidate_sha256=${OMARCHY_VM_CANDIDATE_SHA256:-}' "$vm_runner" || fail "VM runner accepts an exact candidate descriptor checksum"
grep -Fq 'candidate_fingerprint=${OMARCHY_VM_CANDIDATE_FINGERPRINT:-}' "$vm_runner" || fail "VM runner accepts an exact candidate signing fingerprint"
grep -Fq 'candidate_package_count=${OMARCHY_VM_CANDIDATE_PACKAGE_COUNT:-}' "$vm_runner" || fail "VM runner accepts the exact candidate package count"
grep -Fq 'release_tag=$tag' "$vm_candidate" || fail "VM candidate gate binds the descriptor release tag"
grep -Fq 'valid_fingerprint == "${signing_fingerprint^^}"' "$vm_candidate" || fail "VM candidate gate binds the descriptor signature"
grep -Fq -- '--ignore linux-asahi,linux-asahi-headers,m1n1,grub "${packages[@]}"' "$vm_candidate" || fail "VM candidate gate installs the descriptor packages without upgrading its boot fixture"
grep -Fq 'candidate package version: $package' "$vm_verify" || fail "VM verifies candidate versions after reboot"
pass "fresh-install VM can consume an exact signed package candidate"

grep -Fq '/usr/bin/mkinitcpio -p "$preset"' "$vm_candidate" || fail "VM candidate gate builds every preset with the real mkinitcpio"
grep -Fq 'lsinitcpio "$image"' "$vm_candidate" || fail "VM candidate gate inspects every preset image"
grep -Fq 'usr/lib/omarchy/initcpio/omarchy-vendorfw.sh usr/lib/systemd/system/omarchy-vendorfw.service' "$vm_candidate" ||
  fail "VM candidate gate requires the vendor firmware hook and its initrd unit"
grep -Fq 'usr/lib/systemd/system/initrd.target.wants/omarchy-vendorfw.service; do' "$vm_candidate" ||
  fail "VM candidate gate requires the initrd unit to be wanted"
grep -Fq 'sha256sum /boot/Image /boot/initramfs-linux-vm.img /boot/vmlinuz-linux-asahi /boot/grub/grub.cfg' "$vm_candidate" ||
  fail "VM candidate gate protects the generic VM boot image"
[[ $(sed -n '/^# Pacman succeeds even when its initramfs hook fails/,$p' "$vm_candidate" | grep -c 'sha256sum --check --status "$work/protected-boot.before"') == 1 ]] ||
  fail "VM candidate gate re-checks the protected boot files after building presets"
pass "fresh-install VM builds every initramfs preset right after the candidate transaction"

grep -Fq 'channel_url=${OMARCHY_VM_ASAHI_CHANNEL_URL:-}' "$vm_runner" || fail "VM runner accepts a pinned channel URL"
grep -Fq 'asahi-quattro-channel-[1-9][0-9]*/asahi-quattro-channel$' "$vm_runner" || fail "VM runner accepts only a numbered channel asset"
grep -Fq 'OMARCHY_VM_ASAHI_CHANNEL_URL="$channel_url_quoted" \' "$vm_runner" || fail "VM runner passes the channel URL to verification"
grep -Fq "channel_url_quoted=\$(printf '%q' \"\$channel_url\")" "$vm_runner" ||
  fail "VM runner quotes the channel URL for the guest shell"
grep -Fq 'export OMARCHY_ASAHI_CHANNEL_URL=$OMARCHY_VM_ASAHI_CHANNEL_URL' "$vm_verify" || fail "VM verification hands the channel URL to the updater"
pass "fresh-install VM can pin the signed channel instead of discovering it"

# A run must be pinnable end to end: the pointer the guest reads is the one the
# operator named, in the installation stage and in the updater check afterwards.
grep -Fq 'channel_pointer_url=${OMARCHY_VM_ASAHI_CHANNEL_POINTER_URL:-}' "$vm_runner" ||
  fail "VM runner accepts a pinned channel pointer"
[[ $(grep -c 'OMARCHY_VM_ASAHI_CHANNEL_POINTER_URL="$channel_pointer_url_quoted"' "$vm_runner") == 2 ]] ||
  fail "VM runner forwards the pointer override to installation and verification"
grep -Fq "channel_pointer_url_quoted=\$(printf '%q' \"\$channel_pointer_url\")" "$vm_runner" ||
  fail "VM runner quotes the pointer override for the guest shell"
grep -Fq 'export OMARCHY_ASAHI_CHANNEL_POINTER_URL=$OMARCHY_VM_ASAHI_CHANNEL_POINTER_URL' "$vm_verify" ||
  fail "VM verification hands the pointer override to the updater"
grep -Fq 'pointer_url=${OMARCHY_VM_ASAHI_CHANNEL_POINTER_URL:-https://downloads.aicodelabs.com.au/pointers/asahi-quattro-channel}' "$vm_installer" ||
  fail "VM installation reads the published pointer by default"
installer_pointer_line=$(grep -nF 'downloads.aicodelabs.com.au/pointers/' "$vm_installer" | cut -d: -f1)
installer_api_line=$(grep -nF 'api.github.com' "$vm_installer" | cut -d: -f1)
(( installer_pointer_line < installer_api_line )) || fail "VM installation reads the pointer before the GitHub API"
grep -Fq 'ASAHI_QUATTRO_CHANNEL_TAG="$channel_tag" \' "$vm_installer" ||
  fail "VM installation hands the resolved channel to the installer it verifies with"
pass "fresh-install VM discovers its channel through the pointer and hands it on"

# guest/verify must not learn what to expect from the system it is checking.
grep -Fq 'expected_repository=${OMARCHY_VM_EXPECTED_REPOSITORY:-}' "$vm_verify" ||
  fail "VM verification takes its expected repository from pre-install inputs"
! grep -Fq 'expected_repository=asahi-packages-784daa3' "$vm_verify" ||
  fail "VM verification no longer hard-codes the bootstrap release"
grep -Fq "expected_repository =~ ^asahi-packages-candidate-[0-9a-f]{40}\$" "$vm_verify" ||
  fail "VM verification requires an exact candidate repository tag"
grep -Fq 'C81AC3E2A99556F9B21D5FEA3DD49BC9F8360BDC' "$vm_verify" ||
  fail "VM verification asserts the ARM repository key for a stable snapshot"
grep -Fq "sed -n 's/^[[:space:]]*bootstrap_release_tag=//p'" "$vm_runner" ||
  fail "VM runner reads the bootstrap pin from install/hardware/pacman.sh"
grep -Fq 'OMARCHY_VM_EXPECTED_REPOSITORY="$expected_repository_quoted"' "$vm_runner" ||
  fail "VM runner passes the expected repository to verification"
pass "fresh-install VM checks the install-time pin against the repository's own default"
