#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

keyring="$ROOT/bin/omarchy-update-keyring"
system_packages="$ROOT/bin/omarchy-update-system-pkgs"
aur_packages="$ROOT/bin/omarchy-update-aur-pkgs"

grep -Fq 'platform_keyring=archlinuxarm-keyring' "$keyring" || fail "Apple Silicon updates use the Arch Linux ARM keyring"
grep -Fq 'omarchy-hw-apple-silicon' "$system_packages" || fail "system updates detect Apple Silicon"
grep -Fq '[[ $path == /etc/mkinitcpio* || $path == *usb-autosuspend* ]]' "$system_packages" || fail "system updates omit Asahi boot overwrite paths"
grep -Fq 'omarchy-dev,omarchy-keyring,omarchy-nvim,omarchy-settings-dev,quickshell-git,ttf-jetbrains-mono-nerd-basic' "$aur_packages" || fail "AUR updates preserve the validated Asahi bundle"
pass "Apple Silicon updates preserve platform packages and configuration"
