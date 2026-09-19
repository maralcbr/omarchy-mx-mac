#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command flock
require_command sha256sum

harness="$ROOT/test/vm/asahi-fresh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# The runner reads its whole configuration from OMARCHY_VM_*; start clean.
unset "${!OMARCHY_VM_@}"

stub_bin="$test_tmp/bin"
state="$test_tmp/state"
evidence_root="$test_tmp/evidence"
mkdir -p "$stub_bin" "$test_tmp/home"
export TEST_STATE="$state" TEST_DOCKER_LOG="$test_tmp/docker.log" TEST_SSH_LOG="$test_tmp/ssh.log"
export TEST_BOOT_FILE="$test_tmp/boot-id" TEST_CONTAINERS="$test_tmp/containers"
lease="$test_tmp/home/.cache/omarchy/asahi-fresh-vm.lease"
: >"$TEST_CONTAINERS"

# docker: the container sees the state directory as /work. A created container
# gets the ID cid-<name>, written to --cidfile and listed in TEST_CONTAINERS
# until it is removed. start-vm lays out the run directory the way the real one
# does; the monitor takes a screendump.
cat >"$stub_bin/docker" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_DOCKER_LOG"
host_path() { printf '%s\n' "${1/#\/work/$TEST_STATE}"; }
case $1 in
  ps)
    if [[ $2 == --all ]]; then
      [[ ${TEST_DOCKER_PS_FAILS:-0} == 0 ]] || exit 1
      wanted=${!#}
      grep -Fx -- "${wanted#id=}" "$TEST_CONTAINERS" || true
      exit 0
    fi
    printf '%s' "${TEST_DOCKER_PS:-}"
    ;;
  container) [[ ${3:-} == "${TEST_DOCKER_EXISTING:-}" ]] || exit 1 ;;
  rm)
    [[ ${TEST_DOCKER_RM_FAILS:-0} == 0 ]] || exit 1
    [[ ${TEST_DOCKER_RM_IGNORED:-0} == 0 ]] || exit 0
    grep -Fvx "$3" "$TEST_CONTAINERS" >"$TEST_CONTAINERS.new" || true
    mv "$TEST_CONTAINERS.new" "$TEST_CONTAINERS"
    ;;
  run)
    if [[ " $* " == *" --rm "* ]]; then
      target=${!#}
      rm -rf "$TEST_STATE/runs/${target#/runs/}"
      exit 0
    fi
    # Losing a name race creates nothing; failing to start leaves the container.
    [[ ${TEST_DOCKER_RUN_FAILS:-} != conflict ]] || exit 125
    while (( $# > 0 )); do
      case $1 in
        --cidfile) cid_file=$2; shift ;;
        --name) name=$2; shift ;;
      esac
      shift
    done
    echo "cid-$name" >"$cid_file"
    echo "cid-$name" >>"$TEST_CONTAINERS"
    [[ ${TEST_DOCKER_RUN_FAILS:-} != start ]] || exit 125
    ;;
  exec)
    shift
    run_dir=""
    while [[ $1 == -* ]]; do
      if [[ $1 == -e ]]; then
        [[ $2 != OMARCHY_VM_RUN_DIR=* ]] || run_dir=${2#*=}
        shift
      fi
      shift
    done
    shift
    case $1 in
      */start-vm)
        run_dir=$(host_path "$run_dir")
        mkdir -p "$run_dir"
        head -c 4096 /dev/zero >"$run_dir/disk.qcow2"
        echo "serial console" >"$run_dir/serial.log"
        ;;
      socat)
        command=$(cat)
        printf 'monitor %s\n' "$command" >>"$TEST_DOCKER_LOG"
        if [[ $command == "screendump "* ]]; then
          echo P6 >"$(host_path "${command#screendump }")"
        fi
        ;;
    esac
    ;;
esac
exit 0
SH

# ssh: every guest stage prints one line and fails only when asked to.
cat >"$stub_bin/ssh" <<'SH'
#!/bin/bash
while (( $# > 0 )) && [[ $1 != root@127.0.0.1 ]]; do shift; done
shift
command="$*"
printf '%s\n' "$command" >>"$TEST_SSH_LOG"
case $command in
  true) exit 0 ;;
  "cat /proc/sys/kernel/random/boot_id") cat "$TEST_BOOT_FILE" 2>/dev/null || echo boot-1; exit 0 ;;
  "systemctl reboot --no-block") echo boot-2 >"$TEST_BOOT_FILE"; exit 0 ;;
esac
stage=${!#}
stage=${stage##*/omarchy-vm-}
echo "$stage stage output"
[[ $stage != "${TEST_FAIL_STAGE:-}" ]]
SH

cat >"$stub_bin/scp" <<'SH'
#!/bin/bash
if [[ ${@: -2:1} == root@127.0.0.1:/root/optional-package-logs ]]; then
  mkdir -p "${!#}/optional-package-logs"
  echo "transaction log" >"${!#}/optional-package-logs/install-good.log"
fi
exit 0
SH

cat >"$stub_bin/ssh-keygen" <<'SH'
#!/bin/bash
while [[ $1 != -f ]]; do shift; done
echo key >"$2"
echo key.pub >"$2.pub"
SH

stable_tag=asahi-packages-stable-$(printf 'a%.0s' {1..40})
cat >"$stub_bin/curl" <<SH
#!/bin/bash
case \${!#} in
  */pointers/asahi-packages-channel) printf 'format=1\nsequence=7\ntag=asahi-packages-channel-7' ;;
  */asahi-packages-channel-7/asahi-packages-channel) printf 'format=1\nstable_tag=$stable_tag\n' ;;
  *) exit 22 ;;
esac
SH
chmod +x "$stub_bin"/*

run_harness() {
  rm -f "$TEST_BOOT_FILE" "$TEST_DOCKER_LOG" "$TEST_SSH_LOG"
  : >"$TEST_DOCKER_LOG"
  set +e
  PATH="$stub_bin:$PATH" HOME="$test_tmp/home" OMARCHY_VM_STATE_DIR="$state" \
    "$harness/run" "$@" >"$test_tmp/out" 2>"$test_tmp/err"
  status=$?
  set -e
  output="$(<"$test_tmp/out")"$'\n'"$(<"$test_tmp/err")"
}

lease_is_free() {
  flock -n "$lease" true
}

evidence_verifies() {
  (cd "$1" && sha256sum --check --strict --quiet SHA256SUMS)
}

# --- A passing run -----------------------------------------------------------

# A run directory from before per-run directories must survive a new run.
mkdir -p "$state/run"
echo legacy >"$state/run/disk.qcow2"

OMARCHY_VM_RUN_ID=pass-1 run_harness --optional-packages
(( status == 0 )) || fail "a passing VM run succeeds" "$output"
evidence="$test_tmp/home/vm-evidence/pass-1"
[[ -d $evidence && ! -e $evidence.partial ]] || fail "a passing run exports its evidence to ~/vm-evidence/<run-id>" "$output"
for file in install.log serial.log verify.log optional-packages.log rerun.log desktop.ppm optional-package-logs/install-good.log; do
  [[ -s $evidence/$file ]] || fail "the evidence holds $file" "$(ls -R "$evidence")"
done
[[ ! -e $evidence/candidate-repository.log ]] || fail "a run without a candidate exports no candidate log"
[[ $(grep -c . "$evidence/SHA256SUMS") == 7 ]] || fail "the checksums cover every exported file" "$(<"$evidence/SHA256SUMS")"
evidence_verifies "$evidence" || fail "the exported evidence verifies against its checksums"
grep -Fxq 'install stage output' "$evidence/install.log" || fail "the evidence holds the run's own install log"
grep -Fxq 'status=passed' "$evidence/run.txt" || fail "the run record says the run passed" "$(<"$evidence/run.txt")"
grep -Fxq "install_log_sha256=$(sha256sum "$evidence/install.log" | cut -d' ' -f1)" "$evidence/run.txt" ||
  fail "the run record carries the acceptance-record log hashes" "$(<"$evidence/run.txt")"
grep -Fxq "serial_log_sha256=$(sha256sum "$evidence/serial.log" | cut -d' ' -f1)" "$evidence/run.txt" ||
  fail "the run record carries the serial log hash"
grep -Fxq "expected_repository=$stable_tag" "$evidence/run.txt" || fail "the run record names the resolved stable set"
[[ ! -e $state/runs/pass-1 ]] || fail "a passing run deletes its run directory once the evidence verifies"
[[ $(<"$state/run/disk.qcow2") == legacy ]] || fail "a run never deletes an earlier run's directory"
[[ $output == *"$state/run"* ]] || fail "a run lists the run directories still on disk" "$output"
pass "a passing run exports verified evidence, then deletes its run directory"

grep -Eq '^run -d --cidfile [^ ]+ --name omarchy-asahi-fresh-vm-pass-1 --label org.omarchy.vm-harness=asahi-fresh --label org.omarchy.vm-run-id=pass-1 ' "$TEST_DOCKER_LOG" ||
  fail "each run gets its own container" "$(<"$TEST_DOCKER_LOG")"
grep -Fxq 'rm -f cid-omarchy-asahi-fresh-vm-pass-1' "$TEST_DOCKER_LOG" || fail "a run removes its own container by its ID"
[[ $(grep -c '^rm ' "$TEST_DOCKER_LOG") == 1 ]] || fail "a run removes no other container" "$(<"$TEST_DOCKER_LOG")"
[[ ! -s $TEST_CONTAINERS ]] || fail "a finished run leaves no container behind" "$(<"$TEST_CONTAINERS")"
grep -Fq 'exec -e OMARCHY_VM_MEMORY_MB=6144 -e OMARCHY_VM_CPUS=8 -e OMARCHY_VM_RUN_DIR=/work/runs/pass-1 cid-omarchy-asahi-fresh-vm-pass-1 /usr/local/lib/omarchy-asahi-vm/start-vm' "$TEST_DOCKER_LOG" ||
  fail "the guest keeps 8 vCPUs and 6 GiB and boots from the run's own directory" "$(<"$TEST_DOCKER_LOG")"
grep -Fxq 'exec -e ARCHARM_MIRROR_URL=https://downloads.aicodelabs.com.au/mirror/alarm/20260906/$repo/os/$arch cid-omarchy-asahi-fresh-vm-pass-1 /usr/local/lib/omarchy-asahi-vm/build-base' "$TEST_DOCKER_LOG" ||
  fail "the guest takes its packages from the dated R2 snapshot by default" "$(<"$TEST_DOCKER_LOG")"
lease_is_free || fail "a finished run releases the lease"
grep -q "^run_id=pass-1 pid=[0-9]* state=$state started_at=" "$lease" || fail "the lease names the run that held it" "$(<"$lease")"
pass "each run has its own container and directory, and the defaults stay 8 vCPUs and the R2 snapshot"

# Generated run IDs never repeat, so neither do container names.
run_harness
(( status == 0 )) || fail "a run with a generated ID succeeds" "$output"
first=$(sed -n 's/^run -d --cidfile [^ ]* --name \([^ ]*\) .*/\1/p' "$TEST_DOCKER_LOG")
run_harness
(( status == 0 )) || fail "a second run with a generated ID succeeds" "$output"
second=$(sed -n 's/^run -d --cidfile [^ ]* --name \([^ ]*\) .*/\1/p' "$TEST_DOCKER_LOG")
[[ $first == omarchy-asahi-fresh-vm-2* && $second == omarchy-asahi-fresh-vm-2* && $first != "$second" ]] ||
  fail "generated run IDs give distinct container names" "$first $second"
[[ -d $test_tmp/home/vm-evidence/${first#omarchy-asahi-fresh-vm-} && -d $test_tmp/home/vm-evidence/${second#omarchy-asahi-fresh-vm-} ]] ||
  fail "every run keeps its own evidence"
pass "generated run IDs give every run its own container and evidence"

OMARCHY_VM_RUN_ID=pass-1 run_harness
(( status != 0 )) && [[ $output == *'Run pass-1 already has a run or evidence directory'* ]] ||
  fail "a reused run ID is refused" "$output"
[[ ! -s $TEST_DOCKER_LOG ]] || fail "a refused run starts nothing" "$(<"$TEST_DOCKER_LOG")"
TEST_DOCKER_EXISTING=omarchy-asahi-fresh-vm-taken OMARCHY_VM_RUN_ID=taken run_harness --evidence-dir "$evidence_root"
(( status != 0 )) && [[ $output == *'Container omarchy-asahi-fresh-vm-taken already exists'* ]] ||
  fail "a run whose container name is taken is refused" "$output"
! grep -Eq '^(rm|run|build) ' "$TEST_DOCKER_LOG" || fail "a run never removes a container it did not create" "$(<"$TEST_DOCKER_LOG")"
pass "a reused run ID is refused before anything starts"

# Evidence inside the state directory could be deleted with the run directory,
# whichever path names it.
mkdir -p "$state/runs"
ln -s "$state/runs" "$test_tmp/runs-alias"
for destination in "$state" "$state/runs" "$state/runs/inside/evidence" "$test_tmp/runs-alias" "$test_tmp/runs-alias/../cache"; do
  OMARCHY_VM_RUN_ID=inside run_harness --evidence-dir "$destination"
  (( status != 0 )) && [[ $output == *"is inside the VM state directory $state"* ]] ||
    fail "evidence inside the state directory is refused: $destination" "$output"
  [[ ! -s $TEST_DOCKER_LOG && ! -e $state/runs/inside ]] || fail "a refused evidence directory starts nothing: $destination"
done
OMARCHY_VM_EVIDENCE_DIR="$test_tmp/runs-alias" OMARCHY_VM_RUN_ID=inside run_harness
(( status != 0 )) && [[ $output == *'is inside the VM state directory'* ]] ||
  fail "OMARCHY_VM_EVIDENCE_DIR inside the state directory is refused" "$output"
(cd "$test_tmp" && OMARCHY_VM_RUN_ID=relative run_harness --evidence-dir relative-evidence)
[[ -f $test_tmp/relative-evidence/relative/run.txt ]] || fail "a relative evidence directory resolves from the caller's directory"
pass "evidence inside the state directory is refused, symlinks included"

# A docker run that loses the name to another run creates nothing, so the run
# must not remove anything; one that created its container but could not start
# it removes exactly that container.
echo cid-omarchy-asahi-fresh-vm-race >"$TEST_CONTAINERS"
TEST_DOCKER_RUN_FAILS=conflict OMARCHY_VM_RUN_ID=race run_harness --evidence-dir "$evidence_root"
(( status != 0 )) || fail "a run whose docker run fails fails"
! grep -q '^rm ' "$TEST_DOCKER_LOG" || fail "a run that lost the name race removes no container" "$(<"$TEST_DOCKER_LOG")"
grep -Fxq cid-omarchy-asahi-fresh-vm-race "$TEST_CONTAINERS" || fail "the container that won the name race survives"
: >"$TEST_CONTAINERS"
TEST_DOCKER_RUN_FAILS=start OMARCHY_VM_RUN_ID=unstarted run_harness --evidence-dir "$evidence_root"
(( status != 0 )) || fail "a run whose container cannot start fails"
[[ $(grep '^rm ' "$TEST_DOCKER_LOG") == 'rm -f cid-omarchy-asahi-fresh-vm-unstarted' ]] ||
  fail "a run removes the container it created even when it never started" "$(<"$TEST_DOCKER_LOG")"
[[ ! -s $TEST_CONTAINERS ]] || fail "an unstarted container is not left behind"
pass "a run removes only the container it created, by the ID docker recorded"

# --- The host lease ----------------------------------------------------------

printf 'run_id=holder pid=1 state=/elsewhere started_at=2026-09-19T00:00:00Z\n' >"$lease"
flock "$lease" bash -c 'touch "$1/held"; while [[ ! -e $1/release ]]; do sleep 0.05; done' _ "$test_tmp" &
holder=$!
for (( i = 0; i < 100; i++ )); do
  [[ -e $test_tmp/held ]] && break
  sleep 0.05
done
[[ -e $test_tmp/held ]] || fail "the test holds the lease"

# The holder is another checkout: a different state directory, the same host.
OMARCHY_VM_RUN_ID=refused run_harness --evidence-dir "$evidence_root"
(( status != 0 )) || fail "a second run on a leased host is refused"
[[ $output == *"Another VM run holds the host lease $lease: run_id=holder pid=1 state=/elsewhere"* && $output == *'--wait-for-lease'* ]] ||
  fail "a refused run names the lease holder and the way to queue" "$output"
[[ ! -s $TEST_DOCKER_LOG && ! -e $evidence_root/refused ]] || fail "a refused run touches no container and exports nothing"
pass "a run from any checkout is refused while another holds the host lease"

(
  PATH="$stub_bin:$PATH" HOME="$test_tmp/home" OMARCHY_VM_STATE_DIR="$state" OMARCHY_VM_RUN_ID=queued \
    "$harness/run" --wait-for-lease --evidence-dir "$evidence_root" >"$test_tmp/queued.out" 2>"$test_tmp/queued.err"
) &
queued=$!
for (( i = 0; i < 100; i++ )); do
  grep -q 'Waiting for the host lease' "$test_tmp/queued.err" 2>/dev/null && break
  sleep 0.05
done
grep -Fq "Waiting for the host lease $lease, held by: run_id=holder" "$test_tmp/queued.err" ||
  fail "a queued run says whom it waits for" "$(cat "$test_tmp/queued.err" 2>/dev/null)"
[[ ! -e $evidence_root/queued ]] || fail "a queued run waits for the lease"
touch "$test_tmp/release"
wait "$holder"
set +e
wait "$queued"
status=$?
set -e
(( status == 0 )) || fail "a queued run proceeds once the lease is free" "$(<"$test_tmp/queued.err")"
[[ -d $evidence_root/queued ]] || fail "a queued run exports its evidence"
pass "--wait-for-lease queues behind the running holder"

# A --keep VM from another state directory still owns the forwarded ports.
TEST_DOCKER_PS=$'omarchy-asahi-fresh-vm-old 127.0.0.1:22222->22/tcp, 127.0.0.1:25900->5900/tcp\n' \
  OMARCHY_VM_RUN_ID=ports run_harness --evidence-dir "$evidence_root"
(( status != 0 )) && [[ $output == *'omarchy-asahi-fresh-vm-old 127.0.0.1:22222->22/tcp'* ]] ||
  fail "a run refuses ports another container forwards, naming it" "$output"
! grep -q '^build ' "$TEST_DOCKER_LOG" || fail "a run refused for its ports builds nothing"
lease_is_free || fail "a refused run releases the lease"
pass "a run refuses ports a retained VM still forwards"

# --- Failed runs -------------------------------------------------------------

TEST_FAIL_STAGE=verify OMARCHY_VM_CPUS=4 OMARCHY_VM_RUN_ID=fail-1 run_harness --evidence-dir "$evidence_root"
(( status != 0 )) || fail "a failing guest stage fails the run"
evidence="$evidence_root/fail-1"
grep -Fxq 'status=failed' "$evidence/run.txt" || fail "a failed run is recorded as failed" "$(cat "$evidence/run.txt" 2>/dev/null)"
grep -Fxq 'verify stage output' "$evidence/verify.log" || fail "a failed run exports the failing stage's log"
[[ -s $evidence/install.log && -s $evidence/serial.log ]] || fail "a failed run exports every log it produced"
evidence_verifies "$evidence" || fail "a failed run's evidence verifies"
[[ -f $state/runs/fail-1/disk.qcow2 ]] || fail "a failed run keeps its disk for debugging"
grep -Fxq 'rm -f cid-omarchy-asahi-fresh-vm-fail-1' "$TEST_DOCKER_LOG" || fail "a failed run still removes its container"
[[ $output == *"Failed run retained for debugging: $state/runs/fail-1"* ]] || fail "a failed run says where its disk is" "$output"
grep -Fq -- '-e OMARCHY_VM_CPUS=4 ' "$TEST_DOCKER_LOG" || fail "OMARCHY_VM_CPUS sets the guest's vCPUs"
lease_is_free || fail "a failed run releases the lease"
pass "a failed run keeps its evidence and, by default, its disk"

TEST_FAIL_STAGE=install OMARCHY_VM_RUN_ID=fail-2 run_harness --evidence-dir "$evidence_root" --discard-failed-run
(( status != 0 )) || fail "a failing install fails the run"
grep -Fxq 'status=failed' "$evidence_root/fail-2/run.txt" || fail "a discarded failed run still keeps its evidence"
[[ ! -e $state/runs/fail-2 ]] || fail "--discard-failed-run deletes the failed run's directory"
pass "--discard-failed-run deletes a failed run's disk after exporting its evidence"

# A copy that does not match its source must never cost the run directory.
real_cp=$(command -v cp)
cat >"$stub_bin/cp" <<SH
#!/bin/bash
"$real_cp" "\$@" || exit
[[ \${!#} != */serial.log ]] || echo corrupted >>"\${!#}"
SH
chmod +x "$stub_bin/cp"
OMARCHY_VM_RUN_ID=corrupt run_harness --evidence-dir "$evidence_root"
rm "$stub_bin/cp"
(( status != 0 )) || fail "a run whose evidence does not verify fails"
[[ $output == *'Evidence export failed'* ]] || fail "a failed export is reported" "$output"
[[ -f $state/runs/corrupt/disk.qcow2 ]] || fail "a failed export keeps the run directory"
[[ ! -e $evidence_root/corrupt && -d $evidence_root/corrupt.partial ]] ||
  fail "an unverified copy never takes the evidence directory's name"
pass "an export that does not verify keeps the run directory"

# Until the container is confirmed gone its guest may still be writing the run
# directory: export nothing, delete nothing, and fail even a passing run.
for failure in TEST_DOCKER_RM_FAILS TEST_DOCKER_RM_IGNORED TEST_DOCKER_PS_FAILS; do
  : >"$TEST_CONTAINERS"
  export "$failure=1"
  OMARCHY_VM_RUN_ID="stuck-$failure" run_harness --evidence-dir "$evidence_root"
  unset "$failure"
  (( status != 0 )) || fail "a passing run fails when its container is not confirmed gone ($failure)" "$output"
  [[ $output == *"Could not confirm that container omarchy-asahi-fresh-vm-stuck-$failure"* ]] ||
    fail "a run says it could not confirm its container is gone ($failure)" "$output"
  [[ -f $state/runs/stuck-$failure/disk.qcow2 ]] || fail "a run keeps its disk while its container may run ($failure)"
  [[ ! -e $evidence_root/stuck-$failure && ! -e $evidence_root/stuck-$failure.partial ]] ||
    fail "a run exports nothing while its container may run ($failure)"
done
pass "a run whose container is not confirmed gone keeps everything and fails"

# --keep leaves the VM running on its run directory and pauses it for the copy.
OMARCHY_VM_RUN_ID=kept run_harness --keep --evidence-dir "$evidence_root"
(( status == 0 )) || fail "a kept run succeeds" "$output"
! grep -q '^rm ' "$TEST_DOCKER_LOG" || fail "a kept run keeps its container"
[[ $(grep '^monitor ' "$TEST_DOCKER_LOG") == $'monitor screendump /work/runs/kept/desktop.ppm\nmonitor stop\nmonitor cont' ]] ||
  fail "a kept run pauses the guest while its evidence is copied" "$(<"$TEST_DOCKER_LOG")"
[[ -f $state/runs/kept/disk.qcow2 ]] || fail "a kept run keeps its run directory"
evidence_verifies "$evidence_root/kept" || fail "a kept run's evidence verifies"
[[ $output == *'VM retained in Docker container omarchy-asahi-fresh-vm-kept'* ]] || fail "a kept run names its container" "$output"
pass "--keep exports verified evidence and keeps the VM and its disk"

# --- Static guards -----------------------------------------------------------

grep -Fq 'cpus=${OMARCHY_VM_CPUS:-8}' "$harness/container/start-vm" || fail "the launcher defaults to 8 vCPUs"
grep -Fq -- '-smp "$cpus"' "$harness/container/start-vm" || fail "QEMU uses the configured vCPU count"
grep -Fq 'run=${OMARCHY_VM_RUN_DIR:-/work/run}' "$harness/container/start-vm" || fail "the launcher takes the run's directory"
# The only live Arch Linux ARM URL left is the signed base rootfs, which is
# cached; every package comes from the snapshot unless a caller overrides it.
live_mirrors=$(grep -rn --exclude-dir=test-runs 'archlinuxarm\.org' "$harness" | grep -v '/container/build-base:[0-9]*:rootfs_url=' || true)
[[ -z $live_mirrors ]] || fail "nothing in the harness defaults to a live Arch Linux ARM mirror" "$live_mirrors"
pass "the launcher takes the vCPU count and run directory, and no live mirror is a default"
