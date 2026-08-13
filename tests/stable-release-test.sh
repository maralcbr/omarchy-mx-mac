#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state/omarchy/releases" "$tmp/release"

cat >"$tmp/release/omarchy-mx-mac-release" <<'EOF'
format=1
track=stable-mac
sequence=3
version=3.8.5-mac.1
source_tag=v3.8.5-mac.1
source_commit=0123456789abcdef0123456789abcdef01234567
minimum_updater_version=1
EOF
: >"$tmp/release/omarchy-mx-mac-release.sig"
: >"$tmp/keyring.gpg"

cat >"$tmp/bin/curl" <<'EOF'
#!/bin/bash
while (($#)); do
  if [[ $1 == "--output" ]]; then
    output=$2
    shift 2
  else
    url=$1
    shift
  fi
done
cp "${url#file://}" "$output"
EOF
cat >"$tmp/bin/gpgv" <<'EOF'
#!/bin/bash
exit "${GPGV_EXIT:-0}"
EOF
cat >"$tmp/bin/gpg" <<'EOF'
#!/bin/bash
echo 'fpr:::::::::40DFB630FF42BCFFB047046CF0134EE680CAC571:'
EOF
chmod +x "$tmp/bin"/*

run_resolver() {
  PATH="$tmp/bin:/usr/bin" XDG_STATE_HOME="$tmp/state" \
    OMARCHY_RELEASE_KEYRING="$tmp/keyring.gpg" \
    OMARCHY_RELEASE_BASE_URL="file://$tmp/release" \
    "$ROOT/bin/omarchy-stable-release" "$@"
}

[[ $(run_resolver source_tag) == "v3.8.5-mac.1" ]]
[[ $(run_resolver source_commit) == "0123456789abcdef0123456789abcdef01234567" ]]

GPGV_EXIT=1 run_resolver >/dev/null 2>&1 && { echo "not ok - invalid signature accepted"; exit 1; }

sed -i 's/^sequence=3$/sequence=2/' "$tmp/release/omarchy-mx-mac-release"
printf 'format=1\ntrack=stable-mac\nsequence=3\n' >"$tmp/state/omarchy/releases/stable-mac"
run_resolver >/dev/null 2>&1 && { echo "not ok - rollback accepted"; exit 1; }

echo "ok - stable release descriptor verification and anti-rollback"
