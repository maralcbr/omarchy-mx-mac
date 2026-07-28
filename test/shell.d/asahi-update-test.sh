#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

keyring="$ROOT/bin/omarchy-update-keyring"
system_packages="$ROOT/bin/omarchy-update-system-pkgs"
conflict_handler="$ROOT/bin/omarchy-update-system-pkgs-when-conflicted"
aur_packages="$ROOT/bin/omarchy-update-aur-pkgs"

grep -Fq 'platform_keyring=archlinuxarm-keyring' "$keyring" || fail "Apple Silicon updates use the Arch Linux ARM keyring"
grep -Fq 'omarchy-update-system-pkgs-when-conflicted' "$system_packages" || fail "system updates delegate file conflicts to the recovery helper"
grep -Fq 'if omarchy-hw-apple-silicon; then' "$conflict_handler" || fail "system updates detect Apple Silicon before resolving file conflicts"
grep -Fq '/boot|/boot/*|/etc/default/grub|' "$conflict_handler" || fail "system updates protect Asahi boot paths from conflict recovery"
grep -Fq 'omarchy-dev,omarchy-keyring,omarchy-nvim,omarchy-settings-dev,quickshell-git,ttf-jetbrains-mono-nerd-basic' "$aur_packages" || fail "AUR updates preserve the validated Asahi bundle"
pass "Apple Silicon updates preserve platform packages and configuration"
