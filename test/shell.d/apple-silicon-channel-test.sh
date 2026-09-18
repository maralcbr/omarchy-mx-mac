#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command cmp
require_command flock
require_command timeout

helper="$ROOT/bin/omarchy-apple-silicon-channel"

grep -Fq '# omarchy:hidden=true' "$helper" || fail "the channel helper is hidden from command listings"
grep -Fq '# omarchy:requires-sudo=true' "$helper" || fail "the channel helper declares its sudo requirement"
! grep -Eq 'pacman -Q [^q]|omarchy-pkg-(present|missing)|omarchy-hw-apple-kernel' "$helper" ||
  fail "the channel helper reads kernels by exact installed name and parses the marker itself"
pass "the channel helper is hidden, needs sudo and never asks pacman for a kernel by name"

test_tmp=$(mktemp -d)
holder_pid=""
cleanup() {
  [[ -z $holder_pid ]] || kill "$holder_pid" 2>/dev/null || true
  rm -rf "$test_tmp"
}
trap cleanup EXIT

stub_bin="$test_tmp/bin"
root="$test_tmp/root"
state_dir="$root/var/lib/omarchy"
record="$state_dir/apple-silicon-channel"
marker="$root/usr/share/omarchy/apple-silicon-kernel"
calls="$test_tmp/calls"
pacman_calls="$test_tmp/pacman-calls"
mkdir -p "$stub_bin" "$state_dir" "$(dirname "$marker")"
chmod 0755 "$state_dir"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$TEST_CALLS"
# Hold each run creating the directory until two have got that far.
if [[ $1 == "install" && $2 == "-d" && -n ${TEST_INSTALL_GATE:-} ]]; then
  : >"$TEST_INSTALL_GATE.$$"
  for _ in $(seq 200); do
    (( $(compgen -G "$TEST_INSTALL_GATE.*" | wc -l) >= 2 )) && break
    sleep 0.05
  done
fi
if [[ $1 == "mv" && ${TEST_MV_FAIL:-0} == 1 ]]; then
  echo "mv: cannot move: Input/output error" >&2
  exit 1
fi
exec "$@"
SH
# The test cannot make files root's; ownership checks are relaxed in test mode.
cat >"$stub_bin/install" <<'SH'
#!/bin/bash
args=()
while (($#)); do
  case "$1" in
    -o|-g) shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
exec /usr/bin/install "${args[@]}"
SH
cat >"$stub_bin/chown" <<'SH'
#!/bin/bash
exit 0
SH
# pacman -Q answers through provides the way the real one does: linux-aurora
# provides linux-asahi.
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
# Groups come from TEST_GROUPS, as package:group words.
if [[ $1 == "-Qi" || $1 == "-Si" ]]; then
  groups=()
  for entry in ${TEST_GROUPS:-}; do
    [[ ${entry%%:*} != "$2" ]] || groups+=("${entry#*:}")
  done
  printf 'Name            : %s\nGroups          : %s\n' "$2" "${groups[*]:-None}"
  exit 0
fi
if [[ $* == "-Qq" ]]; then
  [[ ${TEST_PACMAN_FAIL:-0} != 1 ]] || exit 1
  printf '%s\n' $TEST_INSTALLED
  exit 0
fi
printf '%s\n' "$*" >>"$TEST_PACMAN_CALLS"
if [[ $1 == "-Q" ]]; then
  [[ " $TEST_INSTALLED " == *" $2 "* ]] && exit 0
  [[ $2 == "linux-asahi" && " $TEST_INSTALLED " == *" linux-aurora "* ]] && exit 0
fi
exit 1
SH
cat >"$stub_bin/omarchy-hw-apple-silicon" <<'SH'
#!/bin/bash
[[ ${TEST_APPLE_SILICON:-1} == 1 ]]
SH
chmod +x "$stub_bin"/*

aurora_installed="linux-aurora linux-aurora-headers m1n1-aurora"
asahi_installed="linux-asahi linux-asahi-headers m1n1"

invoke() {
  local out=$1 err=$2
  shift 2
  TEST_CALLS="$calls" \
    TEST_PACMAN_CALLS="$pacman_calls" \
    TEST_INSTALLED="${TEST_INSTALLED-$aurora_installed}" \
    OMARCHY_APPLE_SILICON_CHANNEL_ROOT="$root" \
    OMARCHY_APPLE_SILICON_CHANNEL_TESTING=1 \
    OMARCHY_APPLE_SILICON_CHANNEL_LOCK_TIMEOUT="${TEST_LOCK_TIMEOUT:-10}" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    timeout "${TEST_RUN_TIMEOUT:-30}" bash "$helper" "$@" >"$out" 2>"$err"
}

run() {
  set +e
  invoke "$test_tmp/out" "$test_tmp/err" "$@"
  status=$?
  set -e
}

reset() {
  rm -f "$record" "$marker" "$state_dir"/.apple-silicon-channel.*
  : >"$calls"
  : >"$pacman_calls"
}

write_record() {
  printf "$@" >"$record"
  chmod 0644 "$record"
  cp "$record" "$test_tmp/record-before"
}

rc_record='format=1\nchannel=rc\nkernel=linux-aurora\n'
stable_record='format=1\nchannel=stable\nkernel=linux-asahi\n'

expect_record() {
  local description=$1
  shift
  printf "$@" >"$test_tmp/expected"
  cmp -s "$test_tmp/expected" "$record" || fail "$description" "$(diff "$test_tmp/expected" "$record" || true)"
  [[ $(stat -c '%a' "$record") == 644 ]] || fail "$description: the record is 0644"
}

no_staging_left() {
  ! compgen -G "$state_dir/.apple-silicon-channel.*" >/dev/null || fail "$1: no staging file is left" "$(ls -a "$state_dir")"
}

# Inference, when there is no record.
reset
run ensure
(( status == 0 )) || fail "an Aurora Mac without a marker is recorded" "status $status: $(cat "$test_tmp/err")"
expect_record "an Aurora Mac is recorded as rc on linux-aurora" "$rc_record"
[[ ! -s $test_tmp/out && ! -s $test_tmp/err ]] || fail "recording a channel is silent" "$(cat "$test_tmp/out" "$test_tmp/err")"
grep -Eq "^sudo:mktemp -p $state_dir \.apple-silicon-channel\.XXXXXX\$" "$calls" || fail "the record is staged inside its directory" "$(cat "$calls")"
grep -Eq "^sudo:mv -f $state_dir/\.apple-silicon-channel\.[A-Za-z0-9]{6} $record\$" "$calls" || fail "the record is renamed into place" "$(cat "$calls")"
no_staging_left "a recorded channel"
[[ ! -s $pacman_calls ]] || fail "only pacman -Qq is asked" "$(cat "$pacman_calls")"
pass "an Aurora Mac without a marker is recorded as rc through a staged rename"

reset
printf 'linux-aurora\n' >"$marker"
run ensure
(( status == 0 )) || fail "an Aurora marker is accepted" "status $status: $(cat "$test_tmp/err")"
expect_record "an Aurora marker records rc" "$rc_record"
reset
printf 'linux-aurora' >"$marker"
run ensure
(( status == 0 )) || fail "a marker without a final newline is accepted" "status $status: $(cat "$test_tmp/err")"
expect_record "a marker without a final newline records rc" "$rc_record"
pass "an Aurora marker, with or without its final newline, records rc"

reset
TEST_INSTALLED="$asahi_installed" run ensure
(( status == 0 )) || fail "an Asahi Mac is recorded" "status $status: $(cat "$test_tmp/err")"
expect_record "an Asahi Mac is recorded as stable on linux-asahi" "$stable_record"
reset
printf 'linux-asahi\n' >"$marker"
TEST_INSTALLED="$asahi_installed" run ensure
(( status == 0 )) || fail "an Asahi marker is accepted" "status $status: $(cat "$test_tmp/err")"
expect_record "an Asahi marker records stable" "$stable_record"
pass "an Asahi Mac is recorded as stable"

# linux-aurora provides linux-asahi, so pacman -Q linux-asahi succeeds on an
# Aurora Mac. The package names installed are the evidence, not what resolves.
reset
TEST_CALLS="$calls" TEST_PACMAN_CALLS="$test_tmp/sanity" TEST_INSTALLED="$aurora_installed" "$stub_bin/pacman" -Q linux-asahi ||
  fail "the pacman stub resolves linux-asahi through linux-aurora"
run ensure
(( status == 0 )) || fail "an Aurora Mac that resolves linux-asahi is recorded" "status $status: $(cat "$test_tmp/err")"
expect_record "an Aurora Mac that resolves linux-asahi is still rc" "$rc_record"
[[ ! -s $pacman_calls ]] || fail "no kernel is asked for by name" "$(cat "$pacman_calls")"
pass "an Aurora Mac is not taken for Asahi because linux-aurora provides linux-asahi"

ambiguous() {
  local description=$1 message=$2
  run ensure
  (( status == 3 )) || fail "$description is ambiguous" "status $status: $(cat "$test_tmp/err")"
  [[ ! -e $record ]] || fail "$description writes no record" "$(cat "$record")"
  [[ ! -s $test_tmp/out ]] || fail "$description prints nothing on stdout" "$(cat "$test_tmp/out")"
  (( $(wc -l <"$test_tmp/err") == 1 )) || fail "$description says so in one line" "$(cat "$test_tmp/err")"
  grep -Fq "$message" "$test_tmp/err" || fail "$description names the reason" "$(cat "$test_tmp/err")"
  ! grep -q '^sudo:mktemp' "$calls" || fail "$description stages nothing" "$(cat "$calls")"
}
reset
TEST_INSTALLED="linux-aurora linux-asahi" ambiguous "both kernels installed" "both linux-aurora and linux-asahi are installed"
reset
TEST_INSTALLED="m1n1 grub" ambiguous "neither kernel installed" "neither linux-aurora nor linux-asahi is installed"
reset
printf 'linux-asahi\n' >"$marker"
ambiguous "an Asahi marker on an Aurora install" "names linux-asahi, but linux-aurora is installed"
reset
printf 'linux-aurora\n' >"$marker"
TEST_INSTALLED="$asahi_installed" ambiguous "an Aurora marker on an Asahi install" "names linux-aurora, but linux-asahi is installed"
reset
printf 'linux-aurora\n' >"$test_tmp/linked-marker"
ln -s "$test_tmp/linked-marker" "$marker"
ambiguous "a symlinked marker" "is not a readable regular file"
reset
mkdir "$marker"
ambiguous "a marker that is a directory" "is not a readable regular file"
rmdir "$marker"
for content in 'linux-aurora\n\n' 'linux-aurora \n' 'linux-aurora\r\n' 'Linux-Aurora\n' 'linux-foo\n' '' 'linux-aurora\nlinux-aurora\n'; do
  reset
  printf "$content" >"$marker"
  ambiguous "a malformed marker ($content)" "names neither linux-aurora nor linux-asahi"
done
if (( EUID != 0 )); then
  reset
  printf 'linux-aurora\n' >"$marker"
  chmod 000 "$marker"
  ambiguous "an unreadable marker" "is not a readable regular file"
  chmod 644 "$marker"
fi
pass "both kernels, neither, a contradicting, symlinked, malformed or unreadable marker record nothing and say why"

reset
TEST_APPLE_SILICON=0 run ensure
(( status == 0 )) || fail "a machine that is not a Mac is a no-op" "status $status: $(cat "$test_tmp/err")"
[[ ! -s $test_tmp/out && ! -s $test_tmp/err && ! -s $calls && ! -e $record ]] ||
  fail "a machine that is not a Mac is silent, takes no lock and writes nothing" "$(cat "$test_tmp/err" "$calls")"
pass "ensure does nothing on a machine that is not an Apple Silicon Mac"

reset
rm -rf "$state_dir"
run ensure
(( status == 0 )) || fail "a missing state directory is created" "status $status: $(cat "$test_tmp/err")"
[[ -d $state_dir && $(stat -c '%a' "$state_dir") == 755 ]] || fail "the state directory is created 0755"
expect_record "a Mac without a state directory is recorded" "$rc_record"
pass "a Mac without /var/lib/omarchy gets it along with its record"

reset
TEST_PACMAN_FAIL=1 run ensure
(( status == 2 )) || fail "unreadable package evidence stops ensure" "status $status: $(cat "$test_tmp/err")"
[[ ! -e $record ]] || fail "unreadable package evidence writes no record"
pass "a package database that cannot be listed stops ensure without writing"

# Existing records.
reset
write_record "$rc_record"
run ensure
(( status == 0 )) || fail "a valid rc record on an Aurora Mac passes" "status $status: $(cat "$test_tmp/err")"
[[ ! -s $test_tmp/out && ! -s $test_tmp/err ]] || fail "a valid record is silent" "$(cat "$test_tmp/err")"
! grep -q '^sudo:mktemp' "$calls" || fail "a valid record is not rewritten" "$(cat "$calls")"
cmp -s "$test_tmp/record-before" "$record" || fail "a valid record is left byte-identical"
reset
write_record "${rc_record}hold=%s\n" "qualifying a candidate by hand"
printf 'linux-aurora\n' >"$marker"
run ensure
(( status == 0 )) || fail "a held rc record passes" "status $status: $(cat "$test_tmp/err")"
cmp -s "$test_tmp/record-before" "$record" || fail "a held record is left byte-identical"
reset
write_record "$stable_record"
TEST_INSTALLED="$asahi_installed" run ensure
(( status == 0 )) || fail "a valid stable record on an Asahi Mac passes" "status $status: $(cat "$test_tmp/err")"
reset
write_record 'format=1\nchannel=rc\nkernel=linux-aurora'
run ensure
(( status == 0 )) || fail "a record without a final newline passes" "status $status: $(cat "$test_tmp/err")"
reset
write_record "${rc_record}hold=%s\n" "$(printf 'x%.0s' {1..200})"
run ensure
(( status == 0 )) || fail "a 200-character hold passes" "status $status: $(cat "$test_tmp/err")"
pass "valid records that match the evidence pass untouched"

invalid() {
  local description=$1 message=$2
  run ensure
  (( status == 2 )) || fail "$description stops ensure" "status $status: $(cat "$test_tmp/err")"
  grep -Fq "$message" "$test_tmp/err" || fail "$description is explained" "$(cat "$test_tmp/err")"
  [[ ! -s $test_tmp/out ]] || fail "$description prints nothing on stdout"
  ! grep -q '^sudo:mktemp' "$calls" || fail "$description is not replaced" "$(cat "$calls")"
  [[ -L $record || -d $record ]] || cmp -s "$test_tmp/record-before" "$record" || fail "$description is left byte-identical"
}
reset
write_record "$rc_record"
mv "$record" "$test_tmp/linked-record"
ln -s "$test_tmp/linked-record" "$record"
invalid "a symlinked record" "$record is not a regular file"
[[ -L $record ]] || fail "a symlinked record stays a symlink"
cmp -s "$test_tmp/record-before" "$test_tmp/linked-record" || fail "a symlinked record's target is untouched"
reset
mkdir "$record"
invalid "a record that is a directory" "$record is not a regular file"
rmdir "$record"
reset
write_record 'format=1\nchannel=rc\nkernel=linux-aurora\nchannel=rc\n'
invalid "a duplicate key" "$record repeats channel"
reset
write_record 'format=1\nchannel=rc\nkernel=linux-aurora\nsequence=4\n'
invalid "an unknown key" "$record has unknown key sequence"
reset
write_record 'format=1\nchannel=rc\nkernel=linux-aurora\nhold=\n'
invalid "an empty hold" "$record line 4 is not key=value"
reset
write_record 'format=1\nchannel=\nkernel=linux-aurora\n'
invalid "an empty channel" "$record line 2 is not key=value"
reset
write_record 'format=2\nchannel=rc\nkernel=linux-aurora\n'
invalid "an unsupported format" "$record has unsupported format 2"
reset
write_record 'format=1\nchannel=stable\nkernel=linux-aurora\n'
invalid "stable paired with linux-aurora" "$record pairs channel stable with kernel linux-aurora"
reset
write_record 'format=1\nchannel=edge\nkernel=linux-aurora\n'
invalid "an edge channel" "$record pairs channel edge with kernel linux-aurora"
reset
write_record 'format=1\nchannel=rc\nkernel=linux-asahi\n'
TEST_INSTALLED="$asahi_installed" invalid "rc paired with linux-asahi" "$record pairs channel rc with kernel linux-asahi"
reset
write_record "${rc_record}hold=%s\n" $'held\tby hand'
invalid "a control character in the hold" "$record line 4 is not key=value"
reset
write_record "${rc_record}hold=%s\n" "$(printf 'x%.0s' {1..201})"
invalid "a hold over 200 characters" "$record has a hold longer than 200 characters"
reset
write_record 'format=1\r\nchannel=rc\r\nkernel=linux-aurora\r\n'
invalid "CRLF line endings" "$record line 1 is not key=value"
reset
write_record 'format=1\n\nchannel=rc\nkernel=linux-aurora\n'
invalid "a blank line" "$record line 2 is not key=value"
reset
write_record 'format=1\nchannel=rc\n'
invalid "a missing kernel" "$record has no kernel"
reset
write_record 'channel=rc\nkernel=linux-aurora\n'
invalid "a missing format" "$record has no format"
reset
write_record ''
invalid "an empty record" "$record has no format"
reset
write_record "$rc_record"
chmod 0664 "$record"
invalid "a group-writable record" "$record is writable by users other than root"
reset
write_record "$rc_record"
chmod 0775 "$state_dir"
invalid "a group-writable state directory" "$state_dir is writable by users other than root"
chmod 0755 "$state_dir"
reset
write_record "$rc_record"
mv "$state_dir" "$root/var/lib/omarchy-real"
ln -s omarchy-real "$state_dir"
invalid "a symlinked state directory" "$state_dir is not a directory"
rm "$state_dir"
mv "$root/var/lib/omarchy-real" "$state_dir"
pass "malformed, unsafely stored or unsafely placed records stop ensure and are never replaced"

reset
chmod 0775 "$state_dir"
run ensure
(( status == 2 )) || fail "an unsafe state directory stops ensure before recording" "status $status"
[[ ! -e $record ]] || fail "nothing is recorded in an unsafe state directory"
chmod 0755 "$state_dir"
pass "an unsafe state directory stops ensure before anything is recorded"

reset
write_record "$rc_record"
TEST_INSTALLED="$asahi_installed" invalid "an rc record on an Asahi Mac" "$record names linux-aurora, but this Mac runs linux-asahi"
reset
write_record "$stable_record"
invalid "a stable record on an Aurora Mac" "$record names linux-asahi, but this Mac runs linux-aurora"
reset
write_record "$rc_record"
TEST_INSTALLED="linux-aurora linux-asahi" invalid "an rc record with both kernels" "$record names linux-aurora, which this Mac does not confirm: both linux-aurora and linux-asahi are installed"
reset
write_record "$rc_record"
printf 'linux-asahi\n' >"$marker"
invalid "an rc record with an Asahi marker" "names linux-asahi, but linux-aurora is installed"
pass "a record the evidence contradicts stops ensure and is not rewritten"

# status and current.
expect_output() {
  local description=$1 expected_status=$2
  shift 2
  printf "$@" >"$test_tmp/expected"
  (( status == expected_status )) || fail "$description exits $expected_status" "status $status: $(cat "$test_tmp/err")"
  cmp -s "$test_tmp/expected" "$test_tmp/out" || fail "$description prints exactly the expected output" "$(diff "$test_tmp/expected" "$test_tmp/out" || true)"
}
reset
write_record "$rc_record"
run status
expect_output "status of an rc record" 0 'channel=rc\nkernel=linux-aurora\n'
[[ ! -s $test_tmp/err ]] || fail "status of a valid record is quiet on stderr"
run current
expect_output "current of an rc record" 0 'rc\n'
[[ ! -s $test_tmp/err ]] || fail "current of a valid record is quiet on stderr"
reset
write_record "${rc_record}hold=%s\n" "waiting on the display fix"
run status
expect_output "status of a held record" 0 'channel=rc\nkernel=linux-aurora\nhold=waiting on the display fix\n'
run current
expect_output "current of a held record" 0 'rc\n'
reset
write_record "$stable_record"
TEST_INSTALLED="$asahi_installed" run status
expect_output "status of a stable record" 0 'channel=stable\nkernel=linux-asahi\n'
TEST_INSTALLED="$asahi_installed" run current
expect_output "current of a stable record" 0 'stable\n'
pass "status prints the record and current prints its channel"

reset
run status
expect_output "status without a record" 3 ''
run current
expect_output "current without a record" 0 'unknown\n'
[[ ! -s $test_tmp/err ]] || fail "current without a record is quiet" "$(cat "$test_tmp/err")"
[[ ! -s $calls && ! -e $record ]] || fail "status and current write nothing" "$(cat "$calls")"
reset
write_record 'format=1\nchannel=edge\nkernel=linux-aurora\n'
run status
expect_output "status of an invalid record" 2 ''
grep -Fq "$record pairs channel edge" "$test_tmp/err" || fail "status explains an invalid record on stderr" "$(cat "$test_tmp/err")"
run current
expect_output "current of an invalid record" 0 'unknown\n'
grep -Fq "$record pairs channel edge" "$test_tmp/err" || fail "current explains an invalid record on stderr" "$(cat "$test_tmp/err")"
reset
write_record "$rc_record"
TEST_INSTALLED="$asahi_installed" run status
expect_output "status of a contradicted record" 2 ''
TEST_INSTALLED="$asahi_installed" run current
expect_output "current of a contradicted record" 0 'unknown\n'
[[ ! -s $calls ]] || fail "status and current write nothing" "$(cat "$calls")"
cmp -s "$test_tmp/record-before" "$record" || fail "status and current leave the record alone"
pass "without a trustworthy record status exits 3 or 2 and current prints only unknown"

# hold and release.
reset
write_record "$rc_record"
run hold "qualifying aurora-packages-4439238 by hand"
(( status == 0 )) || fail "an rc record can be held" "status $status: $(cat "$test_tmp/err")"
expect_record "hold adds the reason" "${rc_record}hold=%s\n" "qualifying aurora-packages-4439238 by hand"
no_staging_left "a hold"
grep -Eq "^sudo:mv -f $state_dir/\.apple-silicon-channel\.[A-Za-z0-9]{6} $record\$" "$calls" || fail "a hold is renamed into place" "$(cat "$calls")"
run status
expect_output "status after a hold" 0 'channel=rc\nkernel=linux-aurora\nhold=qualifying aurora-packages-4439238 by hand\n'
run hold "a newer reason"
(( status == 0 )) || fail "a hold reason can be replaced" "status $status: $(cat "$test_tmp/err")"
expect_record "a second hold replaces the reason" "${rc_record}hold=%s\n" "a newer reason"
run release
(( status == 0 )) || fail "a held record can be released" "status $status: $(cat "$test_tmp/err")"
expect_record "release removes the hold" "$rc_record"
: >"$calls"
run release
(( status == 0 )) || fail "releasing an unheld record succeeds" "status $status: $(cat "$test_tmp/err")"
! grep -q '^sudo:mktemp' "$calls" || fail "releasing an unheld record rewrites nothing" "$(cat "$calls")"
expect_record "releasing an unheld record leaves it" "$rc_record"
pass "hold and release round-trip through a staged rename"

reset
run hold "no record yet"
(( status == 2 )) || fail "hold without a record is refused" "status $status"
grep -Fq "$record does not exist yet" "$test_tmp/err" || fail "hold without a record is explained" "$(cat "$test_tmp/err")"
[[ ! -e $record ]] || fail "hold without a record creates none"
run release
(( status == 2 )) && [[ ! -e $record ]] || fail "release without a record is refused and creates none" "status $status"
for command in "hold kept" release; do
  reset
  write_record 'format=1\nchannel=rc\nkernel=linux-aurora\nkernel=linux-aurora\n'
  run $command
  (( status == 2 )) || fail "$command on an invalid record is refused" "status $status"
  grep -Fq "$record repeats kernel" "$test_tmp/err" || fail "$command on an invalid record is explained" "$(cat "$test_tmp/err")"
  cmp -s "$test_tmp/record-before" "$record" || fail "$command does not replace an invalid record"
  ! grep -q '^sudo:mktemp' "$calls" || fail "$command stages nothing for an invalid record" "$(cat "$calls")"
done
pass "hold and release refuse a missing or invalid record without replacing it"

reset
write_record "$rc_record"
for reason in "" $'two\nlines' $'a\ttab' $'escape \e[31m' "$(printf 'x%.0s' {1..201})"; do
  run hold "$reason"
  (( status == 2 )) || fail "a bad hold reason is refused" "status $status for $(printf '%q' "$reason")"
  grep -Fq "a hold reason is one line of 1 to 200 printable ASCII characters" "$test_tmp/err" ||
    fail "a bad hold reason is explained" "$(cat "$test_tmp/err")"
  cmp -s "$test_tmp/record-before" "$record" || fail "a bad hold reason leaves the record"
done
run hold
(( status == 2 )) || fail "hold without a reason is a usage error" "status $status"
run hold one two
(( status == 2 )) || fail "hold with two reasons is a usage error" "status $status"
cmp -s "$test_tmp/record-before" "$record" || fail "usage errors leave the record"
pass "empty, multi-line, control-character and over-long hold reasons are refused"

# Interrupted writes.
reset
write_record "$rc_record"
TEST_MV_FAIL=1 run hold "never lands"
(( status == 2 )) || fail "a failed rename fails the hold" "status $status: $(cat "$test_tmp/err")"
grep -Fq "could not write $record" "$test_tmp/err" || fail "a failed rename is explained" "$(cat "$test_tmp/err")"
cmp -s "$test_tmp/record-before" "$record" || fail "a failed rename leaves the record byte-identical"
no_staging_left "a failed rename"
reset
TEST_MV_FAIL=1 run ensure
(( status == 2 )) || fail "a failed rename fails the first record" "status $status: $(cat "$test_tmp/err")"
[[ ! -e $record ]] || fail "a failed rename leaves no record"
no_staging_left "a failed first record"
pass "a write that fails at the rename leaves the record as it was and no staging file"

# The machine lock is the record's directory.
hold_lock() {
  local ready="$test_tmp/lock-ready"
  rm -f "$ready"
  (
    exec 9<"$state_dir"
    flock -x 9
    : >"$ready"
    exec sleep "$1"
  ) &
  holder_pid=$!
  for _ in $(seq 100); do
    [[ -e $ready ]] && return 0
    sleep 0.05
  done
  fail "the test lock holder started"
}
release_lock() {
  kill "$holder_pid" 2>/dev/null || true
  wait "$holder_pid" 2>/dev/null || true
  holder_pid=""
}

reset
write_record "$rc_record"
hold_lock 30
TEST_LOCK_TIMEOUT=0.3 run ensure
(( status == 2 )) || fail "a held machine lock makes ensure give up" "status $status: $(cat "$test_tmp/err")"
grep -Fq "could not lock $state_dir within 0.3s" "$test_tmp/err" || fail "a lock timeout is explained" "$(cat "$test_tmp/err")"
TEST_LOCK_TIMEOUT=0.3 run hold "while locked"
(( status == 2 )) || fail "a held machine lock makes hold give up" "status $status"
cmp -s "$test_tmp/record-before" "$record" || fail "a hold that cannot lock changes nothing"
XDG_RUNTIME_DIR="$test_tmp/another-session" TEST_LOCK_TIMEOUT=0.3 run ensure
(( status == 2 )) || fail "the machine lock does not depend on the session's runtime directory" "status $status"
TEST_LOCK_TIMEOUT=30 TEST_RUN_TIMEOUT=5 run current
expect_output "current while the lock is held" 0 'rc\n'
TEST_LOCK_TIMEOUT=30 TEST_RUN_TIMEOUT=5 run status
expect_output "status while the lock is held" 0 'channel=rc\nkernel=linux-aurora\n'
release_lock
pass "a held machine lock stops ensure and hold, while current and status still answer"

reset
hold_lock 2
SECONDS=0
run ensure
(( status == 0 )) || fail "ensure waits for the machine lock" "status $status: $(cat "$test_tmp/err")"
(( SECONDS >= 1 )) || fail "ensure waited for the holder to finish"
expect_record "ensure records once the lock is free" "$rc_record"
release_lock
pass "ensure waits for a lock that is released in time"

reset
write_record "$rc_record"
hold_lock 30
TEST_LOCK_TIMEOUT=0.3 run locked true
(( status == 2 )) || fail "a held machine lock makes locked give up" "status $status: $(cat "$test_tmp/err")"
grep -Fq "could not lock $state_dir within 0.3s" "$test_tmp/err" || fail "locked explains its timeout" "$(cat "$test_tmp/err")"
chmod 0775 "$state_dir"
for command in ensure "hold unsafe" release "locked true"; do
  TEST_LOCK_TIMEOUT=30 TEST_RUN_TIMEOUT=5 run $command
  (( status == 2 )) || fail "$command refuses a group-writable directory without waiting for its lock" "status $status"
  grep -Fq "$state_dir is writable by users other than root" "$test_tmp/err" || fail "$command explains the unsafe directory" "$(cat "$test_tmp/err")"
done
chmod 0755 "$state_dir"
mv "$state_dir" "$root/var/lib/omarchy-real"
ln -s omarchy-real "$state_dir"
for command in ensure "hold unsafe" release "locked true"; do
  TEST_LOCK_TIMEOUT=30 TEST_RUN_TIMEOUT=5 run $command
  (( status == 2 )) || fail "$command refuses a symlinked directory without waiting for its lock" "status $status"
  grep -Fq "$state_dir is not a directory" "$test_tmp/err" || fail "$command explains the symlinked directory" "$(cat "$test_tmp/err")"
done
rm "$state_dir"
mv "$root/var/lib/omarchy-real" "$state_dir"
release_lock
cmp -s "$test_tmp/record-before" "$record" || fail "refused lock attempts leave the record"
pass "a busy lock times out with exit 2, and an unsafe directory is refused before any wait"

# locked holds the directory lock for the command's whole life.
reset
write_record "$rc_record"
run locked bash -c 'flock -n "$1" true && echo free || echo busy
echo "locked=$OMARCHY_APPLE_SILICON_CHANNEL_LOCKED"
[[ /proc/$$/fd/$OMARCHY_APPLE_SILICON_CHANNEL_LOCK_FD -ef $1 ]] && echo "descriptor on the directory"
exit 7' _ "$state_dir"
expect_output "locked runs the command in its place" 7 'busy\nlocked=1\ndescriptor on the directory\n'
(
  invoke "$test_tmp/locked.out" "$test_tmp/locked.err" locked bash -c ': >"$1"; sleep 2' _ "$test_tmp/locked-ready"
) &
locked_pid=$!
for _ in $(seq 100); do
  [[ -e $test_tmp/locked-ready ]] && break
  sleep 0.05
done
[[ -e $test_tmp/locked-ready ]] || fail "the locked command started" "$(cat "$test_tmp/locked.err")"
! flock -n "$state_dir" true || fail "another process cannot lock the directory while the locked command runs"
TEST_LOCK_TIMEOUT=0.3 run hold "while an update runs"
(( status == 2 )) || fail "hold waits on a locked command" "status $status"
wait "$locked_pid"
flock -n "$state_dir" true || fail "the lock is free once the locked command ends"
cmp -s "$test_tmp/record-before" "$record" || fail "nothing lands while a locked command runs"
for command in ensure "hold nested" release "locked true"; do
  OMARCHY_APPLE_SILICON_CHANNEL_LOCKED=1 TEST_RUN_TIMEOUT=5 run $command
  (( status == 2 )) || fail "$command under a held channel lock refuses instead of waiting for itself" "status $status"
  grep -Fq "already held by a caller" "$test_tmp/err" || fail "$command explains the nested lock" "$(cat "$test_tmp/err")"
done
run locked
(( status == 2 )) || fail "locked without a command is a usage error" "status $status"
run locked bash "$helper" verify-locked
(( status == 0 )) || fail "a command run by locked verifies its lock" "status $status: $(cat "$test_tmp/err")"
run verify-locked
(( status == 2 )) || fail "verify-locked outside locked fails" "status $status"
for fd in "" 3x -1 " 3"; do
  OMARCHY_APPLE_SILICON_CHANNEL_LOCKED=1 OMARCHY_APPLE_SILICON_CHANNEL_LOCK_FD=$fd run verify-locked
  (( status == 2 )) || fail "verify-locked refuses descriptor '$fd'" "status $status"
  grep -Fq "is not a descriptor number" "$test_tmp/err" || fail "verify-locked explains descriptor '$fd'" "$(cat "$test_tmp/err")"
done
pass "locked holds an exclusive lock on the directory for the command's lifetime and never nests"

# Two first runs at once: both find no directory, one records, the other agrees.
reset
rm -rf "$state_dir"
gate="$test_tmp/install-gate"
for name in first second; do
  (
    TEST_INSTALL_GATE="$gate" invoke "$test_tmp/$name.out" "$test_tmp/$name.err" ensure &&
      echo 0 >"$test_tmp/$name.status" || echo $? >"$test_tmp/$name.status"
  ) &
done
wait
for name in first second; do
  [[ $(cat "$test_tmp/$name.status") == 0 ]] || fail "concurrent first run $name succeeds" "$(cat "$test_tmp/$name.err")"
done
(( $(grep -c '^sudo:install -d' "$calls") == 2 )) || fail "both first runs found no directory" "$(cat "$calls")"
(( $(grep -c '^sudo:mv -f' "$calls") == 1 )) || fail "exactly one concurrent first run writes the record" "$(cat "$calls")"
expect_record "concurrent first runs leave one valid record" "$rc_record"
no_staging_left "concurrent first runs"
rm -f "$gate".*
pass "two concurrent first runs end with exactly one valid record and no staging file"

# hold and release are policy: they work while the kernel evidence disagrees, and
# the next ensure still refuses the record.
reset
write_record "$rc_record"
TEST_INSTALLED="$asahi_installed" run hold "repairing the kernel by hand"
(( status == 0 )) || fail "a record the evidence contradicts can still be held" "status $status: $(cat "$test_tmp/err")"
expect_record "a hold on a contradicted record" "${rc_record}hold=%s\n" "repairing the kernel by hand"
TEST_INSTALLED="$asahi_installed" run ensure
(( status == 2 )) || fail "ensure refuses a held record the evidence contradicts" "status $status"
TEST_INSTALLED="$asahi_installed" run release
(( status == 0 )) || fail "a record the evidence contradicts can still be released" "status $status: $(cat "$test_tmp/err")"
expect_record "a release on a contradicted record" "$rc_record"
TEST_INSTALLED="$asahi_installed" run ensure
(( status == 2 )) || fail "ensure refuses a released record the evidence contradicts" "status $status"
pass "hold and release succeed on a contradicted record, and ensure still refuses it"

leftovers=$(find "$root" -type f ! -path "$record" ! -path "$marker")
[[ -z $leftovers && ! -e $root/run ]] || fail "no lock file or anything else is created beside the record" "$leftovers"
pass "the channel lock creates no file anywhere"

# The Aurora lane lives in its own file, so the format-1 record never changes shape.
lane_file="$state_dir/apple-silicon-aurora-lane"
descriptor_file="$state_dir/aurora-target.descriptor"
verify_hook="$root/usr/share/libalpm/hooks/01-omarchy-aurora-verify.hook"
pacman_conf="$root/etc/pacman.conf"
mkdir -p "$(dirname "$verify_hook")" "$root/etc"
accepted="4:$(printf 'a%.0s' {1..64})"
pending="5:$(printf 'b%.0s' {1..64})"

write_lane() {
  printf "$@" >"$lane_file"
  chmod 0644 "$lane_file"
  cp "$lane_file" "$test_tmp/lane-before"
}

expect_lane() {
  local description=$1
  shift
  printf "$@" >"$test_tmp/expected-lane"
  cmp -s "$test_tmp/expected-lane" "$lane_file" || fail "$description" "$(diff "$test_tmp/expected-lane" "$lane_file" || true)"
  [[ $(stat -c '%a' "$lane_file") == 644 ]] || fail "$description: the lane file is 0644"
}

lane_reset() {
  reset
  rm -f "$lane_file" "$descriptor_file" "$state_dir"/.apple-silicon-aurora-lane.* "$state_dir"/.aurora-target.descriptor.*
  write_record "$rc_record"
  printf '[options]\nArchitecture = aarch64\n\n[omarchy]\nServer = https://example.test\n' >"$pacman_conf"
  : >"$verify_hook"
}

run_under_update_lock() {
  set +e
  XDG_RUNTIME_DIR="$test_tmp" TEST_CALLS="$calls" TEST_PACMAN_CALLS="$pacman_calls" \
    TEST_INSTALLED="${TEST_INSTALLED-$aurora_installed}" \
    OMARCHY_APPLE_SILICON_CHANNEL_ROOT="$root" \
    OMARCHY_APPLE_SILICON_CHANNEL_TESTING=1 \
    OMARCHY_APPLE_SILICON_CHANNEL_LOCK_TIMEOUT="${TEST_LOCK_TIMEOUT:-10}" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    timeout "${TEST_RUN_TIMEOUT:-30}" "$ROOT/bin/omarchy-update-lock" run bash "$helper" "$@" >"$test_tmp/out" 2>"$test_tmp/err"
  status=$?
  set -e
}

lane_reset
run current
expect_output "current of an rc record without a lane file" 0 'rc\n'
run lane
expect_output "lane without a lane file" 0 'lane=rc\n'
write_lane 'format=1\nlane=edge\nedge_accepted=%s\n' "$accepted"
run current
expect_output "current of an rc record whose lane is edge" 0 'edge\n'
[[ ! -s $test_tmp/err ]] || fail "current of an edge lane is quiet" "$(cat "$test_tmp/err")"
run lane
expect_output "lane of an edge Mac" 0 'lane=edge\nedge_accepted=%s\n' "$accepted"
run status
expect_output "status still prints only the record" 0 'channel=rc\nkernel=linux-aurora\n'
write_lane 'format=1\nlane=rc\nswitch=rc\nedge_accepted=%s\nedge_pending=%s\n' "$accepted" "$pending"
run lane
expect_output "lane prints every field" 0 'lane=rc\nswitch=rc\nedge_accepted=%s\nedge_pending=%s\n' "$accepted" "$pending"
run current
expect_output "current of an rc lane" 0 'rc\n'
reset
write_record "$stable_record"
write_lane 'format=1\nlane=edge\n'
TEST_INSTALLED="$asahi_installed" run current
expect_output "a stable record ignores a lane file" 0 'stable\n'
TEST_INSTALLED="$asahi_installed" run lane
expect_output "the lane of a stable Mac is rc" 0 'lane=rc\n'
pass "current reports edge only for an rc record whose lane file says so, and status keeps the record's shape"

lane_invalid() {
  local description=$1 message=$2
  run current
  expect_output "current with $description" 0 'unknown\n'
  grep -Fq "$message" "$test_tmp/err" || fail "current explains $description" "$(cat "$test_tmp/err")"
  run lane
  (( status == 2 )) || fail "lane refuses $description" "status $status"
  grep -Fq "$message" "$test_tmp/err" || fail "lane explains $description" "$(cat "$test_tmp/err")"
}
lane_reset
write_lane 'format=2\nlane=edge\n'
lane_invalid "format 2" "$lane_file has unsupported format 2"
write_lane 'format=1\nlane=edge\nsequence=4\n'
lane_invalid "an unknown key" "$lane_file has unknown key sequence"
write_lane 'format=1\nlane=stable\n'
lane_invalid "a stable lane" "$lane_file has lane stable, which is neither rc nor edge"
write_lane 'format=1\nlane=edge\nswitch=dev\n'
lane_invalid "a dev switch" "$lane_file has switch dev, which is neither rc nor edge"
write_lane 'format=1\nlane=edge\nlane=rc\n'
lane_invalid "a repeated key" "$lane_file repeats lane"
write_lane 'format=1\n'
lane_invalid "no lane" "$lane_file has no lane"
write_lane 'lane=edge\n'
lane_invalid "no format" "$lane_file has no format"
for value in "04:$(printf 'a%.0s' {1..64})" "4:$(printf 'a%.0s' {1..63})" "4:$(printf 'A%.0s' {1..64})" "1234567890:$(printf 'a%.0s' {1..64})" "0:$(printf 'a%.0s' {1..64})"; do
  write_lane 'format=1\nlane=edge\nedge_accepted=%s\n' "$value"
  lane_invalid "edge_accepted=$value" "$lane_file has a malformed edge_accepted"
done
write_lane 'format=1\r\nlane=edge\r\n'
lane_invalid "CRLF" "$lane_file line 1 is not key=value"
write_lane 'format=1\nlane=edge\n'
chmod 0664 "$lane_file"
lane_invalid "a group-writable lane file" "$lane_file is writable by users other than root"
rm -f "$lane_file"
ln -s "$test_tmp/lane-before" "$lane_file"
lane_invalid "a symlinked lane file" "$lane_file is not a regular file"
rm -f "$lane_file"
cmp -s "$test_tmp/record-before" "$record" || fail "reading a lane never touches the record"
pass "a malformed or unsafely stored lane file makes current unknown and lane refuse, naming the file"

# lane-write and stage-descriptor are the updater's, under a lock it already holds.
lane_reset
write_lane 'format=1\nlane=edge\nswitch=edge\nedge_accepted=%s\n' "$accepted"
run lane-write "edge_pending=$pending"
(( status == 2 )) || fail "lane-write outside the channel lock is refused" "status $status"
cmp -s "$test_tmp/lane-before" "$lane_file" || fail "a refused lane-write changes nothing"
run locked bash "$helper" lane-write "edge_pending=$pending"
(( status == 0 )) || fail "lane-write under the channel lock" "status $status: $(cat "$test_tmp/err")"
expect_lane "lane-write adds a field and keeps the others" 'format=1\nlane=edge\nswitch=edge\nedge_accepted=%s\nedge_pending=%s\n' "$accepted" "$pending"
grep -Eq "^sudo:mv -f $state_dir/\.apple-silicon-aurora-lane\.[A-Za-z0-9]{6} $lane_file\$" "$calls" || fail "the lane file is renamed into place" "$(cat "$calls")"
run locked bash "$helper" lane-write "edge_accepted=$pending" edge_pending= switch=
expect_lane "lane-write clears fields given empty" 'format=1\nlane=edge\nedge_accepted=%s\n' "$pending"
for bad in lane= lane=stable switch=dev edge_pending=07:x hold=x nonsense; do
  cp "$lane_file" "$test_tmp/lane-before"
  run locked bash "$helper" lane-write "$bad"
  (( status == 2 )) || fail "lane-write refuses $bad" "status $status"
  cmp -s "$test_tmp/lane-before" "$lane_file" || fail "lane-write $bad changes nothing"
done
cmp -s "$test_tmp/record-before" "$record" || fail "lane-write never touches the record"
! compgen -G "$state_dir/.apple-silicon-aurora-lane.*" >/dev/null || fail "lane-write leaves no staging file"

printf 'format=1\nchannel=aurora\n' >"$test_tmp/descriptor"
run stage-descriptor "$test_tmp/descriptor"
(( status == 2 )) && [[ ! -e $descriptor_file ]] || fail "stage-descriptor outside the channel lock is refused" "status $status"
run locked bash "$helper" stage-descriptor "$test_tmp/descriptor"
(( status == 0 )) || fail "stage-descriptor under the channel lock" "status $status: $(cat "$test_tmp/err")"
cmp -s "$test_tmp/descriptor" "$descriptor_file" && [[ $(stat -c '%a' "$descriptor_file") == 644 ]] ||
  fail "the descriptor is staged byte for byte, 0644"
: >"$calls"
run locked bash "$helper" stage-descriptor "$test_tmp/descriptor"
! grep -q '^sudo:mktemp' "$calls" || fail "an identical descriptor is not staged again" "$(cat "$calls")"
pass "lane-write and stage-descriptor need the channel lock and write through a staged rename, never the record"

# switch: every refusal is decided under the lock, before anything is written.
switch_refused() {
  local description=$1 message=$2
  shift 2
  run_under_update_lock switch "$@"
  (( status == 2 )) || fail "$description is refused" "status $status: $(cat "$test_tmp/out" "$test_tmp/err")"
  grep -Fq "$message" "$test_tmp/err" || fail "$description is explained" "$(cat "$test_tmp/err")"
  if [[ -e $test_tmp/lane-before ]]; then
    cmp -s "$test_tmp/lane-before" "$lane_file" || fail "$description leaves the lane file" "$(cat "$lane_file" 2>&1)"
  fi
  [[ ! -e $record ]] || cmp -s "$test_tmp/record-before" "$record" || fail "$description leaves the record"
}
lane_reset
rm -f "$test_tmp/lane-before"
run switch edge
(( status == 2 )) && [[ ! -e $lane_file ]] || fail "switch without the update lock is refused" "status $status"
grep -Fq "the update lock is not held" "$test_tmp/err" || fail "switch explains the missing update lock" "$(cat "$test_tmp/err")"
write_record "${rc_record}hold=%s\n" "qualifying by hand"
switch_refused "a held Mac" "this Mac's channel is held (qualifying by hand)" edge
write_record "$stable_record"
TEST_INSTALLED="$asahi_installed" switch_refused "a stable Mac" "this Mac runs linux-asahi on stable" edge
write_record 'format=1\nchannel=rc\nkernel=linux-aurora\nkernel=linux-aurora\n'
switch_refused "an invalid record" "$record repeats kernel" rc
write_record "$rc_record"
TEST_INSTALLED="$asahi_installed" switch_refused "a contradicted record" "this Mac runs linux-asahi" edge
rm -f "$record"
switch_refused "a Mac without a record" "$record does not exist yet" edge
write_record "$rc_record"
printf '[options]\nIgnorePkg = linux-aurora\n' >"$pacman_conf"
switch_refused "an IgnorePkg hold on linux-aurora" "IgnorePkg/IgnoreGroup in /etc/pacman.conf holds linux-aurora" edge
mkdir -p "$root/etc/pacman.d"
printf 'IgnorePkg = linux-aurora-headers\n' >"$root/etc/pacman.d/holds.conf"
printf '[options]\nArchitecture = aarch64\nInclude = %s\n' "$root/etc/pacman.d/holds.conf" >"$pacman_conf"
switch_refused "an IgnorePkg hold in an included file" "holds linux-aurora-headers" edge
printf '[options]\nIgnoreGroup = asahi-*\r\n' >"$pacman_conf"
TEST_GROUPS="m1n1-aurora:asahi-boot" switch_refused "an IgnoreGroup glob on a group m1n1-aurora is in" "holds m1n1-aurora" rc
printf '[options]\nInclude = %s\n' "$root/etc/pacman.d/missing.conf" >"$pacman_conf"
switch_refused "a pacman configuration pacman cannot read" "pacman cannot read /etc/pacman.conf" edge
printf '[options]\n#IgnorePkg = linux-aurora\n[extra]\nIgnorePkg = linux-aurora-headers\n' >"$pacman_conf"
rm -f "$verify_hook"
switch_refused "edge without the verification hook" "does not install $verify_hook" edge
: >"$verify_hook"
write_lane 'format=1\nlane=edge\nsurprise=1\n'
switch_refused "a malformed lane file" "has unknown key surprise; omarchy-apple-silicon-channel reset-rc" rc
rm -f "$lane_file" "$test_tmp/lane-before"
[[ ! -e $lane_file ]] || fail "refusals write no lane file"
pass "switch needs the update lock and refuses holds, stable, invalid records, pacman holds as pacman reads them, a missing hook and a malformed lane without writing"

lane_reset
printf '[options]\nIgnoreGroup = m1n1-*\n' >"$pacman_conf"
TEST_GROUPS="m1n1-aurora:asahi-boot" run_under_update_lock switch edge
(( status == 0 )) || fail "an IgnoreGroup pattern matching no group of the Aurora packages holds nothing" "status $status: $(cat "$test_tmp/err")"
lane_reset
run_under_update_lock switch edge
(( status == 0 )) || fail "an rc Mac switches to edge" "status $status: $(cat "$test_tmp/err")"
expect_lane "switch edge writes the requested lane" 'format=1\nlane=edge\nswitch=edge\n'
cmp -s "$test_tmp/record-before" "$record" || fail "switch leaves the format-1 record byte-identical"
run current
expect_output "current right after switching to edge" 0 'edge\n'
: >"$calls"
run_under_update_lock switch edge
(( status == 0 )) && grep -Fq "already follows edge" "$test_tmp/out" || fail "repeating a pending switch is a no-op" "$(cat "$test_tmp/out" "$test_tmp/err")"
! grep -q '^sudo:mktemp' "$calls" || fail "repeating a pending switch writes nothing" "$(cat "$calls")"
write_lane 'format=1\nlane=edge\nswitch=edge\nedge_accepted=%s\nedge_pending=%s\n' "$accepted" "$pending"
run_under_update_lock switch rc
(( status == 0 )) || fail "an opposing switch replaces a pending one" "status $status: $(cat "$test_tmp/err")"
expect_lane "the last request wins and edge history stays" 'format=1\nlane=rc\nswitch=rc\nedge_accepted=%s\nedge_pending=%s\n' "$accepted" "$pending"
run_under_update_lock switch edge
expect_lane "switching back again" 'format=1\nlane=edge\nswitch=edge\nedge_accepted=%s\nedge_pending=%s\n' "$accepted" "$pending"
write_lane 'format=1\nlane=edge\nedge_accepted=%s\n' "$accepted"
run_under_update_lock switch edge
grep -Fq "already follows edge" "$test_tmp/out" && cmp -s "$test_tmp/lane-before" "$lane_file" || fail "a Mac settled on edge stays as it is"
lane_reset
run_under_update_lock switch rc
grep -Fq "already follows rc" "$test_tmp/out" && [[ ! -e $lane_file ]] || fail "an rc Mac asking for rc writes nothing" "$(cat "$test_tmp/out")"
printf '[omarchy-aurora]\nServer = https://github.com/maralcbr/omarchy-pkgs/releases/download/aurora-edge-7\n' >>"$pacman_conf"
run_under_update_lock switch rc
expect_lane "rc on a section left on edge is a switch back" 'format=1\nlane=rc\nswitch=rc\n'
pass "switch records lane and switch, the last request wins, repeats are no-ops, and rc still returns a section left on edge"

# A hold that commits while switch waits for the lock is read under it.
lane_reset
hold_lock 2
(
  sleep 0.5
  printf 'hold=landed while switch waited\n' >>"$record"
) &
run_under_update_lock switch edge
wait
release_lock
(( status == 2 )) && grep -Fq "held (landed while switch waited)" "$test_tmp/err" ||
  fail "a hold that lands while switch waits for the lock refuses the switch" "status $status: $(cat "$test_tmp/err")"
[[ ! -e $lane_file ]] || fail "a switch refused under the lock writes nothing"
pass "a hold that lands while switch waits for the channel lock stops it"

# reset-rc returns a Mac to rc whatever the lane says, keeping what edge accepted.
lane_reset
write_lane 'format=1\nlane=edge\nedge_accepted=%s\nedge_pending=%s\n' "$accepted" "$pending"
run reset-rc
(( status == 0 )) || fail "reset-rc on an edge Mac" "status $status: $(cat "$test_tmp/err")"
expect_lane "reset-rc writes rc and keeps the edge history" 'format=1\nlane=rc\nswitch=rc\nedge_accepted=%s\nedge_pending=%s\n' "$accepted" "$pending"
cmp -s "$test_tmp/record-before" "$record" || fail "reset-rc leaves the record"
write_lane 'format=2\nlane=edge\n'
run reset-rc
(( status == 0 )) || fail "reset-rc repairs a malformed lane file" "status $status: $(cat "$test_tmp/err")"
grep -Fq "without its edge history" "$test_tmp/err" || fail "reset-rc says what a repair loses" "$(cat "$test_tmp/err")"
expect_lane "reset-rc starts a malformed lane again from rc" 'format=1\nlane=rc\nswitch=rc\n'
rm -f "$lane_file"
mkdir "$lane_file"
run reset-rc
(( status == 2 )) && [[ -d $lane_file ]] || fail "reset-rc refuses a lane path that is not a file" "status $status"
rmdir "$lane_file"
write_record "${rc_record}hold=%s\n" "frozen"
run reset-rc
(( status == 0 )) && grep -Fq "held (frozen)" "$test_tmp/out" || fail "reset-rc on a held Mac records rc and says the hold still applies" "$(cat "$test_tmp/out" "$test_tmp/err")"
write_record "$stable_record"
rm -f "$lane_file"
TEST_INSTALLED="$asahi_installed" run reset-rc
(( status == 2 )) && [[ ! -e $lane_file ]] || fail "reset-rc refuses a stable Mac" "status $status"
pass "reset-rc writes lane=rc switch=rc, keeps edge history, repairs malformed content and refuses what is not a file"

# held reports what pacman holds, the way the updater warns about it.
lane_reset
printf 'IgnorePkg = linux-aurora*\n' >"$root/etc/pacman.d/holds.conf"
printf '[options]\nInclude = %s\nIgnoreGroup = kernels\n' "$root/etc/pacman.d/holds.conf" >"$pacman_conf"
TEST_GROUPS="m1n1-aurora:kernels" run held
expect_output "held through an Include and a group" 0 'linux-aurora linux-aurora-headers m1n1-aurora\n'
printf '[options]\nIgnoreGroup = linux-aurora\n' >"$pacman_conf"
run held
expect_output "an IgnoreGroup naming a package, not a group" 0 '\n'
pass "held follows Include and matches IgnoreGroup against real groups, not package names"
