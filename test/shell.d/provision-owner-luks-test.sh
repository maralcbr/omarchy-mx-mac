#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

stub_bin="$tmp/bin"
root="$tmp/root"
calls="$tmp/calls"
slots="$tmp/slots"
prov="$tmp/provisioning"
boot_key="$tmp/boot/omarchy/luks-key"
encrypt_state="$tmp/boot/omarchy/encrypt.state"
grub_default="$tmp/default/grub"
device="$tmp/luks-device"
mkdir -p "$stub_bin" "$prov" "$tmp/boot/omarchy" "$tmp/default" "$root"
: >"$calls"
: >"$device"

printf 'throwaway-install-key\n' >"$prov/luks-key"
chmod 600 "$prov/luks-key"
printf 'throwaway-install-key\n' >"$boot_key"
chmod 600 "$boot_key"
# The files are binary-safe passphrases without a newline in production; keep
# the same bytes the stub will compare against.
printf 'throwaway-install-key' >"$prov/luks-key"
printf 'throwaway-install-key' >"$boot_key"
cat >"$encrypt_state" <<'EOF'
format=1
phase=encrypted
partition=PART-UUID-1
luks_uuid=abcd-ef
EOF

cat >"$grub_default" <<'EOF'
GRUB_CMDLINE_LINUX="rd.luks.name=abcd-ef=root rd.luks.key=abcd-ef=/omarchy/luks-key:UUID=4F4D-5801 root=/dev/mapper/root"
EOF

printf '0 throwaway-install-key\n' >"$slots"

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/update-grub" <<SH
#!/bin/bash
printf 'update-grub %s\n' "\$*" >>"$calls"
exit 0
SH

cat >"$stub_bin/mkinitcpio" <<SH
#!/bin/bash
printf 'mkinitcpio %s\n' "\$*" >>"$calls"
exit 0
SH

cat >"$stub_bin/stty" <<'SH'
#!/bin/bash
echo "24 80"
SH

cat >"$stub_bin/gum" <<SH
#!/bin/bash
printf 'gum %s\n' "\$*" >>"$calls"
exit 0
SH

cat >"$stub_bin/cryptsetup" <<SH
#!/bin/bash
printf 'cryptsetup %s\n' "\$*" >>"$calls"
slots_file="$slots"
read_key() {
  local path=\$1
  [[ -n \$path && -e \$path ]] || return 1
  cat "\$path"
}
slot_for() {
  local material=\$1 line slot rest
  while read -r slot rest; do
    [[ \$rest == "\$material" ]] && { printf '%s' "\$slot"; return 0; }
  done <"\$slots_file"
  return 1
}
add_slot() {
  local material=\$1 next
  next=\$(awk '{s=\$1} END {print s+1}' "\$slots_file")
  printf '%s %s\n' "\$next" "\$material" >>"\$slots_file"
}
case "\$1" in
  open)
    keyfile=""
    verbose=0
    while ((\$#)); do
      case "\$1" in
        --verbose) verbose=1 ;;
        --key-file) keyfile=\$2; shift ;;
      esac
      shift
    done
    material=\$(read_key "\$keyfile") || exit 1
    slot=\$(slot_for "\$material") || exit 1
    (( verbose )) && echo "Key slot \$slot unlocked" >&2
    exit 0
    ;;
  luksAddKey)
    keyfile=""
    device=""
    newfile=""
    shift
    while ((\$#)); do
      case "\$1" in
        --key-file) keyfile=\$2; shift 2 ;;
        --*) shift ;;
        *)
          if [[ -z \$device ]]; then
            device=\$1
          else
            newfile=\$1
          fi
          shift
          ;;
      esac
    done
    material=\$(read_key "\$keyfile") || exit 1
    slot_for "\$material" >/dev/null || exit 1
    new=\$(read_key "\$newfile") || exit 1
    add_slot "\$new"
    exit 0
    ;;
  luksDump)
    awk '{ printf "  %s: luks2\\n", \$1 }' "\$slots_file"
    exit 0
    ;;
  luksUUID)
    echo abcd-ef
    exit 0
    ;;
  luksKillSlot)
    kill_slot=""
    while ((\$#)); do
      [[ \$1 =~ ^[0-9]+$ ]] && kill_slot=\$1
      shift
    done
    [[ -n \$kill_slot ]] || exit 1
    awk -v s="\$kill_slot" '\$1 != s { print }' "\$slots_file" >"\$slots_file.new"
    mv "\$slots_file.new" "\$slots_file"
    exit 0
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$stub_bin"/*

omarchy="$tmp/omarchy"
mkdir -p "$omarchy/install/provisioning"
printf 'OMARCHY\n' >"$omarchy/logo.txt"
: >"$omarchy/install/provisioning/setup-form.sh"

export PATH="$stub_bin:$PATH"
export OMARCHY_PATH="$omarchy"
export OMARCHY_PROVISIONING_DIR="$prov"
export OMARCHY_PROVISION_OWNER_LOG="$tmp/provision.log"
export OMARCHY_BOOT_LUKS_KEY="$boot_key"
export OMARCHY_ENCRYPT_STATE="$encrypt_state"
export OMARCHY_GRUB_DEFAULT="$grub_default"
export OMARCHY_LUKS_DEVICE="$device"
export OMARCHY_PROVISION_OWNER_SOURCE=1
export COLUMNS=80
: >"$OMARCHY_PROVISION_OWNER_LOG"

# shellcheck disable=SC1091
source "$ROOT/bin/omarchy-provision-owner"
export PATH="$stub_bin:$PATH"

password="owner-secret"
recovery_key=$(generate_recovery_passphrase)
[[ $recovery_key =~ ^([A-Z2-7]{4}-){11}[A-Z2-7]{4}$ ]] ||
  fail "recovery key is 12 base32 groups of 4" "$recovery_key"

rekey_luks

grep -F 'cryptsetup luksAddKey' "$calls" >/dev/null || fail "re-key adds the owner's key"
(( $(grep -cF 'cryptsetup luksAddKey' "$calls") == 2 )) ||
  fail "re-key adds the owner key and the recovery keyslot" "$(cat "$calls")"
grep -F 'cryptsetup luksKillSlot' "$calls" >/dev/null || fail "re-key retires the throwaway slot"
grep -Fx 'update-grub ' "$calls" >/dev/null || fail "re-key regenerates grub.cfg with update-grub"
grep -F 'mkinitcpio -P' "$calls" >/dev/null || fail "re-key rebuilds the initramfs" "$(cat "$calls")"

[[ ! -e $prov/luks-key ]] || fail "provisioning luks-key is shredded"
[[ ! -e $boot_key ]] || fail "Boot-partition luks-key is shredded"
! grep -q 'rd.luks.key=' "$grub_default" ||
  fail "rd.luks.key= is dropped from GRUB_CMDLINE_LINUX" "$(cat "$grub_default")"
grep -q 'rd.luks.name=' "$grub_default" || fail "rd.luks.name= is kept"
grep -q 'root=/dev/mapper/root' "$grub_default" || fail "root=/dev/mapper/root is kept"

grep -Fxq 'format=1' "$encrypt_state" || fail "encrypt.state keeps format=1" "$(cat "$encrypt_state")"
grep -Fxq 'phase=finished' "$encrypt_state" || fail "encrypt.state is phase=finished" "$(cat "$encrypt_state")"
grep -Fxq 'partition=PART-UUID-1' "$encrypt_state" || fail "encrypt.state keeps partition=" "$(cat "$encrypt_state")"
grep -Fxq 'luks_uuid=abcd-ef' "$encrypt_state" || fail "encrypt.state keeps luks_uuid=" "$(cat "$encrypt_state")"

! grep -Fq "$recovery_key" "$OMARCHY_PROVISION_OWNER_LOG" ||
  fail "the recovery key is never written to the provision log"
! grep -Fq "$recovery_key" "$grub_default" || fail "the recovery key is not stored in GRUB config"
[[ ! -e $prov/recovery-key && ! -e $tmp/boot/omarchy/recovery-key ]] ||
  fail "the recovery key is never written to a keyfile"

: >"$calls"
printf 'nope\n%s\n' "$RECOVERY_ACK_PHRASE" >"$tmp/gum-input"
cat >"$stub_bin/gum" <<SH
#!/bin/bash
printf 'gum %s\n' "\$*" >>"$calls"
if [[ \$1 == input ]]; then
  IFS= read -r line <"$tmp/gum-input" || exit 1
  tail -n +2 "$tmp/gum-input" >"$tmp/gum-input.new"
  mv "$tmp/gum-input.new" "$tmp/gum-input"
  printf '%s\n' "\$line"
fi
exit 0
SH
chmod +x "$stub_bin/gum"
show_recovery_key "$recovery_key"
grep -F "$recovery_key" "$calls" >/dev/null || fail "the recovery key is shown once"
grep -F "$RECOVERY_ACK_PHRASE" "$calls" >/dev/null ||
  fail "the owner types the acknowledgement phrase"
! grep -F 'Show it again' "$calls" >/dev/null || fail "there is no re-show path"
! grep -F 'gum confirm' "$calls" >/dev/null || fail "acknowledgement is typed, not a confirm"
(( $(grep -cF "$recovery_key" "$calls") == 1 )) ||
  fail "the recovery key is shown once" "$(cat "$calls")"
(( $(grep -c '^gum input' "$calls") == 2 )) ||
  fail "a wrong phrase is rejected until the owner types the acknowledgement" "$(cat "$calls")"
! grep -Fq "$recovery_key" "$OMARCHY_PROVISION_OWNER_LOG" ||
  fail "the recovery key is never written to the provision log after display"

! grep -Fq 'limine-update' "$calls" || fail "Apple re-key does not call limine-update"
[[ ! -e $tmp/omarchy/install.conf && ! -e /boot/efi/omarchy/install.conf ]] || true
pass "Apple LUKS re-key adds a recovery keyslot, shreds both keyfiles, and drops rd.luks.key="
