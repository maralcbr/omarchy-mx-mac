#!/bin/bash
#
# On Apple Silicon the Omarchy release key must already be trusted by
# /etc/pacman.d/gnupg. A Mac image builds that keyring on first boot from the
# ARM keyrings, so the key omarchy-keyring ships is present on disk but not
# populated; the updater populates it from that package and never from a
# keyserver. The real omarchy-update-keyring runs; gpg, pacman-key, sudo,
# pacman and the platform probes are stubbed.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

keyring="$ROOT/bin/omarchy-update-keyring"
trusted_key=40DFB630FF42BCFFB047046CF0134EE680CAC571

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"
export CALL_LOG="$scratch/calls"
export TRUST_FILE="$scratch/trusted"
export PATH="$scratch/bin:$PATH"

printf '#!/bin/bash\nexit 0\n' >"$scratch/bin/omarchy-hw-apple-silicon"
cat >"$scratch/bin/omarchy-pkg-missing" <<'STUB'
#!/bin/bash
[[ ${KEYRING_INSTALLED:-1} == 1 ]] && exit 1
exit 0
STUB
cat >"$scratch/bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
# TRUST_FILE holds the fingerprints /etc/pacman.d/gnupg knows.
cat >"$scratch/bin/gpg" <<'STUB'
#!/bin/bash
key=${*: -1}
[[ -f $TRUST_FILE ]] && grep -qx "$key" "$TRUST_FILE" && printf 'fpr:::::::::%s:\n' "$key"
exit 0
STUB
# POPULATE_WORKS=1: import and sign. 0: nothing happens. partial: the key is
# imported (so its fingerprint shows) but the local signing step fails.
cat >"$scratch/bin/pacman-key" <<'STUB'
#!/bin/bash
printf 'pacman-key %s\n' "$*" >>"$CALL_LOG"
if [[ $1 == --populate && $2 == omarchy ]]; then
  case ${POPULATE_WORKS:-1} in
    1) printf '%s\n' 40DFB630FF42BCFFB047046CF0134EE680CAC571 >>"$TRUST_FILE" ;;
    partial) printf '%s\n' 40DFB630FF42BCFFB047046CF0134EE680CAC571 >>"$TRUST_FILE"; exit 1 ;;
  esac
fi
exit 0
STUB
cat >"$scratch/bin/pacman" <<'STUB'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$CALL_LOG"
exit 0
STUB
chmod +x "$scratch/bin"/*

run_keyring() {
  : >"$CALL_LOG"
  bash "$keyring" >"$scratch/out" 2>&1
}

# Key already trusted: nothing to populate.
printf '%s\n' "$trusted_key" >"$TRUST_FILE"
run_keyring || fail "a trusted Omarchy key passes the Apple Silicon check: $(<"$scratch/out")"
! grep -q -- '--populate omarchy' "$CALL_LOG" || fail "a trusted key is not populated again"
grep -q 'pacman -Sy --noconfirm archlinuxarm-keyring' "$CALL_LOG" || fail "the ARM platform keyring is still refreshed"
pass "a trusted Omarchy release key is left alone"

# Fresh image: package installed, key not yet in the pacman keyring.
: >"$TRUST_FILE"
run_keyring || fail "a fresh Mac image populates the shipped Omarchy keyring: $(<"$scratch/out")"
[[ $(grep -c -- '^pacman-key --populate omarchy$' "$CALL_LOG") == 1 ]] ||
  fail "the Omarchy keyring is populated exactly once from omarchy-keyring"
! grep -q -- '--recv-keys' "$CALL_LOG" || fail "Apple Silicon never fetches the key from a keyserver"
grep -qx "$trusted_key" "$TRUST_FILE" || fail "populating omarchy trusts the release key"
pass "a fresh Mac image gets the Omarchy release key from the installed omarchy-keyring"

# The shipped keyring does not carry the key: still a hard failure.
: >"$TRUST_FILE"
if POPULATE_WORKS=0 run_keyring; then
  fail "a keyring that cannot supply the release key must fail"
fi
grep -Fq 'must be installed by the signed Apple Silicon bundle' "$scratch/out" ||
  fail "the failure names the signed bundle"
pass "a missing release key after populate still stops the update"

# Import succeeded but local signing failed: the fingerprint is present, yet
# the key is not trusted, so the populate exit status decides.
: >"$TRUST_FILE"
if POPULATE_WORKS=partial run_keyring; then
  fail "a populate that fails after importing the key must stop the update"
fi
grep -Fq 'pacman-key --populate omarchy failed' "$scratch/out" || fail "a failed populate is reported"
! grep -q 'archlinuxarm-keyring' "$CALL_LOG" || fail "a failed populate stops before the platform keyring refresh"
pass "a populate that imports but cannot sign the key stops the update"

# omarchy-keyring absent: fail without touching pacman-key.
printf '%s\n' "$trusted_key" >"$TRUST_FILE"
if KEYRING_INSTALLED=0 run_keyring; then
  fail "a missing omarchy-keyring package must fail"
fi
! grep -q 'pacman-key' "$CALL_LOG" || fail "a missing package is not populated"
pass "a missing omarchy-keyring package stops the update before any populate"
