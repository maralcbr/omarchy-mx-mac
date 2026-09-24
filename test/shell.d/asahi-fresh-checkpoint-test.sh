#!/bin/bash
#
# A fresh install that finds an interrupted install's checkpoint from a
# different user or release names the fields that differ, with both values,
# and how to resume, instead of one message for every case.

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

installer="$ROOT/bin/omarchy-install-asahi-fresh"

grep -Fq '[[ $(<"$state_dir/release") == "$expected_state" ]] || checkpoint_mismatch "$(<"$state_dir/release")" "$expected_state"' "$installer" ||
  fail "a mismatched checkpoint is explained by checkpoint_mismatch"
function_body=$(awk '/^checkpoint_mismatch\(\) \{$/,/^}$/' "$installer")
[[ -n $function_body ]] || fail "the installer defines checkpoint_mismatch"
eval "$function_body"

source_a=1111111111111111111111111111111111111111
source_b=2222222222222222222222222222222222222222
package_a=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
package_b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

state() {
  printf '%s\n' "$1" "sequence=$2" "tag=$3" "source_commit=$4" "package_source_commit=$5"
}

explain() {
  local status=0
  output=$( (checkpoint_mismatch "$1" "$2") 2>&1) || status=$?
  (( status == 1 )) || fail "a mismatched checkpoint stops the install" "exit status $status"
}

expect_line() {
  grep -Fxq -- "$1" <<<"$output" || fail "$2" "$output"
}

reject_line() {
  ! grep -Fq -- "$1" <<<"$output" || fail "$2" "$output"
}

# Issue #85: the same user resumes on a day when the channel has moved on.
explain "$(state user=marcelo 25 asahi-quattro-fe8d2bf8 "$source_a" "$package_a")" \
  "$(state user=marcelo 29 asahi-quattro-2afd2ef2 "$source_b" "$package_b")"
expect_line "Error: An incomplete installation was started with a different release sequence, release tag, release source commit, package source commit" \
  "a release change names every release field that differs"
expect_line "  release sequence: recorded 25, this run 29" "the sequence shows both values"
expect_line "  release tag: recorded asahi-quattro-fe8d2bf8, this run asahi-quattro-2afd2ef2" "the tag shows both values"
expect_line "  release source commit: recorded $source_a, this run $source_b" "the source commit shows both values"
expect_line "  package source commit: recorded $package_a, this run $package_b" "the package source commit shows both values"
expect_line "To resume it, run the installer again with --release-tag asahi-quattro-fe8d2bf8, the release that started it." \
  "a release change says how to resume with the recorded release"
reject_line "  user:" "an unchanged user is not reported as different"
reject_line "--user" "an unchanged user needs no --user advice"
pass "a moved release channel names the release fields and the release to resume with"

explain "$(state user=marcelo 29 asahi-quattro-2afd2ef2 "$source_b" "$package_b")" \
  "$(state user=mina 29 asahi-quattro-2afd2ef2 "$source_b" "$package_b")"
expect_line "Error: An incomplete installation was started with a different user" "a user change names the user"
expect_line "  user: recorded marcelo, this run mina" "the user shows both names"
expect_line "To resume it, run the installer again with --user marcelo." "a user change says how to resume"
reject_line "  release" "an unchanged release is not reported as different"
reject_line "--release-tag" "an unchanged release needs no --release-tag advice"
pass "a different user is named with both names and the user to resume with"

explain "$(state identity=deferred 29 asahi-quattro-2afd2ef2 "$source_b" "$package_b")" \
  "$(state user=mina 29 asahi-quattro-2afd2ef2 "$source_b" "$package_b")"
expect_line "  user: recorded none (--deferred-user), this run mina" "a deferred checkpoint names the deferred user"
expect_line "To resume it, run the installer again with --deferred-user." "a deferred checkpoint resumes with --deferred-user"
explain "$(state user=marcelo 29 asahi-quattro-2afd2ef2 "$source_b" "$package_b")" \
  "$(state identity=deferred 29 asahi-quattro-2afd2ef2 "$source_b" "$package_b")"
expect_line "  user: recorded marcelo, this run none (--deferred-user)" "a deferred run names the recorded user"
expect_line "To resume it, run the installer again with --user marcelo." "a deferred run resumes with the recorded user"
pass "deferred and named users are told apart"

explain "$(state user=marcelo 29 asahi-quattro-2afd2ef2 "$source_b" "$package_a")" \
  "$(state user=marcelo 29 asahi-quattro-2afd2ef2 "$source_b" "$package_b")"
expect_line "Error: An incomplete installation was started with a different package source commit" \
  "a package source change alone is named"
expect_line "To resume it, run the installer again with --release-tag asahi-quattro-2afd2ef2, the release that started it." \
  "a package source change says which release to resume with"
pass "a package source change alone is named"

explain $'user=marcelo\nsequence=29\ntag=\e]0;x\a' "$(state user=marcelo 29 asahi-quattro-2afd2ef2 "$source_b" "$package_b")"
expect_line "  release source commit: recorded (missing), this run $source_b" "a field missing from the checkpoint is reported"
[[ $output != *$'\e'* && $output != *$'\a'* ]] || fail "control characters from the checkpoint are not printed" "$output"
reject_line "--release-tag" "a damaged tag is not offered as the release to resume with"
pass "a damaged checkpoint is reported without echoing control characters"

explain $'format=1\nnoise' $'format=1\nnoise\nextra'
expect_line "Error: The incomplete installation checkpoint does not match this run" "an unexplained mismatch still stops the install"
expect_line "To install a different release or user instead, start again from a freshly installed Asahi system." \
  "every mismatch says how to start over"
pass "a mismatch outside the known fields still stops the install"
