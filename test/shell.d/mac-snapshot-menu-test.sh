#!/bin/bash
#
# omarchy-mac-snapshot-menu writes the grub-btrfs configuration for an Apple
# Silicon Mac, runs the generator into /boot/grub/grub-btrfs.cfg, and adds
# the submenu include to grub.cfg once. The kernel on /boot is outside every
# snapshot, so snapshots without its modules are hidden from the menu.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

menu="$ROOT/bin/omarchy-mac-snapshot-menu"
grep -Fxq 'grub-btrfs' "$ROOT/install/omarchy-other-asahi.packages" || fail "grub-btrfs is an Apple Silicon default package"
grep -Fq 'sudo omarchy-mac-snapshot-menu refresh || (($? == 127))' "$ROOT/bin/omarchy-snapshot" ||
  fail "omarchy-snapshot create refreshes the GRUB menu on Apple Silicon and tolerates a missing grub-btrfs"
grep -Fq 'omarchy-mac-snapshot-menu refresh' "$ROOT/bin/omarchy-mac-snapshot-restore" &&
  grep -Fq 'omarchy-mac-snapshot-menu refresh' "$ROOT/bin/omarchy-mac-snapshot-restore-finish" ||
  fail "the restore tools refresh the GRUB menu after pruning and after verification"
pass "the snapshot tools refresh the GRUB menu explicitly; no grub-btrfsd"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/etc/default/grub-btrfs" "$tmp/boot/grub" "$tmp/modules/6.16.0-aurora" \
  "$tmp/snapshots/1/snapshot$tmp/modules/6.16.0-aurora" "$tmp/snapshots/2/snapshot$tmp/modules/6.15.0-aurora" \
  "$tmp/snapshots/3/snapshot$tmp/modules/6.16.0-aurora"
export CALL_LOG="$tmp/calls"
export PATH="$tmp/bin:$PATH"
printf 'linux-aurora\n' >"$tmp/modules/6.16.0-aurora/pkgbase"
: >"$tmp/snapshots/1/snapshot$tmp/modules/6.16.0-aurora/modules.dep"
: >"$tmp/snapshots/2/snapshot$tmp/modules/6.15.0-aurora/modules.dep"
# snapshot 3 has the directory but no modules.dep: an interrupted install
for number in 1 2 3; do printf '<snapshot><num>%s</num></snapshot>\n' "$number" >"$tmp/snapshots/$number/info.xml"; done
printf 'menuentry Omarchy {\n}\n' >"$tmp/boot/grub/grub.cfg"

printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/omarchy-hw-apple-silicon"
# The generator stub records that it ran with the config in place and
# writes the menu file, as grub-btrfs does.
cat >"$tmp/generator" <<'STUB'
#!/bin/bash
printf 'generator\n' >>"$CALL_LOG"
cp "$OMARCHY_GRUB_BTRFS_CONFIG" "$CALL_LOG.config"
printf 'submenu Omarchy snapshots {\n}\n' >"$OMARCHY_GRUB_BTRFS_CFG"
STUB
cat >"$tmp/bin/update-grub" <<'STUB'
#!/bin/bash
printf 'update-grub\n' >>"$CALL_LOG"
printf 'menuentry Omarchy {\n}\nsubmenu "Omarchy snapshots" {\n  configfile /grub/grub-btrfs.cfg\n}\n' >"$OMARCHY_GRUB_CFG"
STUB
chmod +x "$tmp/bin"/* "$tmp/generator"

runnable="$tmp/omarchy-mac-snapshot-menu"
sed -e 's@^(( EUID == 0 )) || fail "run as root"$@true # test-only root boundary@' "$menu" >"$runnable"
grep -Fq 'test-only root boundary' "$runnable" || fail "the sandbox copy drops the root boundary"

refresh() {
  : >"$CALL_LOG"
  OMARCHY_GRUB_BTRFS_CONFIG="$tmp/etc/default/grub-btrfs/config" \
  OMARCHY_GRUB_BTRFS_GENERATOR="$tmp/generator" \
  OMARCHY_GRUB_CFG="$tmp/boot/grub/grub.cfg" \
  OMARCHY_GRUB_BTRFS_CFG="$tmp/boot/grub/grub-btrfs.cfg" \
  OMARCHY_SNAPSHOTS_DIR="$tmp/snapshots" \
  OMARCHY_SNAPSHOT_RESTORE_MODULES="$tmp/modules" \
  OMARCHY_UPDATE_GRUB=update-grub \
    bash "$runnable" refresh >"$tmp/out" 2>&1
}

refresh || fail "the refresh runs: $(<"$tmp/out")"
config="$CALL_LOG.config"
grep -Fxq 'GRUB_BTRFS_IGNORE_SPECIFIC_PATH=("@" "@factory" "@/.snapshots/2/snapshot" "@/.snapshots/3/snapshot")' "$config" ||
  fail "snapshots without the /boot kernel's modules are hidden, @ and @factory always: $(grep IGNORE_SPECIFIC "$config")"
grep -Fq '"@omarchy-previous-" "@restore-" "@omarchy-old-"' "$config" || fail "staging and kept roots are hidden by prefix"
grep -Fxq 'GRUB_BTRFS_LIMIT="5"' "$config" && grep -Fxq 'GRUB_BTRFS_SUBMENUNAME="Omarchy snapshots"' "$config" ||
  fail "the menu is limited to five entries under the Omarchy submenu"
grep -Fxq 'GRUB_BTRFS_OVERRIDE_BOOT_PARTITION_DETECTION="true"' "$config" || fail "the separate ext4 /boot is declared"
[[ $(<"$CALL_LOG") == $'generator\nupdate-grub' ]] || fail "the generator runs, then grub.cfg gains the include once: $(<"$CALL_LOG")"
grep -Fq 'configfile /grub/grub-btrfs.cfg' "$tmp/boot/grub/grub.cfg" || fail "grub.cfg carries the submenu include"
grep -Fq '1 snapshot(s) hidden' "$tmp/out" || grep -Fq '2 snapshot(s) hidden' "$tmp/out" || fail "the summary counts hidden snapshots: $(<"$tmp/out")"
pass "a refresh hides incompatible snapshots and adds the submenu to grub.cfg once"

refresh || fail "a second refresh runs"
[[ $(<"$CALL_LOG") == generator ]] || fail "a grub.cfg that already includes the menu is left alone: $(<"$CALL_LOG")"
pass "later refreshes regenerate only grub-btrfs.cfg"

# A new kernel on /boot: the compatible set changes with it.
mkdir -p "$tmp/modules/6.17.0-aurora"; printf 'linux-aurora\n' >"$tmp/modules/6.17.0-aurora/pkgbase"
refresh || fail "a refresh after a kernel change runs"
grep -Fq '"@/.snapshots/1/snapshot"' "$config" || fail "a snapshot without the new kernel's modules is hidden after a kernel change"
pass "a kernel change re-evaluates which snapshots may boot"

# Without grub-btrfs installed the refresh is a no-op that says so with 127.
rm "$tmp/generator"
if refresh; then fail "a missing generator must exit 127"; fi
OMARCHY_GRUB_BTRFS_GENERATOR="$tmp/generator" bash "$runnable" refresh >/dev/null 2>&1 || status=$?
[[ ${status:-0} == 127 ]] || fail "a missing generator exits 127, not $status"
pass "a Mac without grub-btrfs reports 127 so omarchy-snapshot ignores it"
