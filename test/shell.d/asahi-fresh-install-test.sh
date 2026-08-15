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
grep -Fq 'pacman -U --needed --noconfirm "${archives[@]}"' "$installer" || fail "fresh installer uses one exact six-package transaction"
grep -Fq 'makepkg --syncdeps --noconfirm' "$installer" || fail "fresh installer builds missing packages from pinned sources"
pass "fresh Asahi installer installs the runtime closure and exact release bundle"

runtime_line=$(grep -n -m1 'pacman -Syu --needed --noconfirm' "$installer" | cut -d: -f1)
bundle_line=$(grep -n -m1 'pacman -U --needed --noconfirm' "$installer" | cut -d: -f1)
user_line=$(grep -n 'useradd -m -G wheel' "$installer" | cut -d: -f1)
(( runtime_line < bundle_line && bundle_line < user_line )) || fail "settings and runtime packages are installed before user creation"
pass "fresh user receives package-populated skel defaults"

grep -Fq 'omarchy-apply-system --install-user "$target_user" --first-install' "$installer" || fail "fresh installer runs root finalization"
grep -Fq 'omarchy-provision-user --force --first-install' "$installer" || fail "fresh installer runs user finalization"
grep -Fq 'OMARCHY_SETUP_CONTEXT=fresh-install' "$installer" || fail "fresh installer does not select the ISO payload context"
pass "fresh installer runs the Quattro system and user finalizers"

grep -Fq '/boot/vmlinuz-linux-asahi' "$installer" || fail "fresh installer protects the Asahi kernel"
grep -Fq '/boot/grub/grub.cfg' "$installer" || fail "fresh installer protects GRUB"
grep -Fq 'asahi-alarm core extra alarm aur' "$installer" || fail "fresh installer requires the Asahi repositories"
grep -Fq 'swapon --show --noheadings' "$installer" || fail "fresh installer rejects swap"
grep -Fq '/sys/module/zswap/parameters/enabled' "$installer" || fail "fresh installer rejects zswap"
pass "fresh installer enforces the Apple Silicon platform boundary"

grep -Fq 'installer_args=(--fresh "${installer_args[@]}")' "$wrapper" || fail "root stable installer selects the fresh path"
if grep -Fq 'v3.8.4' "$installer" "$wrapper"; then
  fail "final fresh installer depends on legacy Omarchy"
fi
pass "stable installer enters Quattro directly without Omarchy 3"
