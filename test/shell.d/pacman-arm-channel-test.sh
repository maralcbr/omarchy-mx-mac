#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command python3
require_command pacman-conf
require_command bsdtar

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export OMARCHY_PATH="$ROOT"
source "$ROOT/install/helpers/pacman.sh"

printf 'Server = https://arm.example/$arch/$repo\n' >"$work/mirrorlist"

# An aarch64 machine's configuration: Omarchy with its own signature policy,
# Arch Linux ARM inline and through a mirrorlist, and a private repository
# whose server merely looks like Omarchy's.
original="[options]
Architecture = auto
SigLevel = Required DatabaseOptional
[omarchy]
SigLevel = Optional TrustAll
Server = https://pkgs.omarchy.org/stable/\$arch
[core]
Server = https://arm.example/\$arch/\$repo
[extra]
Include = $work/mirrorlist
[alarm]
Server = https://arm.example/\$arch/\$repo
[custom]
Server = https://custom.example/stable/\$arch
# This endpoint belongs to another repository and must not change.
Server = https://pkgs.omarchy.org/stable/\$arch
"

# swap <channel> <configuration> [platform]: the result in $work/out.conf.
swap() {
  printf '%s' "$2" >"$work/in.conf"
  omarchy_pacman_swap_channel "$1" "${3:-qualcomm}" "$work/in.conf" >"$work/out.conf"
}

# ── the channel gate ─────────────────────────────────────────────────────────

for channel in stable rc edge; do
  omarchy_pacman_channel_qualified "$channel" generic || fail "x86 keeps every channel ($channel)"
  for platform in qualcomm generic-aarch64 apple-silicon; do
    [[ $channel == "edge" && $platform != "apple-silicon" ]] && continue
    if omarchy_pacman_channel_qualified "$channel" "$platform" 2>"$work/err"; then
      fail "$platform refuses $channel, which has no qualified packages for it"
    fi
    grep -q "not qualified for $platform" "$work/err" || fail "$platform: the refusal says why" "$(cat "$work/err")"
  done
done
omarchy_pacman_channel_qualified edge qualcomm || fail "Qualcomm is qualified on edge"
omarchy_pacman_channel_qualified edge generic-aarch64 || fail "generic aarch64 is qualified on edge"
! omarchy_pacman_channel_qualified edge apple-silicon 2>"$work/err" || fail "Apple Silicon refuses edge until it is qualified"
grep -q 'Channels for this machine: none yet' "$work/err" || fail "Apple Silicon says it has no qualified channel yet" "$(cat "$work/err")"
! omarchy_pacman_channel_qualified edge riscv 2>/dev/null || fail "an unknown platform is refused"
! omarchy_pacman_channel_qualified nightly generic 2>/dev/null || fail "an unknown channel is refused"
pass "x86 keeps every channel, other aarch64 platforms take edge, and Apple Silicon none until qualified"

# ── keeping the repositories, swapping the channel ───────────────────────────

for source in stable rc edge; do
  for platform in qualcomm apple-silicon; do
    swap edge "${original/org\/stable\//org/$source/}" "$platform" || fail "a $source configuration switches to edge ($platform)"
    [[ $(cat "$work/out.conf"; echo .) == "${original/org\/stable\//org/edge/}." ]] ||
      fail "only the Omarchy server changes ($source, $platform)" "$(cat "$work/out.conf")"
  done
done
pass "a channel change keeps every repository, mirror, signature policy and look-alike server"

swap rc "$original"$'\n\n' || fail "a configuration ending in blank lines switches"
[[ $(cat "$work/out.conf"; echo .) == "${original/org\/stable\//org/rc/}"$'\n\n.' ]] || fail "the file's other bytes stay as they were"
literal=${original//\$arch/aarch64}
swap rc "$literal" || fail "a literal aarch64 endpoint switches"
[[ $(cat "$work/out.conf"; echo .) == "${literal/org\/stable\//org/rc/}." ]] || fail "a literal endpoint keeps its form"
cp "$work/out.conf" "$work/again.conf"
omarchy_pacman_swap_channel rc qualcomm "$work/again.conf" >"$work/out.conf" || fail "a repeated switch works"
cmp -s "$work/again.conf" "$work/out.conf" || fail "a repeated switch changes nothing"
pass "trailing lines, literal aarch64 endpoints and repeated switches are kept"

# Each variant on its own line of $work/bad, newlines escaped.
python3 - "$original" >"$work/bad" <<'PY'
import sys
o = sys.argv[1]
server = 'Server = https://pkgs.omarchy.org/stable/$arch\n[core]'
variants = [
    o.replace('pkgs.omarchy.org/stable', 'unknown.example/stable', 1),
    o.replace(server, 'Include = /etc/pacman.d/omarchy\n[core]', 1),
    o.replace('[core]', 'Server = https://pkgs.omarchy.org/rc/$arch\n[core]', 1),
    o.replace('[core]', 'Server = https://mirror.example/edge/$arch\n[core]', 1),
    o + '[omarchy]\nServer = https://pkgs.omarchy.org/edge/$arch\n',
    o.replace(server, '[core]', 1),
]
for v in variants:
    assert v != o
    print(v.replace('\n', '\\n'))
PY
while IFS= read -r bad; do
  if swap edge "$(printf '%b' "$bad")" 2>"$work/err"; then
    fail "an ambiguous or private Omarchy repository is refused" "$bad"
  fi
  grep -q 'configuration unchanged' "$work/err" || fail "the refusal says nothing changed"
done <"$work/bad"
(( $(wc -l <"$work/bad") == 6 )) || fail "every refused configuration was tried"
pass "an unknown, included, duplicated or missing Omarchy server stops the switch"

# The channel a configuration names, which omarchy-reinstall-pkgs refreshes on:
# read through pacman-conf, which expands $arch, and only from a single server
# on pkgs.omarchy.org.
mkdir -p "$work/conf-bin"
cat >"$work/conf-bin/pacman-conf" <<SH
#!/bin/bash
exec $(command -v pacman-conf) --config "$work/configured.conf" "\$@"
SH
chmod +x "$work/conf-bin/pacman-conf"
configured() {
  printf '%b' "$1" >"$work/configured.conf"
  PATH="$work/conf-bin:$PATH" omarchy_pacman_configured_channel
}
[[ $(configured "$original") == stable ]] || fail "the configured channel is read from the Omarchy server"
[[ $(configured '[options]\nArchitecture = aarch64\n[omarchy]\nServer = https://pkgs.omarchy.org/edge/aarch64\n') == edge ]] ||
  fail "a literal aarch64 endpoint names its channel"
for bad in '[options]\n[core]\nServer = https://arm.example/$arch/$repo\n' \
  '[omarchy]\nServer = https://pkgs.omarchy.org/stable/$arch\nServer = https://pkgs.omarchy.org/edge/$arch\n' \
  '[omarchy]\nServer = https://custom.example/edge/$arch\n' '[omarchy]\nServer = https://pkgs.omarchy.org/beta/$arch\n'; do
  if out=$(configured "$bad"); then fail "no single Omarchy channel is configured" "$bad"; fi
  [[ -z $out ]] || fail "an unreadable channel prints nothing" "$out"
done
pass "the configured channel is the Omarchy repository's single pkgs.omarchy.org server"

no_omarchy="[options]
Architecture = auto
[core]
Include = $work/mirrorlist
[alarm]
Include = $work/mirrorlist
"
swap edge "$no_omarchy" || fail "a configuration without Omarchy gets it"
[[ $(cat "$work/out.conf") == "$no_omarchy"$'\n[omarchy]\nServer = https://pkgs.omarchy.org/edge/$arch' ]] ||
  fail "Omarchy is added after the machine's own repositories" "$(cat "$work/out.conf")"
printf '[omarchy]\nServer = https://example.com/$arch\n' >"$work/extra.conf"
if swap edge "${no_omarchy/Architecture = auto/Architecture = auto
Include = $work/extra.conf}" 2>/dev/null; then
  fail "an Omarchy repository from an included file is not added again"
fi
if swap edge "$no_omarchy" apple-silicon 2>"$work/err"; then
  fail "Apple Silicon without an Omarchy repository is refused, since its own repository would come first"
fi
grep -q "no Omarchy repository, and on Apple Silicon one can't be added" "$work/err" || fail "the Mac's refusal says why" "$(cat "$work/err")"
pass "a configuration without an Omarchy repository gets one at the end, except on Apple Silicon or through an include"

# A configuration that isn't there or can't be read is refused, never taken for
# one without an Omarchy repository.
unreadable=("$work/missing.conf" "$work")
printf '%s' "$no_omarchy" >"$work/unreadable.conf"
chmod 000 "$work/unreadable.conf"
[[ -r $work/unreadable.conf ]] || unreadable+=("$work/unreadable.conf")
for source in "${unreadable[@]}"; do
  if omarchy_pacman_swap_channel edge qualcomm "$source" >"$work/out.conf" 2>"$work/err"; then
    fail "an unreadable configuration is refused ($source)"
  fi
  grep -q "Cannot read $source; configuration unchanged" "$work/err" || fail "the refusal says it can't read it ($source)" "$(cat "$work/err")"
  [[ ! -s $work/out.conf ]] || fail "an unreadable configuration prints nothing ($source)"
done
chmod 600 "$work/unreadable.conf"
(( ${#unreadable[@]} == 3 )) || skip "running as root; the unreadable-file case needs an unprivileged user"
pass "a missing, unreadable or directory configuration is refused, not given an Omarchy repository"

# ── install finalization ─────────────────────────────────────────────────────

etc="$work/etc"
mkdir -p "$etc"
for channel in stable rc edge; do
  omarchy_pacman_write_template "$channel" generic "$etc/pacman.conf" "$etc/mirrorlist" || fail "x86 finalization ($channel)"
  cmp -s "$etc/pacman.conf" "$ROOT/default/pacman/pacman-$channel.conf" || fail "x86 gets its channel's template ($channel)"
  cmp -s "$etc/mirrorlist" "$ROOT/default/pacman/mirrorlist-$channel" || fail "x86 gets its channel's mirrors ($channel)"
done
pass "x86 finalization writes the channel's template, as before"

for platform in qualcomm generic-aarch64; do
  for channel in stable rc; do
    output=$(omarchy_pacman_write_template "$channel" "$platform" "$etc/pacman.conf" "$etc/mirrorlist") || fail "$platform finalization on $channel"
    [[ $output == "Omarchy $channel is not qualified for $platform yet, so this machine gets no Omarchy repository; omarchy-channel-set edge adds one." ]] ||
      fail "$platform: finalization on $channel says why it adds no Omarchy repository" "$output"
  done
  cmp -s "$etc/pacman.conf" "$ROOT/default/pacman/pacman-aarch64.conf" || fail "$platform: stable has no Omarchy repository for it"
  cmp -s "$etc/mirrorlist" "$ROOT/default/pacman/mirrorlist-aarch64" || fail "$platform: Arch Linux ARM's mirrors"
  sed -i "s|/etc/pacman.d/mirrorlist|$etc/mirrorlist|" "$etc/pacman.conf"
  omarchy_pacman_swap_channel edge "$platform" "$etc/pacman.conf" >"$work/out.conf" || fail "$platform: a channel change reads a stable finalization"
  output=$(omarchy_pacman_write_template edge "$platform" "$etc/pacman.conf" "$etc/mirrorlist") || fail "$platform finalization on edge"
  [[ -z $output ]] || fail "$platform: finalization on edge has nothing to explain" "$output"
  [[ $(tail -n 2 "$etc/pacman.conf") == $'[omarchy]\nServer = https://pkgs.omarchy.org/edge/$arch' ]] ||
    fail "$platform: edge adds Omarchy after Arch Linux ARM" "$(cat "$etc/pacman.conf")"
  ! grep -q '^\[multilib\]' "$etc/pacman.conf" || fail "$platform: no x86 repository"
  sed -i "s|/etc/pacman.d/mirrorlist|$etc/mirrorlist|" "$etc/pacman.conf"
  cmp -s "$etc/pacman.conf" "$work/out.conf" || fail "$platform: switching a stable finalization to edge gives edge's"
  omarchy_pacman_swap_channel edge "$platform" "$etc/pacman.conf" >"$work/out.conf" || fail "$platform: a channel change reads an edge finalization"
  cmp -s "$etc/pacman.conf" "$work/out.conf" || fail "$platform: switching to the same channel changes nothing"
done
pass "other aarch64 platforms get Arch Linux ARM, with Omarchy on a qualified channel (saying why not otherwise), in a form channel changes read"

templates="$work/omarchy-mac-pacman"
mkdir -p "$templates"
for channel in stable rc edge; do
  printf '[options]\n[omarchy]\nServer = https://pkgs.omarchy.org/%s/$arch\n[mac-repository]\nServer = https://mac.example/$arch\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' "$channel" \
    >"$templates/pacman-$channel.conf"
done
for channel in stable rc edge; do
  printf 'image configuration\n' >"$etc/pacman.conf"
  printf 'image mirrors\n' >"$etc/mirrorlist"
  OMARCHY_MAC_PACMAN_TEMPLATES=$templates omarchy_pacman_write_template "$channel" apple-silicon "$etc/pacman.conf" "$etc/mirrorlist" >/dev/null ||
    fail "Apple Silicon finalization on an unqualified channel succeeds ($channel)"
  [[ $(cat "$etc/pacman.conf") == "image configuration" && $(cat "$etc/mirrorlist") == "image mirrors" ]] ||
    fail "Apple Silicon keeps its image's repositories on a channel not qualified for it ($channel)"
done
# Once edge is qualified for Apple Silicon.
(
  omarchy_pacman_qualified_channels() { [[ $1 == "apple-silicon" ]] && echo edge; }
  OMARCHY_MAC_PACMAN_TEMPLATES=$templates omarchy_pacman_write_template edge apple-silicon "$etc/pacman.conf" "$etc/mirrorlist" ||
    fail "Apple Silicon finalization on a qualified channel"
  cmp -s "$etc/pacman.conf" "$templates/pacman-edge.conf" || fail "Apple Silicon gets omarchy-mac's template"
  cmp -s "$etc/mirrorlist" "$ROOT/default/pacman/mirrorlist-aarch64" || fail "Apple Silicon gets Arch Linux ARM's mirrors"
  sed "s|/etc/pacman.d/mirrorlist|$work/mirrorlist|" "$etc/pacman.conf" >"$work/mac.conf"
  omarchy_pacman_swap_channel edge apple-silicon "$work/mac.conf" >"$work/out.conf" || fail "a Mac's channel change reads omarchy-mac's template"
  cmp -s "$work/mac.conf" "$work/out.conf" || fail "the Mac's own repository stays, after Omarchy's"
  rm "$templates/pacman-edge.conf"
  printf 'image configuration\n' >"$etc/pacman.conf"
  if OMARCHY_MAC_PACMAN_TEMPLATES=$templates omarchy_pacman_write_template edge apple-silicon "$etc/pacman.conf" "$etc/mirrorlist" 2>"$work/err"; then
    fail "Apple Silicon without omarchy-mac's template fails finalization"
  fi
  grep -q 'omarchy-mac provides it' "$work/err" || fail "the failure names omarchy-mac"
  [[ $(cat "$etc/pacman.conf") == "image configuration" ]] || fail "a missing template leaves the configuration alone"
)
pass "Apple Silicon keeps its image's repositories until a channel is qualified, then gets omarchy-mac's template"

! omarchy_pacman_write_template edge riscv "$etc/pacman.conf" "$etc/mirrorlist" 2>/dev/null || fail "an unknown platform is refused"
! omarchy_pacman_write_template nightly generic "$etc/pacman.conf" "$etc/mirrorlist" 2>/dev/null || fail "an unknown channel is refused"
pass "finalization refuses an unknown platform or channel"

# ── the preflight ────────────────────────────────────────────────────────────

# A repository database listing the named packages.
repository() {
  local db="$work/repository" package
  rm -rf "$db" "$work/omarchy.db"
  mkdir -p "$db"
  for package in "$@"; do
    mkdir -p "$db/$package-1.0.r1.g0-1"
    printf '%%NAME%%\n%s\n' "$package" >"$db/$package-1.0.r1.g0-1/desc"
  done
  (cd "$db" && bsdtar -czf "$work/omarchy.db" -- *)
}
mkdir -p "$work/bin"
cat >"$work/bin/curl" <<'SH'
#!/bin/bash
printf '%s\n' "${@: -1}" >>"$CURL_LOG"
[[ ${CURL_FAIL:-0} == 0 ]] || exit 22
cat "$CURL_DB"
SH
chmod +x "$work/bin/curl"
preflight() {
  : >"$work/curl.log"
  CURL_LOG="$work/curl.log" CURL_DB="$work/omarchy.db" PATH="$work/bin:$PATH" omarchy_pacman_preflight "$@"
}

repository omarchy-dev omarchy-settings-dev omarchy-mac omarchy-mac-boot omarchy-mac-extra
preflight edge apple-silicon || fail "Apple Silicon's preflight passes where edge has its packages"
[[ $(cat "$work/curl.log") == "https://pkgs.omarchy.org/edge/aarch64/omarchy.db" ]] || fail "the preflight reads the channel's package list" "$(cat "$work/curl.log")"
preflight edge qualcomm || fail "Qualcomm's preflight passes"
repository omarchy-dev omarchy-settings-dev omarchy-mac-boot omarchy-mac-extra
if preflight edge apple-silicon 2>"$work/err"; then fail "a missing Mac package stops Apple Silicon's preflight"; fi
grep -q 'does not publish omarchy-mac for' "$work/err" || fail "the failure names the package" "$(cat "$work/err")"
preflight edge qualcomm || fail "Qualcomm needs only the runtime pair"
repository omarchy omarchy-settings
preflight stable generic-aarch64 || fail "stable checks the release pair"
[[ $(cat "$work/curl.log") == "https://pkgs.omarchy.org/stable/aarch64/omarchy.db" ]] || fail "stable reads stable's package list"
if preflight edge qualcomm 2>/dev/null; then fail "edge needs the development pair"; fi
if CURL_FAIL=1 preflight stable qualcomm 2>"$work/err"; then fail "an unreadable package list stops the preflight"; fi
grep -q 'No repository configuration changed' "$work/err" || fail "the failure says nothing changed"
pass "the preflight checks the channel publishes the runtime pair, and on Apple Silicon the Mac's packages"

# ── telling a machine with no Omarchy repository ─────────────────────────────

# A stable finalization on Snapdragon: Arch Linux ARM, no Omarchy.
omarchy_pacman_write_template stable qualcomm "$etc/pacman.conf" "$etc/mirrorlist" >/dev/null
sed -i "s|/etc/pacman.d/mirrorlist|$etc/mirrorlist|" "$etc/pacman.conf"
cp "$etc/pacman.conf" "$work/no-omarchy.conf"
omarchy_pacman_write_template edge qualcomm "$etc/pacman.conf" "$etc/mirrorlist"
sed -i "s|/etc/pacman.d/mirrorlist|$etc/mirrorlist|" "$etc/pacman.conf"
cp "$etc/pacman.conf" "$work/omarchy.conf"
mkdir -p "$work/platform-bin"
cat >"$work/platform-bin/omarchy-hw-platform" <<SH
#!/bin/bash
echo asked >>"$work/platform-asked"
echo "\$TEST_PLATFORM"
SH
chmod +x "$work/platform-bin/omarchy-hw-platform"
notice() {
  rm -f "$work/platform-asked"
  TEST_PLATFORM=$1 PATH="$work/platform-bin:$PATH" omarchy_pacman_missing_repository_notice "${@:2}"
}
expected="This machine has no Omarchy repository, so its Omarchy packages get no updates. Switch to edge with: omarchy-channel-set edge"
for platform in qualcomm generic-aarch64; do
  [[ $(notice "$platform" "$work/no-omarchy.conf") == "$expected" ]] || fail "$platform without an Omarchy repository is told how to get one"
  [[ $(notice other "$work/no-omarchy.conf" "$platform") == "$expected" ]] || fail "$platform: a caller that knows the platform passes it"
  [[ -z $(notice "$platform" "$work/omarchy.conf") ]] || fail "$platform with an Omarchy repository hears nothing"
  [[ ! -e $work/platform-asked ]] || fail "$platform: with an Omarchy repository the platform is never looked up"
done
for platform in generic apple-silicon; do
  [[ -z $(notice "$platform" "$work/no-omarchy.conf") ]] || fail "$platform without an Omarchy repository hears nothing"
done
[[ -z $(notice qualcomm "$work/absent.conf") ]] || fail "a configuration pacman-conf can't read says nothing"
[[ -z $(notice qualcomm "$ROOT/default/pacman/pacman-stable.conf") && ! -e $work/platform-asked ]] ||
  fail "x86's template names Omarchy, so the platform is never looked up"
pass "only a Snapdragon or generic aarch64 machine with no Omarchy repository is told to switch to edge"

# The update's confirmation, which first run's "Update System" opens, is where
# the owner reads it.
cat >"$work/platform-bin/gum" <<'SH'
#!/bin/bash
[[ $1 == "style" ]] && printf '%s\n' "$@"
exit 0
SH
chmod +x "$work/platform-bin/gum"
confirm() {
  sed "s|/etc/pacman.conf|$1|" "$ROOT/bin/omarchy-update-confirm" >"$work/confirm"
  TEST_PLATFORM=$2 PATH="$work/platform-bin:$PATH" bash "$work/confirm"
}
grep -Fqx "• $expected" <<<"$(confirm "$work/no-omarchy.conf" qualcomm)" || fail "Snapdragon's update confirmation says it has no Omarchy repository"
for platform in generic apple-silicon; do
  ! grep -q 'Omarchy repository' <<<"$(confirm "$work/no-omarchy.conf" "$platform")" || fail "$platform: the update confirmation is unchanged"
done
output=$(confirm "$work/omarchy.conf" qualcomm)
! grep -q 'Omarchy repository' <<<"$output" || fail "a machine with an Omarchy repository sees the usual confirmation"
grep -Fqx "• You cannot stop the update once you start!" <<<"$output" || fail "the usual notes stay"
pass "the update confirmation tells a Snapdragon machine with no Omarchy repository to switch to edge"

# ── refresh through the command, with every privileged step a stand-in ───────

# The fixture keeps its own directory and cleanup from here on.
repository omarchy-dev omarchy-settings-dev
edge_db=$(mktemp)
cp "$work/omarchy.db" "$edge_db"
rm -rf "$work"
trap 'rm -f "$edge_db"' EXIT
source "$SHELL_TEST_DIR/fixtures/sudo-boundary-test.sh"
trap 'rm -rf "$boundary_tmp"; rm -f "$edge_db"' EXIT
copy_boundary_file bin/omarchy-refresh-pacman
config="$boundary_tmp/etc/pacman.conf"
mkdir -p "${config%/*}"
sed -i "s|/etc/pacman.conf|$config|g" "$SUDO_TEST_ROOT/bin/omarchy-refresh-pacman"
cat >"$SUDO_TEST_ROOT/bin/curl" <<SH
#!/bin/bash
printf 'step:curl %s\n' "\$*" >>"\$SUDO_TEST_LOG"
[[ \${SUDO_TEST_CURL_FAIL:-0} == 0 ]] || exit 22
cat "$edge_db"
SH
chmod +x "$SUDO_TEST_ROOT/bin/curl"
before=${original//$work\/mirrorlist/\/etc\/pacman.d\/mirrorlist}

refresh() {
  printf '%s' "$before" >"$config"
  rm -f "$config.bak"
  "$SUDO_TEST_ROOT/bin/omarchy-refresh-pacman" "$@" >"$boundary_tmp/output" 2>&1
}
events() {
  grep -vE '^sudo (-h|-k)$' "$SUDO_TEST_LOG" || true
}

for platform in apple-silicon qualcomm generic-aarch64; do
  for channel in stable rc edge; do
    [[ $channel == "edge" && $platform != "apple-silicon" ]] && continue
    reset_boundary
    if SUDO_TEST_PLATFORM=$platform refresh "$channel"; then fail "$platform refuses to refresh to $channel"; fi
    [[ -z $(events) ]] || fail "$platform: an unqualified channel stops before anything else" "$(events)"
    grep -q "not qualified for $platform" "$boundary_tmp/output" || fail "$platform: the refusal says why" "$(cat "$boundary_tmp/output")"
    [[ $(cat "$config"; echo .) == "$before." ]] || fail "$platform: the configuration is unchanged"
    assert_boundary_cold "$platform $channel"
  done
done
pass "aarch64 platforms refuse a channel not qualified for them before anything else"

# A machine that got no Omarchy repository hears how to get one with the refusal.
with_omarchy=$before
for platform in qualcomm apple-silicon; do
  before=$(sed '/^\[omarchy\]/,/^Server/d' <<<"$with_omarchy")
  reset_boundary
  if SUDO_TEST_PLATFORM=$platform refresh stable; then fail "$platform refuses stable without an Omarchy repository"; fi
  if [[ $platform == "qualcomm" ]]; then
    grep -q 'no Omarchy repository.*omarchy-channel-set edge' "$boundary_tmp/output" ||
      fail "Snapdragon without an Omarchy repository is told to switch to edge" "$(cat "$boundary_tmp/output")"
  else
    ! grep -q 'no Omarchy repository' "$boundary_tmp/output" || fail "Apple Silicon's refusal is unchanged" "$(cat "$boundary_tmp/output")"
  fi
done
before=$with_omarchy
reset_boundary
if SUDO_TEST_PLATFORM=qualcomm refresh stable; then fail "Snapdragon refuses stable"; fi
! grep -q 'no Omarchy repository' "$boundary_tmp/output" || fail "a machine with an Omarchy repository hears only the refusal"
pass "an aarch64 refusal tells a Snapdragon machine without an Omarchy repository to switch to edge"

reset_boundary
SUDO_TEST_PLATFORM=qualcomm refresh edge || fail "Qualcomm refreshes to edge" "$(cat "$boundary_tmp/output")"
[[ $(cat "$config"; echo .) == "${before/org\/stable\//org/edge/}." ]] || fail "only the Omarchy channel changed" "$(cat "$config")"
python3 - "$SUDO_TEST_LOG" "$config" <<'PY'
import sys
events = [e for e in open(sys.argv[1]).read().splitlines() if e not in ('sudo -h', 'sudo -k')]
config = sys.argv[2]
curl = events.index('step:curl -fsSL --retry 2 https://pkgs.omarchy.org/edge/aarch64/omarchy.db')
backup = events.index(f'step:cp -f {config} {config}.bak')
write = events.index(f'sudo -N tee {config}')
hook = events.index('step:omarchy-hook pre-refresh-pacman')
transaction = events.index('step:pacman -Syyuu --noconfirm')
assert curl < backup < write < hook < transaction, events
assert not any('mirrorlist' in e for e in events), events
assert all(e.startswith('sudo -N ') for e in events if e.startswith('sudo ')), events
PY
assert_boundary_cold "Qualcomm edge"
pass "an aarch64 machine checks the channel, backs up and swaps only pacman.conf, keeps its mirrors, then runs the cold hook and the upgrade"

reset_boundary
if SUDO_TEST_PLATFORM=qualcomm SUDO_TEST_CURL_FAIL=1 refresh edge; then fail "a failed preflight stops the refresh"; fi
! grep -qE '^step:(cp|omarchy-hook|pacman)|^sudo -N ' "$SUDO_TEST_LOG" || fail "a failed preflight writes nothing and runs nothing" "$(cat "$SUDO_TEST_LOG")"
[[ $(cat "$config"; echo .) == "$before." ]] || fail "a failed preflight leaves the configuration alone"
assert_boundary_cold "failed preflight"
pass "a failed preflight changes nothing and exits cold"

before='[options]
[omarchy]
Include = /etc/pacman.d/omarchy
'
reset_boundary
if SUDO_TEST_PLATFORM=qualcomm refresh edge; then fail "an unreadable Omarchy channel stops the refresh"; fi
[[ -z $(events) ]] || fail "an unreadable Omarchy channel stops before anything else" "$(events)"
[[ $(cat "$config"; echo .) == "$before." ]] || fail "an unreadable Omarchy channel leaves the configuration alone"
assert_boundary_cold "unreadable channel"
pass "a configuration whose Omarchy channel can't be read stops before anything else"
