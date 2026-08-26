#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1787568759.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_bin="$tmpdir/bin"
calls="$tmpdir/desktop-database-calls"
mkdir -p "$stub_bin"

cat >"$stub_bin/update-desktop-database" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_CALLS"
SH
chmod +x "$stub_bin/update-desktop-database"

legacy_home="$tmpdir/legacy-home"
applications_dir="$legacy_home/.local/share/applications"
mkdir -p "$applications_dir" "$legacy_home/.config/Codex" "$legacy_home/.cache/Codex"
cat >"$applications_dir/ChatGPT.desktop" <<'DESKTOP'
[Desktop Entry]
Name=ChatGPT
Exec=omarchy-launch-webapp https://chatgpt.com/
Type=Application
DESKTOP
touch "$legacy_home/.config/Codex/preferences" "$legacy_home/.cache/Codex/cache-entry"

HOME="$legacy_home" PATH="$stub_bin:$PATH" TEST_CALLS="$calls" \
  bash -euo pipefail "$migration" >/dev/null

[[ ! -e $applications_dir/ChatGPT.desktop ]] || fail "migration removes the legacy ChatGPT web app launcher"
[[ -f $legacy_home/.config/Codex/preferences ]] || fail "migration preserves Codex configuration"
[[ -f $legacy_home/.cache/Codex/cache-entry ]] || fail "migration preserves Codex cache"
[[ $(<"$calls") == "$applications_dir" ]] || fail "migration refreshes the desktop application database"
pass "migration removes only the legacy launcher and preserves Codex state"

HOME="$legacy_home" PATH="$stub_bin:$PATH" TEST_CALLS="$calls" \
  bash -euo pipefail "$migration" >/dev/null
(( $(wc -l <"$calls") == 1 )) || fail "migration is idempotent"
pass "migration is idempotent"

custom_home="$tmpdir/custom-home"
custom_applications_dir="$custom_home/.local/share/applications"
mkdir -p "$custom_applications_dir"
cat >"$custom_applications_dir/ChatGPT.desktop" <<'DESKTOP'
[Desktop Entry]
Name=My ChatGPT launcher
Exec=firefox https://chatgpt.com/
Type=Application
DESKTOP

HOME="$custom_home" PATH="$stub_bin:$PATH" TEST_CALLS="$calls" \
  bash -euo pipefail "$migration" >/dev/null

[[ -f $custom_applications_dir/ChatGPT.desktop ]] || fail "migration preserves a custom launcher with the same filename"
(( $(wc -l <"$calls") == 1 )) || fail "migration does not refresh the database when nothing changed"
pass "migration preserves unrelated custom launchers"
