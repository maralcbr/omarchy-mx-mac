# Apple Silicon deployment runbook

How a change reaches an Omarchy Mac, from a commit to `omarchy update` or a
fresh install. Two lanes: the **fast lane** for changes to the runtime
(scripts, configuration, migrations — about fifteen minutes), and the **full
lane** for changes to the package set or a new OS image (a few hours, with a
VM gate). Policy and rationale live in
[`apple-silicon-release-lifecycle.md`](apple-silicon-release-lifecycle.md);
the signed channel layout in
[`apple-silicon-distribution-channels.md`](apple-silicon-distribution-channels.md).
This document is the sequence of commands.

## The moving parts

| Repository | Ships | Pinned by |
| --- | --- | --- |
| `omarchy-mx-mac` (this) | the runtime pair `omarchy-dev` / `omarchy-settings-dev`, the installer app, the acceptance harness, release tooling | `omarchy-pkgs/pkgbuilds/omarchy-source.conf` names the runtime source commit |
| `omarchy-pkgs` (branch `asahi-quattro`) | the 55-package `[omarchy]` repository and the 6-package runtime bundle, as immutable GitHub releases and signed release channels | `omarchy-iso/builder/arm-package-snapshots.conf`, `configs/airootfs/…/pacman-online-installed-arm.conf` |
| `omarchy-iso` | the OS payload (`omarchy-<date>-aarch64-apple-silicon-asahi-os-package.zip`) | `apps/omarchy-apple-installer/scripts/release-inputs.template.json`, `Engine/installer_data.json` |

Artifacts, in the order they are produced:

| Artifact | Where | Made by |
| --- | --- | --- |
| package candidate `asahi-packages-candidate-<pkgs commit>` | GitHub release, immutable, prerelease | `release-asahi-package-incremental.yml` |
| promoted packages `asahi-packages-stable-<pkgs commit>` | GitHub release, byte-identical copy | `bin/promote-asahi-package-candidate --publish` |
| package channel `asahi-packages-channel-<S>` | GitHub release, immutable, signed; `omarchy update` moves `[omarchy]` to the set it names | `publish-asahi-packages-channel.yml` |
| package channel pointer `pointers/asahi-packages-channel` | R2, mutable; names the highest S | the last step of the same workflow, see [below](#the-package-channel) |
| runtime channel `asahi-quattro-channel-<N>` | GitHub release; `omarchy update` follows the highest N | `promote-asahi-quattro-runtime.yml mode=publish` |
| runtime channel pointer `pointers/asahi-quattro-channel` | R2, mutable; names the highest N | the last step of the same publish job, see [below](#the-runtime-channel-pointer) |
| Arch Linux ARM snapshot `mirror/alarm/<YYYYMMDD>/` | R2 | rsync + rclone, see below |
| OS release `releases/os-v4.0.2-mac.1.<date>/` + signed catalog | R2, immutable (7-day age lock) | `publish-m1-release` + `make-unsigned-catalog.py` + `catalog-signing.swift` |
| channel `channels/rc` or `channels/stable` | R2, mutable | `publish-channels os-promote` |
| installer `installer/<version>/` and `installer/rc|stable/` | R2 | `publish-channels app-publish` |

Machines: **this Mac (M4)** builds the payload and publishes to R2; **GitHub**
builds candidates and publishes runtime channels; **the M1** runs VM
acceptance (it needs KVM, which GitHub's ARM runners lack) — grant yourself
access with the LAN-only helper described in the workspace `AGENTS.md`.
Anything with `bash`, `find`, or a case-insensitive disk in the path runs on
Linux (the M1) or under `/opt/homebrew/bin/bash` with the GNU `gnubin`
directories first on `PATH`; see the gotchas at the end.

## Fast lane: a runtime-only change

Applies when the change is confined to what `omarchy-dev` and
`omarchy-settings-dev` package — `bin/`, `default/`, `config/`, `install/`,
`migrations/`, tests, docs. Nothing in the repository package set moves.

1. Land the change on `main` with its `test/shell.d` coverage, and push.
2. In `omarchy-pkgs`:

   ```bash
   bin/asahi-runtime-release <full main commit>     # --dry-run to preview
   ```

   It pins `omarchy-source.conf` to the commit and merges that as a PR, builds
   an incremental candidate on the newest published candidate (only the
   runtime pair rebuilds; the gate installs the predecessor set from its dated
   snapshot and upgrades over it), approves the `asahi-quattro-release` gates,
   checks the candidate rebuilt nothing outside the runtime, and publishes
   `asahi-quattro-channel-<N+1>`. The publish job's last step points
   `pointers/asahi-quattro-channel` at it. If that step fails, the command
   prints the [repair command](#the-runtime-channel-pointer) and exits
   non-zero.
3. Installed Macs receive it on their next `omarchy update`. Verify on one:

   ```bash
   omarchy-update-asahi-bundle --check    # "… <tag> is available"
   ```

What the lane skips on purpose: VM acceptance, package promotion, and the OS
payload — the repository set is byte-identical to a set that already passed
them, and fresh installs sync their repositories and update on first boot.
The command refuses a candidate that rebuilt a repository package; that change
is a full-lane change.

Timing: ~12–15 minutes, dominated by the runtime build and the upgrade gate.

## Full lane: a package-set change or a new OS image

Use it when `pkgbuilds/asahi-repository-*`, a PKGBUILD, the builder, or the
workflows change, or when the image itself must change (finalizer, pins, base
system). Every step below waits on the previous one.

### 1. Candidate

Open a PR against `asahi-quattro` (squash merge, no approvals required), then:

```bash
gh workflow run release-asahi-package-incremental.yml -R maralcbr/omarchy-pkgs --ref asahi-quattro \
  -f mode=incremental -f publish_candidate=true \
  -f predecessor_tag=asahi-packages-candidate-<prev> -f predecessor_candidate_sha256=<sha of its CANDIDATE> \
  -f previous_package_commit=<prev pkgs commit> -f previous_runtime_commit=<prev mx-mac commit> \
  -f predecessor_signing_fingerprint=CAB18E175BFB9ACCE185234474DE0C737AC186E4
```

`mode=full` rebuilds everything (~1 h); the planner also falls back to full
when workflows or the build contract changed in the compared range. Approve
the environment gate when the publish job reaches it (`gh api … /pending_deployments`
with a JSON body of integer `environment_ids`). Read the result from the
candidate release: `CANDIDATE` (descriptor; its sha256 is the candidate's
identity), `asahi-quattro-bundle.manifest` (runtime), `PLAN.json`.

### 2. VM acceptance on the M1

Sync the harness (`rsync -a --exclude .git … omarchy-mx-mac/ 192.168.0.192:~/omarchy-src/`),
keep the machine awake (the harness needs `docker` group membership and KVM),
then:

```bash
export OMARCHY_VM_CANDIDATE_TAG=asahi-packages-candidate-<commit>
export OMARCHY_VM_CANDIDATE_SHA256=<sha of CANDIDATE>
export OMARCHY_VM_CANDIDATE_FINGERPRINT=CAB18E175BFB9ACCE185234474DE0C737AC186E4
export OMARCHY_VM_CANDIDATE_PACKAGE_COUNT=<package_count from CANDIDATE>
export OMARCHY_VM_RUNTIME_MANIFEST_SHA256=<sha of the candidate's asahi-quattro-bundle.manifest>
export OMARCHY_VM_RUNTIME_SOURCE=<source_commit from that manifest>
# optional: pin the channel guest/verify checks, and the pointer both guest stages read
export OMARCHY_VM_ASAHI_CHANNEL_URL=https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-channel-<N>/asahi-quattro-channel
export OMARCHY_VM_ASAHI_CHANNEL_POINTER_URL=https://downloads.aicodelabs.com.au/pointers/asahi-quattro-channel
# default mirror is the snapshot the payload pins; a live mirror needs its own shape:
export OMARCHY_VM_ALARM_MIRROR='https://ca.us.mirror.archlinuxarm.org/$arch/$repo'
test/vm/asahi-fresh/run --optional-packages
```

Without the two runtime exports the harness installs the last published
runtime release and fails on its version mismatch with the candidate.

Passing means 23 `ok` lines and exit 0. Record it as
`docs/releases/asahi-packages-candidate-<8hex>-acceptance.txt` (copy the
previous one; `format=1`, `candidate_tag`, `candidate_sha256`,
`signing_fingerprint` and `status=accepted` are validated, the log hashes come
from `test/vm/asahi-fresh/test-runs/run/` of a `--keep` run).

### 3. Promote the packages

On Linux (the M1), with a GitHub token that can create releases:

```bash
bin/promote-asahi-package-candidate --publish maralcbr/omarchy-pkgs \
  asahi-packages-candidate-<commit> <candidate sha256> CAB18E175BFB9ACCE185234474DE0C737AC186E4 \
  default/omarchy-arm-repository.asc <acceptance file> <sha256 of the acceptance file>
```

This creates `asahi-packages-stable-<commit>`. Installed Macs do not see it
until it is published on the package channel:

```bash
gh workflow run publish-asahi-packages-channel.yml -R maralcbr/omarchy-pkgs --ref asahi-quattro \
  -f stable_tag=asahi-packages-stable-<commit>
```

Approve the `asahi-quattro-release` gate. The workflow checks the stable and
candidate releases, refuses a set that does not descend from the current
channel's set, signs and publishes `asahi-packages-channel-<S+1>`, and points
`pointers/asahi-packages-channel` at it. `omarchy-update-asahi-repository`
then moves installed Macs on their next update. If it fails part way, see
[the package channel](#the-package-channel).

A fresh install starts on the promoted set directly: before its first package
transaction, `bin/omarchy-install-asahi-fresh` runs the verified runtime's
`omarchy-update-asahi-repository --bootstrap`, which reads the package channel,
trusts both Omarchy keys and writes `[omarchy]` ahead of the Arch Linux ARM
repositories. A fresh install cannot start until the package channel pointer or
the release listing names a channel, and that channel's stable set is what it
installs from.

**Never withdraw the bootstrap package release.**
`asahi-packages-784daa3efaecfa81b5b4da888b524e6ec4574d24` is what
`install/hardware/pacman.sh` still writes on paths with no `[omarchy]` section
and no package channel, and it must stay published, non-draft, non-prerelease
and byte-for-byte immutable. Those are exactly the conditions under which
`bin/publish-asahi-packages-channel` keeps its commit in every new channel's
`supersedes`, and `supersedes` is what lets `omarchy-update-asahi-repository`
move such a Mac onto the promoted set. Withdraw it and those Macs cannot
install; drop it from `supersedes` and they install but never move. The pin is
not bumped when a set is promoted: the package channel does the moving.

### 4. Runtime channel

```bash
gh workflow run promote-asahi-quattro-runtime.yml -R maralcbr/omarchy-pkgs --ref asahi-quattro \
  -f candidate_tag=… -f candidate_sha256=… -f source_commit=<mx-mac commit> -f sequence=<N+1> -f mode=publish
```

Approve the gate. The sequence must be exactly one above the highest
published channel. The job's last step points the runtime channel pointer at
the new channel.

### 5. Repoint the image

In `omarchy-iso`, all in one commit:

- `builder/arm-package-snapshots.conf` — every field, derived from the
  candidate's signed assets: `ARM_REPOSITORY_RELEASE=…stable-<c>`,
  `…DESCRIPTOR_RELEASE=…candidate-<c>`, `…DESCRIPTOR_SHA256`,
  `…SOURCE_COMMIT=<c>`, `…PACKAGE_COUNT`; `ARM_RUNTIME_RELEASE=…candidate-<c>`,
  `…MANIFEST_SHA256`, `…SOURCE_COMMIT=<mx-mac commit>`;
  `ARM_RUNTIME_CHANNEL_SEQUENCE=<N>`, `…CHANNEL_TAG=asahi-quattro-<8hex>`.
  The build verifies each against the release; a half-edited file fails it.
- `configs/airootfs/usr/share/omarchy-iso/pacman-online-installed-arm.conf` —
  `[omarchy]` on the same stable tag (the build cross-checks).
- `configs/pacman-online-arm.conf` — the Arch Linux ARM snapshot to build from.
- `builder/products/omarchy-mx-mac.json` — a new `package_filename` date, and
  the matching expectation in `test/unit/test_asahi_stage_inputs.py`.

Also `test/prepare-alarm-container` here and, if the snapshot changed, the
harness default in `test/vm/asahi-fresh/run` and the gate pin in both
`release-asahi-package-*.yml` workflows.

### 6. Build the payload (this Mac)

```bash
cd omarchy-iso
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) OMARCHY_ASAHI_CHECKPOINT_ROOT=$HOME/.cache/omarchy/asahi-checkpoints-<date>
export PATH=/opt/homebrew/bin:/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/grep/libexec/gnubin:/opt/homebrew/opt/findutils/libexec/gnubin:$PATH
/opt/homebrew/bin/bash bin/omarchy-iso-make --target aarch64/apple-silicon --artifact asahi-os-package --mode diagnostic
/opt/homebrew/bin/bash bin/omarchy-iso-make --target aarch64/apple-silicon --artifact asahi-os-package --mode qualification
```

A fresh checkpoint root needs the diagnostic pass first (it content-locks the
toolchain); qualification then restores the stages. Output lands in
`release/`. 60–90 minutes when pins changed; the diagnostic mode rebuilds the
base image every run and compares it, so re-running it against an existing
`checkpoints/base-images` fails — delete that directory first.

### 7. Publish and promote

In `apps/omarchy-apple-installer` of this repository:

```bash
A=apps/omarchy-apple-installer; W=~/omarchy-cutover/release-<date>; TAG=os-v4.0.2-mac.1.<date>
P=../omarchy-iso/release/omarchy-<date>-aarch64-apple-silicon-asahi-os-package.zip
cp "$P.installer-data.json" $W/installer_data.json          # names this payload; also copy it to $A/Engine/
# That copy is per payload and is not pinned by the engine source lock, which pins the
# metadata inside the engine artifact (validation_artifact.metadata_sha256) instead.
python3 - <<'PY'                                             # inputs: payload_name, evidence_revision
…
PY
git tag -a $TAG -m "…" && git push origin $TAG                # publish-r2 requires the tag on origin
bash $A/scripts/publish-m1-release prepare --payload "$P" --engine $A/Engine/artifacts/installer-v0.9.2-omarchy.17.tar.gz \
  --metadata $W/installer_data.json --tag $TAG --repo maralcbr/omarchy-mx-mac --out-dir $W/staged --no-split \
  --base-url https://downloads.aicodelabs.com.au/releases/$TAG
python3 $A/scripts/make-unsigned-catalog.py --base-url https://downloads.aicodelabs.com.au/releases/$TAG \
  --assets-dir $W/staged --inputs $W/inputs.json --output $W/catalog/catalog.json
xcrun swift $A/scripts/catalog-signing.swift sign-keychain omarchy-channel-signing-key $W/catalog/catalog.json $W/catalog/catalog.json.sig
xcrun swift $A/scripts/catalog-signing.swift verify $A/Release/trust-root.ed25519.pub $W/catalog/catalog.json $W/catalog/catalog.json.sig
$A/scripts/publish-channels envelope --catalog $W/catalog/catalog.json --signature $W/catalog/catalog.json.sig --output $W/catalog/catalog.signed.json
OMARCHY_PUBLISH_ASSUME_YES=$TAG bash $A/scripts/publish-m1-release publish-r2 --dir $W/staged --tag $TAG \
  --bucket omarchy-releases --endpoint https://ab85a8b9d88f084e66bf9d4a8ee5cf66.r2.cloudflarestorage.com \
  --base-url https://downloads.aicodelabs.com.au/releases/$TAG --catalog-dir $W/catalog
OMARCHY_PUBLISH_ASSUME_YES=$TAG $A/scripts/publish-channels os-promote --tag $TAG --to rc
```

The engine is a Python-only repack of the deployed `omarchy.14` engine, so it
needs no re-signing. Rebuild it from an `asahi-installer` checkout at the
commit in `Engine/source-lock.json` (submodules initialised); the lock records
the expected size and SHA-256:

```bash
python3 $A/Engine/rebuild-python-overlay.py <asahi-installer checkout> \
  $A/Engine/artifacts/installer-v0.9.0-omarchy.14.tar.gz $A/Engine/artifacts/installer-v0.9.2-omarchy.17.tar.gz
```

The rebuild only takes the upstream Python files the lock lists under
`incremental_build.upstream_delta`, and refuses any other upstream change. When
the Omarchy patch also edits one of those files (`src/main.py` today), the
rebuild applies the patch to a scratch copy of the old and new upstream file
and checks both results against the lock, so the checkout is never modified.
Build it twice into different folders and compare the two files before
recording a new size and SHA-256.

R2 credentials come from the login Keychain (`omarchy-r2-access-key-id`,
`omarchy-r2-secret-access-key`), the catalog key from
`omarchy-channel-signing-key`. `os-promote --to stable` is a separate,
deliberate step, and prunes unreferenced release sets afterwards. The
installer app has its own lane (`publish-channels app-publish`) and only
changes when the app does; the README download link never changes.

## The runtime channel pointer

`pointers/asahi-quattro-channel` on R2 tells installed Macs which runtime
channel is newest, so `omarchy update` does not need the rate-limited GitHub
API. The format and what a Mac does with it are in
[`apple-silicon-distribution-channels.md`](apple-silicon-distribution-channels.md#the-runtime-channel-pointer).

The runtime publish job (`promote-asahi-quattro-runtime.yml`) updates it as
its last step, through `bin/publish-asahi-channel-pointer` in `omarchy-pkgs`.
The legacy `release-asahi-quattro.yml` lane runs the same step, but that step
refuses its releases: the lane signs the bundle manifest and packages with the
release key, and installed Macs (and the publisher) require the ARM repository
key, so those releases were never installable. Publish through the promote
lane. That script checks
channel `N` completely, refuses unless `N` is the highest published channel,
refuses to move the pointer backwards or to rewrite `N` with different bytes,
and always reads the object back, including when nothing needed writing.

Check what it says:

```bash
curl -fsS https://downloads.aicodelabs.com.au/pointers/asahi-quattro-channel
```

### Repair it

When a publish job failed at the pointer step, or `asahi-runtime-release`
printed this command, the channel release is public but the pointer still
names the previous channel:

```bash
gh workflow run publish-asahi-channel-pointer.yml -R maralcbr/omarchy-pkgs --ref asahi-quattro -f sequence=<N>
```

Approve the `asahi-quattro-release` gate. It shares the publish jobs'
concurrency group, so it waits for any running publish. Nothing is broken
while the pointer lags: Macs on the previous channel stay there until the
repair, and Macs already on `N` ignore the lower pointer and use the GitHub
listing. Use the same command for the first publication.

If the script reports that the current object is malformed, replace it
(`N` must still be the highest published channel):

```bash
gh workflow run publish-asahi-channel-pointer.yml -R maralcbr/omarchy-pkgs --ref asahi-quattro -f sequence=<N> -f replace_malformed=true
```

Until then, Macs warn `release channel pointer is malformed; using the GitHub
release listing` and fall back to the listing.

### Cache

`downloads.aicodelabs.com.au` sits behind Cloudflare's cache. The readback
proves only what the edge that answered serves; another edge can keep an
older copy or a cached 404 for a while despite `no-cache`. If a Mac still
sees the old pointer after a successful publish, wait and retry, rerun the
repair command (it writes nothing when the bytes already match and verifies
again), or purge that URL from the Cloudflare cache. Do not treat one good
readback as proof that every Mac sees the new pointer.

## The package channel

`asahi-packages-channel-<S>` and `pointers/asahi-packages-channel` tell
installed Macs which promoted package set to move `[omarchy]` to, without the
GitHub API. The format and the move rules are in
[`apple-silicon-distribution-channels.md`](apple-silicon-distribution-channels.md#the-package-channel).
Full lane step 3 publishes both.

Check what is live:

```bash
curl -fsS https://downloads.aicodelabs.com.au/pointers/asahi-packages-channel
```

### Repair it

Rerun the same dispatch with the same `stable_tag`. It is the repair for every
failure after the checks passed (draft created, an upload, publication,
readback, or the pointer): it reuses channel `S` if it already names that set,
replaces its own leftover draft, and writes nothing that already matches.

```bash
gh workflow run publish-asahi-packages-channel.yml -R maralcbr/omarchy-pkgs --ref asahi-quattro \
  -f stable_tag=asahi-packages-stable-<commit>
```

If it reports that the current pointer object is malformed, rerun with
`-f replace_malformed_pointer=true`. To republish only the pointer (`S` must be
the highest published package channel):

```bash
gh workflow run publish-asahi-channel-pointer.yml -R maralcbr/omarchy-pkgs --ref asahi-quattro \
  -f kind=packages -f sequence=<S>
```

Approve the gate each time. The workflows share the publish jobs' concurrency
group, and a queued dispatch can be replaced by a newer one; if yours never
ran, dispatch it again.

One failure a rerun cannot fix: a git tag `asahi-packages-channel-<S>` that has
no published release. Check that no release uses it, delete the tag by hand,
then rerun:

```bash
gh release view asahi-packages-channel-<S> -R maralcbr/omarchy-pkgs    # must report no release
gh api -X DELETE repos/maralcbr/omarchy-pkgs/git/refs/tags/asahi-packages-channel-<S>
```

Nothing is broken while the channel or pointer lags: Macs stay on the set they
have, and a Mac whose recorded channel is above the pointer reads the GitHub
listing instead. The [cache note](#cache) above applies to this pointer too.

## Cutting an Arch Linux ARM snapshot

The payload build and the acceptance gate read Arch Linux ARM from a dated,
immutable copy in R2 (`mirror/alarm/<YYYYMMDD>/<repo>/os/aarch64/`) so an
upstream mid-transition cannot fail a build that has nothing to do with it.
Cut a new one when a package we carry needs something newer than the current
snapshot has (as `hyprland` needed `aquamarine 0.15`), or on a cadence.

```bash
# refresh the local mirror incrementally (core alarm aur extra; drops *.old, dereferences the .db links)
rsync -rtL --delete --exclude '*.old' rsync://ca.us.mirror.archlinuxarm.org/archlinuxarm/aarch64/<repo>/ ~/.cache/omarchy/alarm-mirror/<date>/aarch64/<repo>/
# copy the previous snapshot server-side (rclone, ~10 min for 28k objects), then sync only the delta
rclone copy r2:omarchy-releases/mirror/alarm/<prev> r2:omarchy-releases/mirror/alarm/<date> --transfers 32 --s3-no-check-bucket
rclone sync ~/.cache/omarchy/alarm-mirror/<date>/aarch64/<repo>/ r2:omarchy-releases/mirror/alarm/<date>/<repo>/os/aarch64/ --size-only
# force the databases, then verify: each <repo>.db must match the local copy byte for byte
```

`rclone` needs `RCLONE_CONFIG_R2_{TYPE=s3,PROVIDER=Cloudflare,ENDPOINT,ACCESS_KEY_ID,SECRET_ACCESS_KEY}` and
`RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true`. Then repoint every reader (step 5)
and record the date in `apple-silicon-distribution-channels.md`. Snapshots are
never modified or pruned automatically.

## The Aurora lane

The `RC (Aurora)` channel serves a second payload built from the Aurora Silicon
kernel (`aurora-silicon/linux`, branch `aurora-wip`): DisplayPort alt-mode and
USB4 for external monitors, variable refresh rate, ISP and AOP. It is a whole
kernel, not a module, so it is a whole payload.

The lane is deliberately parallel to the Asahi one rather than part of it. The
kernel never enters the `[omarchy]` repository, it gets its own immutable
release, and the payload is a second product descriptor. Nothing here runs
during a normal Asahi release, and a build that does not ask for the aurora
product produces the same bytes it did before this lane existed.

| Artifact | Where | Made by |
| --- | --- | --- |
| kernel `aurora-packages-<pkgs commit>` | GitHub release, immutable, prerelease | `release-aurora-package.yml` |
| payload `omarchy-<date>-aarch64-apple-silicon-aurora-os-package.zip` | this Mac | `omarchy-iso-make --product omarchy-mx-mac-aurora` |
| channel `channels/rc-aurora` | R2 | `publish-channels os-promote --to rc-aurora` |

1. Build and publish the kernel from `omarchy-pkgs`, then record the tag and
   the `AURORA` digest the run prints:

   ```bash
   gh workflow run release-aurora-package.yml -f publish=true
   ```

2. Pin both halves in `omarchy-iso` — they are compared at build time and the
   build stops if they disagree: `builder/aurora-package-snapshots.conf`
   (`AURORA_REPOSITORY_RELEASE`, `_DESCRIPTOR_SHA256`, `_SOURCE_COMMIT`) and
   the `[omarchy-aurora]` `Server` line in
   `configs/airootfs/usr/share/omarchy-iso/pacman-online-installed-arm-aurora.conf`.

3. Build the payload on this Mac. Give it its own checkpoint root so the Asahi
   cache is untouched:

   ```bash
   OMARCHY_ASAHI_PRODUCT_NAME=omarchy-mx-mac-aurora OMARCHY_ASAHI_CHECKPOINT_ROOT=$HOME/.cache/omarchy/asahi-checkpoints-aurora bin/omarchy-iso-make --target aarch64/apple-silicon --artifact asahi-os-package --product omarchy-mx-mac-aurora --mode qualification
   ```

4. Publish as usual, with the aurora inputs, and promote to `rc-aurora`. Use
   `--no-prune` the first time, before any stable promotion can prune a release
   set the new channel is the only reference to:

   ```bash
   publish-channels os-promote --tag os-v4.0.2-mac.1.<date>-aurora --to rc-aurora --no-prune
   ```

Steps 2 through 4 need the owner's authorization, like every other publication.

### Promoting a qualified Aurora kernel

Installed Aurora Macs follow `default/aurora-qualified-release`: a `tag`, the
`descriptor_sha256` of its `AURORA`, and `predecessors`, the older releases it
replaces. On every `omarchy update`, `omarchy-update-system-pkgs` first runs
`omarchy-update-aurora-repository`, which checks the pinned `AURORA` against
that digest and the ARM repository subkey, then adds `[omarchy-aurora]` just
before `[omarchy]` or repins it from a listed predecessor; the package upgrade
right after it syncs. Commit hashes carry no order, so a section on any other
release — such as a candidate pinned by hand for qualification — is left alone
with a warning. Asahi installs and x86 are untouched; a failed check stops the
update before any package moves.

Only a Mac whose channel record says so follows the pin. The record,
`/var/lib/omarchy/apple-silicon-channel`, holds `format=1`, `channel=stable|rc`,
`kernel=linux-asahi|linux-aurora` and an optional `hold=<reason>`. A Mac without
one gets it on its first update, inferred from the installed kernel and the
image's kernel marker; ambiguous evidence writes nothing and skips the pin with
a warning, while a malformed or contradicted record stops the update.
`channel=rc` is the policy, not proof that the qualified kernel is installed.
`omarchy-apple-silicon-channel hold "<reason>"` stops `[omarchy-aurora]` moving
and `release` resumes it. A hold is not a package freeze: `pacman -Syu` still
runs against the repository the section already names.

1. Publish the kernel release (step 1 above); record the tag and `AURORA`
   digest.
2. Qualify it on real hardware: on the M2 Max, point `[omarchy-aurora]` at the
   new release by hand, `omarchy update`, reboot, and check boot, Wi-Fi and
   every display. The updater leaves that hand-pinned candidate alone.
3. In one commit, append the current `tag` to the end of `predecessors`, then
   set `tag` and `descriptor_sha256` to the new release. Recompute the digest
   rather than copying it: `gh release download <tag> --repo
   maralcbr/omarchy-pkgs --pattern AURORA --dir <tmp>`, then
   `sha256sum <tmp>/AURORA`.
4. Ship it as a runtime release ([fast lane](#fast-lane-a-runtime-only-change)).
5. Verify on the M2 Max: put its `[omarchy-aurora]` `Server` back on the
   previous release (now a predecessor), run `omarchy update`, and check that
   the section names the new tag, `pacman -Q linux-aurora` shows the new
   version, and it boots.

An `IgnorePkg` or `IgnoreGroup` hold on the Aurora packages keeps the old
kernel: the updater warns and leaves the hold. A repin never downgrades an
installed kernel; only a switch back from edge does (below).

Every managed run also stages the verified `AURORA` at
`/var/lib/omarchy/aurora-target.descriptor`, even when the section does not
move. `01-omarchy-aurora-verify.hook` (a PreTransaction, AbortOnFail hook the
runtime ships) then stops any pacman transaction that installs or upgrades
`linux-aurora`, `linux-aurora-headers` or `m1n1-aurora` while the synced
`omarchy-aurora.db` is not the database that descriptor names. A section on a
different release (a hold, a hand pin) or nothing staged yet gets one notice
and passes; archives installed with `pacman -U` are outside the check.

### The edge lane

An installed rc Mac can follow `edge` instead of the pin: each
`aurora-edge-<N>` release, built from `aurora-wip` HEAD. There is no edge
installer image. The channel record keeps `format=1 channel=rc`, so older
runtimes still read it; the lane lives beside it in
`/var/lib/omarchy/apple-silicon-aurora-lane` (root, 0644, written by rename
under the channel lock):

| Line | Meaning |
| --- | --- |
| `lane=rc` or `lane=edge` | what the Mac follows; no file means `rc` |
| `switch=rc` or `switch=edge` | a requested switch, cleared once it is proven |
| `edge_accepted=<N>:<sha256>` | the last edge release proven installed and bootable; the Mac never goes below it |
| `edge_pending=<N>:<sha256>` | the edge release journaled before the section moved; an interrupted update finishes it |

`omarchy-channel-current` reports `edge` for such a Mac (`dev` still wins).
The runtime package must install the hook above: `omarchy-channel-set edge`
refuses on a runtime without it.

**Publish an edge release** (in `omarchy-pkgs`, with the owner's authorization
like any publication):

1. `gh workflow run release-aurora-edge.yml -R maralcbr/omarchy-pkgs --ref asahi-quattro`,
   then approve the `asahi-quattro-release` gate after checking what changed on
   `aurora-wip` and that the build passed. The run number is the sequence `N`,
   and the release is `aurora-edge-N` (not a draft, not a prerelease).
2. `bin/publish-asahi-channel-pointer --kind aurora-edge` points
   `pointers/aurora-edge-channel` at it once the release's signed descriptor
   reads back correctly. Check it:
   `curl -fsS https://downloads.aicodelabs.com.au/pointers/aurora-edge-channel`.
   A lagging pointer only holds Macs back: one behind what a Mac accepted
   sends that Mac to the release listing.
3. Before the first edge release reaches anyone else, qualify rc → edge → rc
   on the M2 Max and the M1 Pro with the owner present, cold boots only.

**Opt a Mac in**: *Update > Channel > Edge*, or `omarchy-channel-set edge`. It
takes the update lock, then the channel lock, refuses a held channel, a Mac on
`linux-asahi`, an invalid record, and `IgnorePkg`/`IgnoreGroup` on any of the
three packages, writes `lane=edge switch=edge`, and runs `omarchy update -y`.
That update picks the release (the pointer if it is not behind the accepted
release, else the listing read to its end within 10 pages; on first contact
the listing's highest full release), verifies its signed descriptor
(`channel=aurora-edge`, `release_tag=aurora-edge-N`, `sequence=N`; for an
accepted or journaled `N`, the same digest), journals it as pending (even
when the section already names it: only the accepted release in place needs
no journal), stages it, moves `[omarchy-aurora]`, and upgrades with
`omarchy-aurora/linux-aurora omarchy-aurora/linux-aurora-headers
omarchy-aurora/m1n1-aurora` named. After the transaction it checks the
installed versions against the descriptor and the boot chain, and only then
records `edge_accepted`; a switch with no release to prove never completes.
Later updates follow newer edge releases the same way.

When neither pointer nor listing answers (or the chosen release's descriptor
cannot be downloaded), the update says so, exits the Aurora step with 3,
upgrades on what it can prove, and leaves any switch or journal open. That is
not always "nothing moves": a section on the accepted edge release stays
there, but a missing section or one on a release the pin replaces is moved to
the rc pin, exactly as on an rc Mac, so it is on a release whose descriptor
can be staged. A section on any other edge release stays as it is.

The boot chain check is `omarchy-apple-silicon-boot-check`. It knows two
kernel and bootloader pairs, `linux-aurora` with `m1n1-aurora` and
`linux-asahi` with `m1n1`, takes one as an argument or detects the installed
pair (refusing both kernels, neither, or a mismatched bootloader), and keeps no
lane or reboot state, so a first-boot installer can run it for either kernel
once the boot hooks have finished. It compares `/boot/vmlinuz-<kernel>`, the
initramfs modules, the GRUB entry, and `m1n1/boot.bin` against an image rebuilt
from the installed m1n1, device trees, U-Boot and `/etc/m1n1.conf` the way the
installed `update-m1n1` builds it (a DTBS directory only when that script
expands one), without running `update-m1n1`. The ESP is read only through a
read-only mount: a fresh `mount -o ro` when it is not mounted, else a
read-only bind of its existing mount; a refused read-only mount fails the
check rather than falling back to a writable one.

**Leave edge**: `omarchy-channel-set rc`. The next update moves the section
back to the pin and installs the pin's (older) packages through the same
named targets and checks; `edge_accepted` is kept. When the menu or
`omarchy-channel-set` is not an option, `omarchy-apple-silicon-channel
reset-rc` records the same request, then run `omarchy update`.

**Recovery**:

- `Aurora kernel check: the synced omarchy-aurora database is not the one …`
  from pacman: the transaction stopped before anything changed. Run
  `omarchy update`, which restages the descriptor and syncs again.
- `The move to <tag> is not verified: <reason>`: the packages installed but
  what boots does not match them (a failed mkinitcpio, GRUB or update-m1n1
  hook, or `M1N1_UPDATE_DISABLED` set). The switch and journal stay open,
  `/run/omarchy-reboot-blocked` holds the reason, the reboot prompt refuses,
  and `omarchy update` exits non-zero. Re-run what failed (`sudo mkinitcpio
  -P`, `sudo grub-mkconfig -o /boot/grub/grub.cfg`, `sudo update-m1n1`), then
  `omarchy update`, which checks again and lifts the block. Do not reboot
  before that.
- `this Mac's Aurora lane cannot be read`: `omarchy-apple-silicon-channel
  reset-rc` rewrites the lane file as rc (its edge history is lost).
- A runtime downgraded by hand ignores the lane file and leaves an
  `aurora-edge-*` section alone: the Mac keeps its edge kernel until a newer
  runtime is back.

**Integration check.** `test/aurora-integration` runs the boot check against a
FAT ESP on a loop device (mounted and not) and the hook against a real pacman
transaction from a throwaway repository. It mounts devices and replaces
`/etc/pacman.conf`, so it refuses to run outside a disposable container:

```bash
docker run --rm --privileged -e OMARCHY_INTEGRATION_CONTAINER=1 -v "$PWD":/src -w /src omarchy-test:4.0.3 test/aurora-integration
```

### What the Aurora lane does not do

The kernel is pinned by commit. A new Aurora kernel is a new
`aurora-packages-<sha>` release, a new ISO pin, and a new payload; installed
rc Macs move only when the runtime pin above is bumped, never on their own.
Only Macs that opted into edge follow edge releases.

`test/vm/asahi-fresh` installs `linux-asahi` and boots a generic kernel, so it
proves the runtime tolerates the Aurora name but cannot exercise the kernel.
Aurora is qualified on real hardware.

### Removing the lane

Delete `pkgbuilds/linux-aurora`, `pkgbuilds/aurora-*`,
`bin/aurora-package-descriptor`, `test/aurora-package-descriptor` and
`.github/workflows/release-aurora-package.yml` from `omarchy-pkgs` (and the
aurora ignore rule in `bin/asahi-incremental-plan`); the `builder/*aurora*`,
`builder/branding/branding-manifest-aurora.json`,
`products/omarchy-mx-mac-aurora.json`, `*-arm-aurora.conf` and
`test/unit/aurora-product-test.sh` files from `omarchy-iso`; and
`bin/omarchy-hw-apple-kernel`, `bin/omarchy-update-aurora-repository` (and its
calls in `bin/omarchy-update-system-pkgs`), `bin/omarchy-update-aurora-verify`,
`default/libalpm/hooks/01-omarchy-aurora-verify.hook`,
`default/aurora-qualified-release`, `test/shell.d/aurora-*-test.sh`,
`test/shell.d/update-system-pkgs-aurora-test.sh`, the hook half of
`test/aurora-integration` and
`scripts/release-inputs-aurora.template.json` here. Everything else is a hook
that defaults to the Asahi behaviour (the
kernel name in the builder, orchestrator and verifiers; the per-kernel branding
manifest; the `-lane` suffix `publish-channels` accepts on release tags), so
reverting those files restores the previous lane exactly. Then drop
`channels/rc-aurora/` and the aurora release sets from R2 and the
`aurora-packages-*` releases from GitHub.

The m1n1 boot image embeds the kernel's device trees, so a new Aurora kernel
also needs a new `branding-manifest-aurora.json`: rebuild the image offline as
`m1n1.bin` + every `*.dtb` in the kernel package (sorted) + the gzip stream and
config tail of an existing `boot.bin`, brand it with the manifest's
replacements, and pin both digests. The same recipe reproduces the Asahi pins
byte for byte, which is how to check it.

## Gates and timings

| Step | Gate | Time |
| --- | --- | --- |
| candidate build | shell tests on the source commit; signing check; upgrade lifecycle (predecessor from its snapshot, upgrade against live) | 15 min incremental, 60 full |
| VM acceptance | fresh install, interruption/resume, reboot, verify, optional packages, rerun rejection | 10–15 min |
| promotion | acceptance file bound to the candidate identity; byte-identical copy | 2 min |
| package channel | stable and candidate verified; set descends from the current channel's; channel and pointer read back | 2 min |
| runtime channel | candidate verified; sequence strictly increasing; pointer read back | 2 min |
| payload | checkpointed stages; content evidence; drift gate between cache and repository | 60–90 min |
| publish + rc | readback of every object; catalog signature; sequence above the live channel | 15 min |

## Gotchas that cost a retry each

- macOS: `/bin/bash` is 3.2 (`mapfile`, `declare -A`, `${x,,}` fail),
  BSD `find` has no `-printf`, `sed -i` needs `''`, and the default disk is
  case-insensitive (`candidate/` collides with `CANDIDATE`). Run release
  scripts on the M1, or on this Mac under `/opt/homebrew/bin/bash` with
  `gnubin` first on `PATH` and `TMPDIR` on a case-sensitive volume.
- Helpers launched as `bash <script>` take whatever `bash` is first on `PATH`
  — put `/opt/homebrew/bin` first for the payload build.
- A GitHub release serves every tag's `omarchy.db` under one name with
  unordered upload times; repointing `[omarchy]` to an older tag makes pacman
  keep a stale database and reject it against the new signature. The installed
  pin writer drops the cache; the acceptance guest patches its packaged copy.
- `publish-r2` needs the tag pushed to `origin`, `--base-url` equal to the
  pinned `releases/<tag>` URL, and `OMARCHY_PUBLISH_ASSUME_YES=<exact tag>`
  when there is no terminal.
- Over ssh, `pkill -f omarchy-update` matches the ssh shell's own command
  line; exclude `$$` and `$PPID`.
- The acceptance guest and the gate need Arch Linux ARM in a state consistent
  with the candidate: pin the snapshot the candidate was accepted against,
  not the newest.
