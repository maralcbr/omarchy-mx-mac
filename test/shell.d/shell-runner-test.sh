#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

runner="$ROOT/test/shell"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# --- Sharding the real suite --------------------------------------------------

mapfile -t all_files < <("$runner" --list)
(( ${#all_files[@]} > 1 )) || fail "the runner lists the suite"
[[ " ${all_files[*]} " != *" test/shell.d/base-test.sh "* ]] || fail "the runner never lists the test base"

for count in 1 2 3 4 7; do
  dealt=()
  smallest=${#all_files[@]} largest=0
  for (( shard = 1; shard <= count; shard++ )); do
    mapfile -t shard_files < <("$runner" --list --shard "$shard/$count")
    dealt+=("${shard_files[@]}")
    if (( ${#shard_files[@]} < smallest )); then
      smallest=${#shard_files[@]}
    fi
    if (( ${#shard_files[@]} > largest )); then
      largest=${#shard_files[@]}
    fi
  done
  [[ -z $(printf '%s\n' "${dealt[@]}" | sort | uniq -d) ]] ||
    fail "no file lands in two of $count shards" "$(printf '%s\n' "${dealt[@]}" | sort | uniq -d)"
  [[ $(printf '%s\n' "${dealt[@]}" | sort) == "$(printf '%s\n' "${all_files[@]}" | sort)" ]] ||
    fail "$count shards together run every file"
  (( largest - smallest <= 1 )) || fail "$count shards are dealt evenly ($smallest..$largest files)"
done
pass "shards 1..N together select every file exactly once, evenly"

# Membership is byte order, not locale collation, so every runner deals the same
# shards; only the order the files run in follows the locale.
c_shard=$(LC_ALL=C "$runner" --list --shard 2/4 | LC_ALL=C sort)
for locale in C.UTF-8 en_US.UTF-8 POSIX; do
  [[ $(LC_ALL=$locale "$runner" --list --shard 2/4 2>/dev/null | LC_ALL=C sort) == "$c_shard" ]] ||
    fail "shard membership does not depend on the locale ($locale)"
done
pass "shard membership does not depend on the locale"

for invalid in 0/4 5/4 1/0 4 a/b 1/4/2 ''; do
  set +e
  "$runner" --list --shard "$invalid" >/dev/null 2>&1
  status=$?
  set -e
  (( status == 2 )) || fail "an invalid shard is refused: '$invalid'"
done
for invalid in 0 -1 x ''; do
  set +e
  "$runner" --list --jobs "$invalid" >/dev/null 2>&1
  status=$?
  set -e
  (( status == 2 )) || fail "an invalid job count is refused: '$invalid'"
done
set +e
"$runner" --list --shard >/dev/null 2>&1
status=$?
set -e
(( status == 2 )) || fail "a shard option without a value is refused"
pass "invalid shard and job options are refused"

# --- Running a stand-in suite -------------------------------------------------

suite="$test_tmp/suite"
mkdir -p "$suite/test/shell.d"
cp "$runner" "$ROOT/test/require-modern-bash" "$suite/test/"
cp "$ROOT/test/shell.d/base-test.sh" "$suite/test/shell.d/"

write_test() {
  local name=$1

  {
    printf '#!/bin/bash\nset -euo pipefail\n'
    cat
  } >"$suite/test/shell.d/$name-test.sh"
}

write_test alpha <<'SH'
echo "alpha line 1"
sleep 0.2
echo "alpha line 2"
SH
write_test bravo <<'SH'
echo "bravo output"
echo "bravo error" >&2
exit 3
SH
# The two rendezvous files pass only when they run at the same time: each
# waits for the other's marker, which a one-at-a-time runner never provides.
write_test charlie <<SH
touch "$test_tmp/charlie.started"
for (( i = 0; i < 100; i++ )); do
  [[ -e $test_tmp/delta.started ]] && { echo "charlie met delta"; exit 0; }
  sleep 0.1
done
echo "charlie ran alone"
exit 1
SH
write_test delta <<SH
touch "$test_tmp/delta.started"
for (( i = 0; i < 100; i++ )); do
  [[ -e $test_tmp/charlie.started ]] && { echo "delta met charlie"; exit 0; }
  sleep 0.1
done
echo "delta ran alone"
exit 1
SH
write_test echo <<SH
printf '%s\n' "\${XDG_RUNTIME_DIR:-unset}" >"$test_tmp/echo.runtime"
if [[ -r /proc/\$\$/status ]]; then
  ignored=\$(awk '/^SigIgn:/ { print \$2 }' /proc/\$\$/status)
  (( (16#\$ignored & 2) == 0 )) || { echo "SIGINT is ignored"; exit 1; }
fi
[[ ! -t 0 ]] || { echo "stdin is a terminal"; exit 1; }
echo "echo checked its environment"
SH
write_test foxtrot <<SH
printf '%s\n' "\${XDG_RUNTIME_DIR:-unset}" >"$test_tmp/foxtrot.runtime"
SH

run_suite() {
  set +e
  output=$(env -u XDG_RUNTIME_DIR "$suite/test/shell" "$@" 2>&1)
  status=$?
  set -e
}

# Each file's output must follow its own header as one block, which ends at the
# next header or at the blank line before the summary.
file_block() {
  local name=$1

  awk -v header="==> test/shell.d/$name-test.sh" '
    index($0, header) == 1 { on = 1; next }
    /^==> / || !NF { on = 0 }
    on && !/^--> / { print }
  ' <<<"$output"
}

run_suite --jobs 3
(( status == 1 )) || fail "a parallel run fails when one file fails" "$output"
[[ $output == *$'\n1 of 6 test files failed:\n  test/shell.d/bravo-test.sh'* ]] ||
  fail "a parallel run names exactly the failing file" "$output"
[[ $output == *'--> test/shell.d/bravo-test.sh failed with exit status 3'* ]] ||
  fail "a parallel run reports the failing file's status" "$output"
for name in alpha bravo charlie delta echo foxtrot; do
  [[ $(grep -c "^==> test/shell.d/$name-test.sh " <<<"$output") == 1 ]] ||
    fail "a parallel run prints $name once" "$output"
done
[[ $(file_block alpha) == $'alpha line 1\nalpha line 2' ]] ||
  fail "a parallel run keeps each file's output together" "$output"
[[ $(file_block bravo) == $'bravo output\nbravo error' ]] ||
  fail "a parallel run keeps a file's stderr with its output" "$output"
[[ $(file_block charlie) == "charlie met delta" && $(file_block delta) == "delta met charlie" ]] ||
  fail "a parallel run runs files at the same time" "$output"
[[ $(file_block echo) == "echo checked its environment" ]] ||
  fail "a parallel file runs with default SIGINT handling and no terminal input" "$output"
echo_runtime=$(<"$test_tmp/echo.runtime")
foxtrot_runtime=$(<"$test_tmp/foxtrot.runtime")
[[ $echo_runtime != unset && $foxtrot_runtime != unset && $echo_runtime != "$foxtrot_runtime" ]] ||
  fail "each parallel file gets its own runtime directory" "$echo_runtime $foxtrot_runtime"
[[ ! -e $echo_runtime ]] || fail "the runner removes the private runtime directories"
pass "a parallel run keeps per-file output whole and fails for any failing file"

set +e
output=$(XDG_RUNTIME_DIR="$test_tmp/session" "$suite/test/shell" --jobs 2 "$suite/test/shell.d/foxtrot-test.sh" "$suite/test/shell.d/alpha-test.sh" 2>&1)
status=$?
set -e
(( status == 0 )) || fail "a passing parallel run succeeds" "$output"
[[ $output == *$'\nAll 2 test files passed.' ]] || fail "a passing parallel run reports the count" "$output"
[[ $(<"$test_tmp/foxtrot.runtime") == "$test_tmp/session" ]] ||
  fail "a parallel run keeps a session's own runtime directory"
pass "a passing parallel run succeeds and keeps a session's runtime directory"

run_suite "$suite/test/shell.d/alpha-test.sh" "$suite/test/shell.d/bravo-test.sh"
(( status == 1 )) || fail "a sequential run fails when one file fails" "$output"
[[ $output == $'==> test/shell.d/alpha-test.sh\nalpha line 1\nalpha line 2\n==> test/shell.d/bravo-test.sh\nbravo output\nbravo error\n\n1 of 2 test files failed:\n  test/shell.d/bravo-test.sh' ]] ||
  fail "the default run keeps its sequential output" "$output"
pass "the default run is unchanged: sequential, in order, every failure reported"

# Without the rendezvous pair: alpha, bravo, echo, foxtrot deal alpha and echo
# to shard 1 and bravo and foxtrot to shard 2.
rm -f "$suite/test/shell.d/charlie-test.sh" "$suite/test/shell.d/delta-test.sh"
run_suite --jobs 4 --shard 1/2
(( status == 0 )) || fail "a shard runs only its own files" "$output"
[[ $(grep -c '^==> ' <<<"$output") == 2 ]] || fail "shard 1 of 2 of four files runs two" "$output"
[[ $output != *bravo* ]] || fail "shard 1 of 2 leaves bravo to shard 2" "$output"
run_suite --shard 2/2
(( status == 1 )) && [[ $output == *'bravo-test.sh'* ]] || fail "shard 2 of 2 runs bravo" "$output"
pass "a shard runs only its files and still fails for a failing one"

run_suite --shard 3/9 "$suite/test/shell.d/alpha-test.sh"
(( status == 0 )) && [[ $output == 'Shard 3/9 selects no test files.' ]] ||
  fail "an empty shard passes and says so" "$output"
pass "an empty shard passes and says so"

# Interrupting a parallel run stops the files it started, children included,
# even a child that ignores TERM, before it removes their runtime directories.
# Further signals during that cleanup, as from a second Ctrl-C, are ignored.
write_test golf <<SH
bash -c 'trap "" TERM; while :; do sleep 0.1; done' &
echo "\$!" >"$test_tmp/golf.child"
echo "\$XDG_RUNTIME_DIR" >"$test_tmp/golf.runtime"
wait
SH

# A killed child can linger as a zombie until init reaps it; that is not alive.
alive() {
  local stat

  stat=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  [[ ${stat##*) } != Z* ]]
}

interrupt_run() {
  local description=$1 signal
  shift

  rm -f "$test_tmp/golf.child" "$test_tmp/golf.runtime"
  env -u XDG_RUNTIME_DIR "$suite/test/shell" --jobs 2 "$suite/test/shell.d/golf-test.sh" "$suite/test/shell.d/alpha-test.sh" >/dev/null 2>&1 &
  runner_pid=$!
  for (( i = 0; i < 100; i++ )); do
    [[ -s $test_tmp/golf.child && -s $test_tmp/golf.runtime ]] && break
    sleep 0.1
  done
  golf_child=$(<"$test_tmp/golf.child")
  golf_runtime=$(<"$test_tmp/golf.runtime")
  [[ -d $golf_runtime ]] || fail "the interrupted file had a runtime directory ($description)"
  interrupted_at=$SECONDS
  for signal in "$@"; do
    kill "-$signal" "$runner_pid" 2>/dev/null || true
    sleep 0.3
  done
  set +e
  wait "$runner_pid"
  status=$?
  set -e
  (( status == 143 )) || fail "an interrupted parallel run exits with the first signal's status ($description)" "$status"
  (( SECONDS - interrupted_at <= 10 )) || fail "an interrupted parallel run stops within its bounded wait ($description)"
  for (( i = 0; i < 20; i++ )); do
    alive "$golf_child" || break
    sleep 0.1
  done
  if alive "$golf_child"; then
    kill -KILL "$golf_child" 2>/dev/null || true
    fail "an interrupted parallel run stops a child that ignores TERM ($description)"
  fi
  [[ ! -e $golf_runtime ]] || fail "an interrupted parallel run removes the runtime directories ($description)"
}

interrupt_run "one TERM" TERM
pass "an interrupted parallel run stops every process its files started, then cleans up"

interrupt_run "TERM, TERM, INT" TERM TERM INT
pass "further signals during cleanup do not cut it short"
