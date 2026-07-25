#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

upgrade_to_quattro="$ROOT/bin/omarchy-upgrade-to-quattro"

guard_line=$(grep -n '^if apple_silicon; then$' "$upgrade_to_quattro" | cut -d: -f1)
snapshot_line=$(grep -n '^[[:space:]]*create_pre_upgrade_snapshot$' "$upgrade_to_quattro" | cut -d: -f1)
[[ -n $guard_line && -n $snapshot_line ]] || fail "Apple Silicon mode guard and first mutation call exist"
(( guard_line < snapshot_line )) || fail "Apple Silicon guard runs before the first upgrade mutation"
pass "Omarchy 4 upgrade guards Apple Silicon before mutation"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/apple-bin" "$test_tmp/non-apple-bin"
cat >"$test_tmp/apple-bin/omarchy-hw-apple-silicon" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$test_tmp/non-apple-bin/omarchy-hw-apple-silicon" <<'STUB'
#!/bin/bash
exit 1
STUB
for stub_dir in "$test_tmp/apple-bin" "$test_tmp/non-apple-bin"; do
  cat >"$stub_dir/pacman" <<'STUB'
#!/bin/bash
printf 'pacman called\n' >>"$MUTATION_LOG"
exit 1
STUB
  cat >"$stub_dir/sudo" <<'STUB'
#!/bin/bash
printf 'sudo called\n' >>"$MUTATION_LOG"
exit 1
STUB
  chmod +x "$stub_dir/omarchy-hw-apple-silicon" "$stub_dir/pacman" "$stub_dir/sudo"
done

mutation_log="$test_tmp/mutations.log"
if MUTATION_LOG="$mutation_log" PATH="$test_tmp/apple-bin:$PATH" "$upgrade_to_quattro" --yes 2>"$test_tmp/apple-error"; then
  fail "ordinary Apple Silicon upgrade is rejected"
fi
grep -Fq -- '--asahi-packages DIR' "$test_tmp/apple-error" || fail "ordinary Apple rejection explains local package mode"
[[ ! -e $mutation_log ]] || fail "ordinary Apple rejection happens before pacman or sudo"

if MUTATION_LOG="$mutation_log" PATH="$test_tmp/non-apple-bin:$PATH" "$upgrade_to_quattro" --yes --asahi-packages "$test_tmp/missing" 2>"$test_tmp/non-apple-error"; then
  fail "Asahi package mode is rejected without Apple Silicon detection"
fi
grep -Fq 'accepted only on detected Apple Silicon' "$test_tmp/non-apple-error" || fail "non-Apple rejection identifies detection requirement"
[[ ! -e $mutation_log ]] || fail "non-Apple Asahi rejection happens before pacman or sudo"

if MUTATION_LOG="$mutation_log" PATH="$test_tmp/apple-bin:$PATH" "$upgrade_to_quattro" --yes --asahi-packages "$test_tmp/missing" 2>"$test_tmp/packages-error"; then
  fail "missing Asahi package directory is rejected"
fi
grep -Fq 'is not a readable directory' "$test_tmp/packages-error" || fail "Asahi directory validation reports the failure"
[[ ! -e $mutation_log ]] || fail "Asahi package validation happens before pacman or sudo execution"
pass "Omarchy 4 upgrade gates Asahi mode and validates before mutation"

grep -F '# omarchy:args=' "$upgrade_to_quattro" | grep -Fq '[--asahi-packages DIR]'
grep -Fq -- '--asahi-packages DIR      Apple Silicon only' "$upgrade_to_quattro"
grep -Fq 'omarchy upgrade to quattro --asahi-packages ~/quattro-packages' "$upgrade_to_quattro"
pass "Omarchy 4 upgrade advertises Apple Silicon local-package mode"

grep -Fq 'Expected exactly one local $package_name archive' "$upgrade_to_quattro"
grep -Fq 'pacman -Qp -- "$archive"' "$upgrade_to_quattro"
grep -Fq "grep -Fxq 'arch = aarch64'" "$upgrade_to_quattro"
grep -Fq "grep -Fxq 'arch = any'" "$upgrade_to_quattro"
grep -Fq "'^depend = (limine|snapper)([<>=:]|$)'" "$upgrade_to_quattro"
grep -Fq "'(^|/)etc/mkinitcpio|limine|snapper|usb[-_]autosuspend'" "$upgrade_to_quattro"
grep -Fq "grep -Fq -- '-mac.dev'" "$upgrade_to_quattro"
pass "Omarchy 4 upgrade preflights local package identity, architecture, contents, dependencies, and Mac version"

grep -Fq 'create_asahi_system_backup' "$upgrade_to_quattro"
grep -Fq '/var/lib/omarchy/backups/quattro-$backup_suffix' "$upgrade_to_quattro"
grep -Fq 'mirrorlists=(/etc/pacman.d/*mirrorlist*)' "$upgrade_to_quattro"
grep -Fq '/etc/NetworkManager/conf.d/wifi_backend.conf' "$upgrade_to_quattro"
grep -Fq '/etc/udev/rules.d/99-wifi-powersave.rules' "$upgrade_to_quattro"
grep -Fq '/etc/mkinitcpio.conf.d' "$upgrade_to_quattro"
grep -Fq '/boot/grub/grub.cfg' "$upgrade_to_quattro"
grep -Fq 'pacman -Q | as_root tee "$backup_dir/installed-packages.txt"' "$upgrade_to_quattro"
grep -Fq 'find /boot/efi -xdev -type f -exec sha256sum' "$upgrade_to_quattro"
grep -Fq 'chown -R root:root "$backup_dir"' "$upgrade_to_quattro"
pass "Omarchy 4 upgrade creates a root-owned Apple Silicon safety backup without copying the ESP"

grep -Fq 'as_root pacman -U --needed --noconfirm --ask 4' "$upgrade_to_quattro"
grep -Fq -- "--overwrite '/etc/sudoers.d/omarchy-tzupdate'" "$upgrade_to_quattro"
grep -Fq -- "--overwrite '/usr/lib/systemd/system-sleep/unmount-fuse'" "$upgrade_to_quattro"
grep -Fq -- "--overwrite '/usr/local/share/wayland-sessions/omarchy.desktop'" "$upgrade_to_quattro"
grep -Fq -- "--overwrite '/usr/share/plymouth/themes/omarchy/*'" "$upgrade_to_quattro"
grep -Fq -- "--overwrite '/usr/share/omarchy/*'" "$upgrade_to_quattro"
grep -Fq '"${asahi_package_archives[@]}"' "$upgrade_to_quattro"
grep -Fq '[[ ! -f /usr/lib/libvulkan_asahi.so ]]' "$upgrade_to_quattro"
grep -Fq 'runtime_packages+=(vulkan-asahi)' "$upgrade_to_quattro"
grep -Fq 'pacman -Syu --needed --noconfirm --ask 4 "${runtime_packages[@]}"' "$upgrade_to_quattro"
grep -Fq 'remove_legacy_asahi_udev_rules' "$upgrade_to_quattro"
grep -Fq 'iwd' "$upgrade_to_quattro"
grep -Fq 'udiskie' "$upgrade_to_quattro"
grep -Fq 'expac' "$upgrade_to_quattro"
grep -Fq '(( asahi_mode )) || remove_legacy_limine_configs' "$upgrade_to_quattro"
grep -Fq '(( asahi_mode )) || migrate_1password_beta_package' "$upgrade_to_quattro"
grep -Fq '(( asahi_mode )) || run_post_upgrade_migrations' "$upgrade_to_quattro"
grep -Fq '(( asahi_mode )) || run_post_upgrade_update_steps' "$upgrade_to_quattro"
grep -Fq 'if (( asahi_mode )) && [[ $pkg == wf-recorder ]]' "$upgrade_to_quattro"
pass "Omarchy 4 upgrade uses one local package transaction and excludes unsafe Asahi migrations"

repository_branch=$(awk '
  /^if \(\( asahi_mode \)\); then$/ { capture=1; block=$0 ORS; next }
  capture { block=block $0 ORS }
  capture && /^fi$/ {
    if (block ~ /create_asahi_system_backup/) { printf "%s", block; exit }
    capture=0
    block=""
  }
' "$upgrade_to_quattro")
[[ $repository_branch == *$'create_asahi_system_backup\n  remove_legacy_asahi_udev_rules\nelse\n  create_pre_upgrade_snapshot\n  configure_pacman_channel\n  install_keyrings'* ]] || \
  fail "Asahi migration bypasses snapshots and upstream repository setup"

package_branch=$(awk '
  /^if \(\( asahi_mode \)\); then$/ { capture=1; block=$0 ORS; next }
  capture { block=block $0 ORS }
  capture && /^fi$/ {
    if (block ~ /install_asahi_quattro_packages/) { printf "%s", block; exit }
    capture=0
    block=""
  }
' "$upgrade_to_quattro")
[[ $package_branch == *$'install_asahi_quattro_packages\nelse\n  install_omarchy_quattro_packages\n  install_hardware_transition_packages\n  normalize_limine_config\n  configure_snapper_policy'* ]] || \
  fail "Asahi migration bypasses default-package, hardware, Limine, and Snapper setup"
grep -Fq '[[ $overwrite_path == /etc/mkinitcpio* || $overwrite_path == *usb-autosuspend* ]]' "$upgrade_to_quattro"
grep -Fq 'pacman_args+=(--ignore omarchy-keyring,omarchy-settings-dev,omarchy-dev,quickshell-git,ttf-jetbrains-mono-nerd-basic)' "$upgrade_to_quattro"
pass "Omarchy 4 upgrade preserves Asahi repositories and excludes boot-specific overwrite paths"

pacman_line=$(grep -n '^[[:space:]]*configure_pacman_channel$' "$upgrade_to_quattro" | cut -d: -f1)
[[ -n $snapshot_line && -n $pacman_line ]] || fail "upgrade snapshot and first mutation calls exist"
(( snapshot_line < pacman_line )) || fail "upgrade snapshot runs before pacman configuration"
grep -F 'omarchy-snapshot create || (($? == 127))' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade snapshots the system before mutation"

grep -F 'pacman -Syu --needed' "$upgrade_to_quattro" >/dev/null
grep -F 'omarchy-update-aur-pkgs' "$upgrade_to_quattro" >/dev/null
grep -F 'omarchy-update-available' "$upgrade_to_quattro" >/dev/null
grep -F 'omarchy-update-mise' "$upgrade_to_quattro" >/dev/null
grep -F 'run_final_system_package_upgrade' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade completes package update checks"

grep -F 'run_post_upgrade_migrations' "$upgrade_to_quattro" >/dev/null
grep -F 'omarchy-migrate' "$upgrade_to_quattro" >/dev/null
grep -F 'dust' "$upgrade_to_quattro" >/dev/null
grep -F 'satty' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade applies packaged migrations"

if grep -F 'skip-first-run-update-notification' "$upgrade_to_quattro" >/dev/null; then
  fail "Omarchy 4 upgrade does not use notification-specific first-run state"
fi
pass "Omarchy 4 upgrade completes first-run as one lifecycle"

grep -F '"$root/bin/omarchy-done" mark first-run-user' "$upgrade_to_quattro" >/dev/null
grep -F 'rm -f "$state_dir/first-run-user.done"' "$upgrade_to_quattro" >/dev/null
grep -F '"$root/bin/omarchy-done" mark finalize-user' "$upgrade_to_quattro" >/dev/null
grep -F 'rm -f "$state_dir/finalize-user.done"' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade completes first-run and migrates legacy completion markers"

grep -F 'configure_snapper_policy' "$upgrade_to_quattro" >/dev/null
grep -F '/usr/share/omarchy/install/config/snapper.sh' "$upgrade_to_quattro" >/dev/null
grep -F 'bash -euo pipefail "$snapper_config_script"' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade normalizes Snapper retention"

grep -F 'configure_lock_authentication' "$upgrade_to_quattro" >/dev/null
grep -F 'OMARCHY_INSTALL_USER="$target_user"' "$upgrade_to_quattro" >/dev/null
grep -F '"$setup_lock"' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade configures lock screen authentication for the target user"

grep -F 'OMARCHY_UPGRADE_TO_QUATTRO_LIVE=1' "$upgrade_to_quattro" >/dev/null
grep -F 'systemd-networkd.service' "$upgrade_to_quattro" >/dev/null
grep -F 'systemd-networkd.socket' "$upgrade_to_quattro" >/dev/null
grep -F 'systemd-networkd-resolve-hook.socket' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade retires systemd-networkd for NetworkManager"

grep -F 'omarchy-bar defaults' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade restores service-aware bar defaults"

grep -F 'install_hardware_transition_packages' "$upgrade_to_quattro" >/dev/null
grep -F 'sof-firmware' "$upgrade_to_quattro" >/dev/null
grep -F 'vulkan-intel' "$upgrade_to_quattro" >/dev/null
grep -F 'apply_user_hardware_transition' "$upgrade_to_quattro" >/dev/null
grep -F 'DX13260' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade backfills hardware support from the legacy release"

grep -F 'omarchy-refresh-applications' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade refreshes application launchers"

grep -F '/etc/systemd/system.conf.d/99-omarchy-nofile.conf' "$upgrade_to_quattro" >/dev/null
grep -F '/etc/systemd/user.conf.d/99-omarchy-nofile.conf' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade removes stale nofile drop-ins"
