#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Exempt: the helpers themselves; the two bootstrap installers, which run before
# the Omarchy runtime exists; and the two Apple Silicon boot-loader decisions,
# which the fresh installer calls against a possibly incomplete runtime and
# which must decide the same way whether or not the helpers are present.
raw_command_checks=$(rg -l 'command -v' "$ROOT/bin" \
  | rg -v '/omarchy-(cmd-|pkg-|(upgrade-to-quattro|install-asahi-fresh|mac-limine-active|mac-boot-update)$)' || true)
[[ -z $raw_command_checks ]] || fail "bin commands use command helpers" "$raw_command_checks"
pass "bin commands use command helpers"

raw_notifications=$(rg -l -P '^[[:space:]]*[^#[:space:]].*\bnotify-send\b' "$ROOT/bin" || true)
[[ -z $raw_notifications ]] || fail "bin commands use the notification helper, never notify-send" "$raw_notifications"
pass "bin commands use the notification helper"
