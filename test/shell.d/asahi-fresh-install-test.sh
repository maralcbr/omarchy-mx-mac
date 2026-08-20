#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

installer="$ROOT/bin/omarchy-install-asahi-fresh"
wrapper="$ROOT/install-omarchy-mx-mac"

bash -n "$installer" "$wrapper"
"$installer" --help 2>&1 | grep -Fq -- '--asahi-packages DIR'
pass "fresh Asahi installer exposes the verified bundle entrypoint"

grep -Fq 'omarchy-base-asahi.packages' "$installer" || fail "fresh installer reads the Asahi package closure"
grep -Fq 'pacman -Syu --needed --noconfirm' "$installer" || fail "fresh installer resolves the runtime package transaction"
grep -Fq -- '--ignore linux-asahi,linux-asahi-headers,m1n1' "$installer" || fail "fresh installer excludes protected Asahi boot packages from the system upgrade"
grep -Fq '[[ $package == "linux-asahi" || $package == "linux-asahi-headers" || $package == "m1n1" ]]' "$installer" || fail "fresh installer omits protected Asahi boot packages from explicit targets"
grep -Fq 'pacman -U --needed --noconfirm "${archives[@]}"' "$installer" || fail "fresh installer uses one exact six-package transaction"
grep -Fq 'makepkg --syncdeps --noconfirm' "$installer" || fail "fresh installer builds missing packages from pinned sources"
grep -Fq 'env HOME="$package_repo"' "$installer" || fail "fresh source builds use a build-owned home"
grep -Fq 'build_user=omarchy-fresh-build' "$installer" || fail "fresh installer isolates source builds from the target user"
grep -Fq '$build_user ALL=(root) NOPASSWD: /usr/bin/pacman' "$installer" || fail "fresh build pacman grant is limited to the isolated account"
grep -Fq 'userdel "$build_user"' "$installer" || fail "fresh installer removes its isolated build account"
if grep -Fq '$target_user ALL=(root) NOPASSWD: /usr/bin/pacman' "$installer"; then
  fail "fresh installer must not grant package installation to the target user"
fi
pass "fresh Asahi installer installs the runtime closure and exact release bundle"

build_user_line=$(grep -n -m1 'useradd --system --user-group' "$installer" | cut -d: -f1)
build_trap_line=$(grep -n -m1 'trap cleanup_build_user EXIT' "$installer" | cut -d: -f1)
build_created_line=$(grep -n -m1 'build_account_created=1' "$installer" | cut -d: -f1)
build_dir_line=$(grep -n -m1 'install -d -m 0700 -o "$build_user"' "$installer" | cut -d: -f1)
(( build_trap_line < build_user_line && build_user_line < build_created_line && build_created_line < build_dir_line )) || fail "fresh installer only cleans a build account created by the current process"
grep -Fq 'build_comment == "$owner_token"' "$installer" || fail "fresh installer only reclaims its token-bound build account"
grep -Fq '$(<"$build_sudoers") == "$expected_build_sudo"' "$installer" || fail "fresh installer only reclaims its token-bound sudo rule"

runtime_line=$(grep -n -m1 'pacman -Syu --needed --noconfirm' "$installer" | cut -d: -f1)
account_collision_line=$(grep -Fn -m1 'fail "The package build account already exists"' "$installer" | cut -d: -f1)
(( account_collision_line < runtime_line )) || fail "fresh installer rejects unrelated build accounts before package mutations"
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
grep -Fq 'OMARCHY_SETUP_CONTEXT=fresh-install' "$installer" || fail "fresh installer does not select the ISO payload context"
grep -Fq 'package_source_commit=$OMARCHY_ASAHI_PACKAGE_SOURCE' "$installer" || fail "fresh installer binds resume state to the package source"
grep -Fq '/var/lib/sddm/state.conf' "$installer" || fail "fresh installer seeds the SDDM last-user state"
grep -Fq 'Session=omarchy.desktop' "$installer" || fail "fresh installer records the Omarchy session as last"
pass "fresh installer runs the Quattro system and user finalizers"

grep -Fq '/boot/vmlinuz-linux-asahi' "$installer" || fail "fresh installer protects the Asahi kernel"
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
