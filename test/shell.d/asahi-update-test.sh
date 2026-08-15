#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

keyring="$ROOT/bin/omarchy-update-keyring"
system_packages="$ROOT/bin/omarchy-update-system-pkgs"
conflict_handler="$ROOT/bin/omarchy-update-system-pkgs-when-conflicted"
aur_packages="$ROOT/bin/omarchy-update-aur-pkgs"
bundle_update="$ROOT/bin/omarchy-update-asahi-bundle"
update="$ROOT/bin/omarchy-update"

grep -Fq 'platform_keyring=archlinuxarm-keyring' "$keyring" || fail "Apple Silicon updates use the Arch Linux ARM keyring"
grep -Fq 'GNUPGHOME=/etc/pacman.d/gnupg gpg' "$keyring" || fail "Apple Silicon key checks do not require another sudo invocation"
grep -Fq 'omarchy-update-system-pkgs-when-conflicted' "$system_packages" || fail "system updates delegate file conflicts to the recovery helper"
grep -Fq 'if omarchy-hw-apple-silicon; then' "$conflict_handler" || fail "system updates detect Apple Silicon before resolving file conflicts"
grep -Fq '/boot|/boot/*|/etc/default/grub|' "$conflict_handler" || fail "system updates protect Asahi boot paths from conflict recovery"
grep -Fq 'omarchy-dev,omarchy-keyring,omarchy-nvim,omarchy-settings-dev,quickshell-git,ttf-jetbrains-mono-nerd-basic' "$aur_packages" || fail "AUR updates preserve the validated Asahi bundle"
grep -Fq 'omarchy-keyring,omarchy-settings-dev,omarchy-dev,omarchy-nvim,quickshell-git,ttf-jetbrains-mono-nerd-basic' "$system_packages" || fail "pacman updates exclude the complete Asahi bundle"
grep -Fq 'omarchy-update-asahi-bundle --yes' "$update" || fail "normal updates install the dedicated Asahi bundle"
grep -Fq 'asahi-quattro-release.pending' "$update" || fail "normal updates commit bundle state only after migrations and hooks"
grep -Fq 'bundle_status == 3' "$update" || fail "bundle transport outages do not block platform package updates"
grep -Fq 'pacman -U --noconfirm -- "${archives[@]}"' "$bundle_update" || fail "Asahi bundle installs in one exact transaction"
grep -Fq "grep -q '^apple,'" "$bundle_update" || fail "Asahi bundle updater requires an Apple Silicon device tree"
grep -Fq 'refusing signed release rollback' "$bundle_update" || fail "Asahi bundle updater has an anti-rollback gate"
grep -Fq '$2 == "VALIDSIG" && ($3 == key || $NF == key)' "$bundle_update" || fail "Asahi metadata and packages require the installed Omarchy signing key"
pass "Apple Silicon updates preserve platform packages and configuration"
