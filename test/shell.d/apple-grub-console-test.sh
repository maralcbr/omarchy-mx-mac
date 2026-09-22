#!/bin/bash
#
# The GRUB console leaf gives an Apple Silicon Mac the x86 Limine look and a
# splash-only boot: theme fonts and theme.txt under /boot/grub/themes/omarchy,
# a readable console font, the menu shown for three seconds, the efi_gop
# backend, the unbounded root-device wait, Plymouth told to ignore the serial
# console, and 10_linux's "Loading ..." echoes guarded behind "quiet". One
# update-grub per change, nothing on a second run, a retry when it failed.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/grub-console.sh"
theme="$ROOT/default/grub/omarchy/theme.txt"
fixture="$ROOT/test/fixtures/grub/10_linux"
grep -Fq 'hardware/apple/grub-console.sh' "$ROOT/install/hardware/all.sh" || fail "the leaf is a deferred hardware step"
[[ -f $theme && -f $fixture ]] || fail "the theme and the 10_linux fixture ship with the runtime"
grep -Fxq 'desktop-color: "#1a1b26"' "$theme" && grep -Fxq 'title-color: "#9ece6a"' "$theme" ||
  fail "the theme carries the Tokyo Night backdrop and the green Omarchy title"
! grep -Fq '.png' "$theme" || fail "the theme references no bitmap GRUB would have to load"
for face in "Liberation Sans Bold 36" "Liberation Mono Regular 28" "Liberation Mono Regular 24" "Liberation Mono Regular 20"; do
  grep -Fq "\"$face\"" "$theme" || fail "the theme names the face the leaf renders: $face"
done
pass "the theme is the x86 palette and names only fonts the leaf renders"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fonts" "$tmp/liberation" "$tmp/grub.d" "$tmp/backups"
export CALL_LOG="$tmp/calls"
export PATH="$tmp/bin:$ROOT/bin:$PATH"
printf '#!/bin/bash\nexit "${APPLE:-0}"\n' >"$tmp/bin/omarchy-hw-apple-silicon"
printf '#!/bin/bash\nexec "$@"\n' >"$tmp/bin/sudo"
printf '#!/bin/bash\necho "mkfont $*" >>"$CALL_LOG"; while (( $# > 1 )); do [[ $1 == -o ]] && printf font >"$2"; shift; done\n' >"$tmp/bin/grub-mkfont"
printf '#!/bin/bash\necho update-grub >>"$CALL_LOG"\n' >"$tmp/bin/update-grub"
chmod +x "$tmp/bin"/*
for ttf in LiberationMono-Regular LiberationSans-Bold; do : >"$tmp/liberation/$ttf.ttf"; done
cp "$fixture" "$tmp/grub.d/10_linux"

run_leaf() {
  : >"$CALL_LOG"
  OMARCHY_GRUB_CONSOLE_PENDING="$tmp/pending" OMARCHY_GRUB_DEFAULT="$tmp/grub" \
  OMARCHY_GRUB_FONT="$tmp/fonts/omarchy.pf2" OMARCHY_GRUB_THEME_DIR="$tmp/themes/omarchy" \
  OMARCHY_GRUB_THEME_SOURCE="$theme" OMARCHY_GRUB_FONT_SOURCE_DIR="$tmp/liberation" \
  OMARCHY_GRUB_LINUX_SCRIPT="$tmp/grub.d/10_linux" OMARCHY_GRUB_BACKUP_DIR="$tmp/backups" \
    bash -euo pipefail -c 'source "$1"' _ "$leaf" >"$tmp/out" 2>&1
}

printf 'GRUB_TIMEOUT="1"\nGRUB_TIMEOUT_STYLE="hidden"\nGRUB_CMDLINE_LINUX="zswap.enabled=0 rootfstype=btrfs"\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0"\n' >"$tmp/grub"
run_leaf || fail "the leaf runs: $(<"$tmp/out")"
for spec in "28 -o $tmp/fonts/omarchy.pf2 $tmp/liberation/LiberationMono-Regular.ttf" \
  "36 -o $tmp/themes/omarchy/sans-bold-36.pf2 $tmp/liberation/LiberationSans-Bold.ttf" \
  "28 -o $tmp/themes/omarchy/mono-28.pf2 $tmp/liberation/LiberationMono-Regular.ttf" \
  "24 -o $tmp/themes/omarchy/mono-24.pf2 $tmp/liberation/LiberationMono-Regular.ttf" \
  "20 -o $tmp/themes/omarchy/mono-20.pf2 $tmp/liberation/LiberationMono-Regular.ttf"; do
  grep -Fq "mkfont -s $spec" "$CALL_LOG" || fail "the leaf renders $spec: $(<"$CALL_LOG")"
done
cmp -s "$theme" "$tmp/themes/omarchy/theme.txt" || fail "the theme is installed beside its fonts"
for line in "GRUB_FONT=\"$tmp/fonts/omarchy.pf2\"" "GRUB_THEME=\"$tmp/themes/omarchy/theme.txt\"" 'GRUB_TIMEOUT="3"' \
  'GRUB_TIMEOUT_STYLE="menu"' 'GRUB_VIDEO_BACKEND="efi_gop"' \
  'GRUB_CMDLINE_LINUX="zswap.enabled=0 rootfstype=btrfs rootflags=x-systemd.device-timeout=0"' \
  'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 plymouth.ignore-serial-consoles"'; do
  grep -Fxq "$line" "$tmp/grub" || fail "the defaults carry $line: $(<"$tmp/grub")"
done
[[ $(grep -c update-grub "$CALL_LOG") == 1 ]] || fail "grub.cfg is regenerated once"
pass "the leaf installs the theme and fonts, shows the menu for 3 s, and quiets the kernel line"

# 10_linux: both echoes guarded, the original kept outside grub.d.
[[ $(grep -Fc 'Omarchy: no narration' "$tmp/grub.d/10_linux") == 2 ]] || fail "both loading messages are guarded"
[[ $(grep -Fc $'\t${message:+echo\t' "$tmp/grub.d/10_linux") == 2 ]] || fail "both echoes are emitted only with a message"
! grep -Fq $'\techo\t\'$(echo "$message" | grub_quote)\'' "$tmp/grub.d/10_linux" || fail "no unguarded echo survives"
cmp -s "$fixture" "$tmp/backups/10_linux.pre-omarchy" || fail "the original 10_linux is kept under the backups directory"
[[ -z $(ls "$tmp/grub.d" | grep -v '^10_linux$') ]] || fail "nothing extra lands in grub.d: $(ls "$tmp/grub.d")"
sh -n "$tmp/grub.d/10_linux" || fail "the patched 10_linux still parses"
# The guarded heredoc, executed as sh: a quiet line emits no echo, a loud one does.
render_echo() {
  GRUB_CMDLINE_LINUX_DEFAULT=$1 sh "$tmp/render.sh" | grep -c "echo"
}
cat >"$tmp/render.sh" <<'RENDER'
grub_quote() { sed "s/'/'\\\\''/g"; }
gettext_printf() { printf "$@"; }
version=aurora submenu_indentation="" rel_dirname=/ basename=vmlinuz linux_root_device_thisversion=UUID=x args=""
message="$(gettext_printf "Loading Linux %s ..." ${version})"
case " $GRUB_CMDLINE_LINUX_DEFAULT " in *" quiet "*) message="" ;; esac
sed "s/^/$submenu_indentation/" << HEREDOC
	${message:+echo	'$(echo "$message" | grub_quote)'}
	linux	${rel_dirname}/${basename} root=${linux_root_device_thisversion} rw ${args}
HEREDOC
RENDER
[[ $(render_echo "quiet splash") == 0 && $(render_echo "splash") == 1 ]] || fail "the guard drops the echo only on a quiet line"
pass "10_linux narrates only without quiet, and its original stays out of grub.d"

# An unexpected 10_linux (different echo lines) is left alone, with a warning.
printf 'GRUB_CMDLINE_LINUX="zswap.enabled=0"\n' >"$tmp/grub"
sed 's/^\techo\t/\t  echo\t/' "$fixture" >"$tmp/grub.d/10_linux"
cp "$tmp/grub.d/10_linux" "$tmp/unfamiliar"
run_leaf || fail "an unfamiliar 10_linux does not fail the leaf: $(<"$tmp/out")"
cmp -s "$tmp/unfamiliar" "$tmp/grub.d/10_linux" || fail "an unfamiliar 10_linux is left untouched"
grep -Fq 'leaving its echoes' "$tmp/out" || fail "the leaf says why the echoes stay: $(<"$tmp/out")"
cp "$fixture" "$tmp/grub.d/10_linux"; run_leaf || fail "back to the fixture: $(<"$tmp/out")"

# A font that cannot be rendered keeps the theme off rather than half on.
printf '#!/bin/bash\necho "mkfont $*" >>"$CALL_LOG"; exit 1\n' >"$tmp/bin/grub-mkfont"
rm -rf "$tmp/themes" "$tmp/fonts"; printf 'GRUB_CMDLINE_LINUX="zswap.enabled=0"\n' >"$tmp/grub"
run_leaf || fail "a failed font render does not fail the leaf: $(<"$tmp/out")"
! grep -q "GRUB_THEME=" "$tmp/grub" && ! grep -q "GRUB_FONT=" "$tmp/grub" || fail "no theme or font is activated without its faces: $(<"$tmp/grub")"
printf '#!/bin/bash\necho "mkfont $*" >>"$CALL_LOG"; while (( $# > 1 )); do [[ $1 == -o ]] && printf font >"$2"; shift; done\n' >"$tmp/bin/grub-mkfont"
pass "a font that cannot be rendered leaves the theme off"
run_leaf || fail "the fonts render once grub-mkfont works again: $(<"$tmp/out")"

run_leaf || fail "a second run passes"
[[ ! -s $CALL_LOG ]] || fail "a configured Mac renders nothing and runs no update-grub: $(<"$CALL_LOG")"
pass "the leaf is idempotent"

# A duplicate or commented assignment: one authoritative line survives with
# the effective (last) value extended.
printf '#GRUB_CMDLINE_LINUX="old"\nGRUB_CMDLINE_LINUX="first"\nGRUB_TIMEOUT="1"\nGRUB_CMDLINE_LINUX='"'"'zswap.enabled=0'"'"'\n' >"$tmp/grub"
run_leaf || fail "duplicate assignments are handled: $(<"$tmp/out")"
[[ $(grep -c "GRUB_CMDLINE_LINUX=" "$tmp/grub") == 1 ]] || fail "one GRUB_CMDLINE_LINUX line remains: $(<"$tmp/grub")"
grep -Fxq 'GRUB_CMDLINE_LINUX="zswap.enabled=0 rootflags=x-systemd.device-timeout=0"' "$tmp/grub" ||
  fail "the effective (last, single-quoted) value is the one extended: $(<"$tmp/grub")"
pass "the leaf leaves one authoritative assignment carrying the effective value"

# A failed update-grub leaves the regeneration owed.
printf '#!/bin/bash\necho update-grub >>"$CALL_LOG"; exit 1\n' >"$tmp/bin/update-grub"
printf 'GRUB_CMDLINE_LINUX="zswap.enabled=0"\n' >"$tmp/grub"
if run_leaf; then fail "a failed update-grub must fail the leaf"; fi
[[ -e $tmp/pending ]] || fail "a failed regeneration is recorded as pending"
printf '#!/bin/bash\necho update-grub >>"$CALL_LOG"\n' >"$tmp/bin/update-grub"
run_leaf || fail "the retry runs: $(<"$tmp/out")"
grep -q update-grub "$CALL_LOG" || fail "the retry regenerates GRUB although the defaults were already set"
[[ ! -e $tmp/pending ]] || fail "a successful regeneration clears the pending marker"
pass "a failed regeneration is retried on the next run"

printf 'GRUB_CMDLINE_LINUX="zswap.enabled=0"\n' >"$tmp/grub"
APPLE=1 run_leaf || fail "a non-Apple machine passes"
[[ ! -s $CALL_LOG ]] && grep -Fxq 'GRUB_CMDLINE_LINUX="zswap.enabled=0"' "$tmp/grub" || fail "a non-Apple machine is untouched"
pass "the leaf gates itself to Apple Silicon"

grep -Fq 'hardware/apple/grub-console.sh' "$ROOT/migrations/1790030337.sh" "$ROOT/migrations/1790037110.sh" >/dev/null ||
  fail "installed Macs run the leaf through the migrations"
pass "installed Macs get the same through the migrations"
