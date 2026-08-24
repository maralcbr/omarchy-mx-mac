#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

locale_leaf="$ROOT/install/config/locale.sh"
config_all="$ROOT/install/config/all.sh"
fresh_installer="$ROOT/bin/omarchy-install-asahi-fresh"
migration="$ROOT/migrations/1787491150.sh"
migrate="$ROOT/bin/omarchy-migrate"
vm_verify="$ROOT/test/vm/asahi-fresh/guest/verify"

bash -n "$locale_leaf" "$fresh_installer" "$migration" "$migrate"

! head -1 "$locale_leaf" | grep -q '^#!' || fail "locale setup leaf stays shebang-free like its sourced siblings"
grep -Fq "printf 'LANG=C.UTF-8\\n' >>\"\$locale_conf\"" "$locale_leaf" ||
  fail "locale setup leaf seeds the neutral C.UTF-8 default"
if grep -Eq '^[[:space:]]*localectl' "$locale_leaf"; then
  fail "locale setup leaf avoids localectl so it works from the ISO chroot"
fi
pass "install-time locale setup seeds C.UTF-8 without disturbing regional choices"

apply_locale_leaf() {
  OMARCHY_LOCALE_CONF="$1" bash -euo pipefail -c 'source "$1"' _ "$locale_leaf"
}

locale_conf=$(mktemp)
trap 'rm -f "$locale_conf"' EXIT
printf 'LANG=C\nLC_TIME=de_DE.UTF-8\n# local choice\n' >"$locale_conf"
apply_locale_leaf "$locale_conf"
grep -Fxq 'LANG=C.UTF-8' "$locale_conf" || fail "locale setup replaces a non-UTF-8 LANG"
grep -Fxq 'LC_TIME=de_DE.UTF-8' "$locale_conf" || fail "locale setup preserves LC category choices"
grep -Fxq '# local choice' "$locale_conf" || fail "locale setup preserves comments"

for configured_lang in 'C.UTF-8' 'C.utf8' '"en_US.UTF-8"' '"sr_RS.UTF-8@latin"'; do
  printf 'LANG=%s\nLC_MESSAGES=C\n' "$configured_lang" >"$locale_conf"
  before=$(<"$locale_conf")
  apply_locale_leaf "$locale_conf"
  [[ $(<"$locale_conf") == "$before" ]] || fail "locale setup preserves UTF-8 LANG=$configured_lang"
done
pass "locale setup behavior preserves valid locale.conf syntax and independent settings"

grep -Fq 'run_logged "$OMARCHY_INSTALL/config/locale.sh"' "$config_all" ||
  fail "system config wires the locale setup into every install path"
locale_line=$(grep -n -m1 'config/locale.sh' "$config_all" | cut -d: -f1)
theme_line=$(grep -n -m1 'config/theme-system.sh' "$config_all" | cut -d: -f1)
(( locale_line < theme_line )) || fail "locale setup runs before the themed config steps"
pass "every omarchy-apply-system path applies the UTF-8 locale default"

check_line=$(grep -n -m1 'The system locale is not UTF-8' "$fresh_installer" | cut -d: -f1)
apply_line=$(grep -n -m1 'omarchy-apply-system --install-user "$target_user" --first-install' "$fresh_installer" | cut -d: -f1)
alarm_line=$(grep -n -m1 'usermod -L alarm' "$fresh_installer" | cut -d: -f1)
(( apply_line < check_line && check_line < alarm_line )) ||
  fail "fresh installer validates the UTF-8 locale after system finalization and before retiring the stock administrator"
pass "fresh Asahi install refuses to complete with a non-UTF-8 system locale"

[[ -f $migration ]] || fail "existing installs receive the UTF-8 locale repair migration"
grep -Fq 'if [[ ${lang,,} =~ \.utf-?8(@[^[:space:]]+)?$ ]]' "$migration" ||
  fail "UTF-8 locale repair migration keeps an already configured UTF-8 locale"
grep -Fq 'sudo localectl set-locale LANG=C.UTF-8' "$migration" ||
  fail "UTF-8 locale repair migration goes through localectl"
disposition=$(grep '1787491150.sh)' "$migrate") ||
  fail "UTF-8 locale repair migration is registered in the Asahi dispositions"
[[ $disposition == *"printf 'run"* && $disposition == *'reviewed as architecture-neutral'* ]] ||
  fail "UTF-8 locale repair migration is reviewed for Apple Silicon"
pass "existing LANG=C installs are repaired through a reviewed migration"

grep -Fq 'system locale is not UTF-8' "$vm_verify" ||
  fail "fresh-install VM verification asserts the UTF-8 system locale"
pass "fresh-install VM regression asserts the configured locale is UTF-8"
