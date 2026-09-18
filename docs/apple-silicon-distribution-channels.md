# Apple Silicon distribution channels

Status: adopted 2026-09-04. Replaces the per-release download folder with a
permanent link and a signed channel the installer reads at run time.

## Why this exists

Before this, the app was welded to one Omarchy release. Its bundled descriptor
named a single versioned folder, the signed catalog was sealed inside the app,
and the key that signed the catalog was destroyed straight after signing. A
change to the app, the engine, or the OS package therefore cost the same thing:
a new catalog, a new throwaway key, a rebuild, a notarization, and a new
download URL. Ten releases shipped that way in two days, nine of them for
reasons that had nothing to do with the operating system being installed.

Now the app is built once against a long-lived key, and a release is a small
signed file published to a channel.

## What lives where

Everything is served from `https://downloads.aicodelabs.com.au`.

| Key | Mutable | Holds |
| --- | --- | --- |
| `releases/<os-tag>/…` | no | payload, engine, `installer_data.json`, `SHA256SUMS`, `catalog.json`, `catalog.json.sig`, `catalog.signed.json` |
| `installer/<version>/Omarchy-MX-Mac-Installer-<version>.pkg` (+ `.sha256`) | no | one immutable installer build |
| `channels/<channel>/catalog.signed.json` | **yes** | the catalog that channel currently serves |
| `channels/<channel>/channel.json` | **yes** | which OS tag and sequence that is, for humans |
| `installer/<channel>/Omarchy-MX-Mac-Installer.pkg` | **yes** | the download the README links to |
| `installer/<channel>/installer.json` | **yes** | that package's version, digest and size |
| `mirror/alarm/<YYYYMMDD>/<repo>/os/aarch64/` | no | a dated copy of the Arch Linux ARM repositories, see below |
| `pointers/asahi-quattro-channel` | **yes** | the newest runtime channel installed Macs update to, see [the runtime channel pointer](#the-runtime-channel-pointer) |
| `pointers/asahi-packages-channel` | **yes** | the newest package channel installed Macs move `[omarchy]` to, see [the package channel](#the-package-channel) |

Exactly six mutable keys may ever be overwritten. The four `channels/` and
`installer/<channel>/` keys change only through `scripts/publish-channels`,
which refuses any other key and is covered by
`test/shell.d/apple-installer-channel-publish-test.sh`. The two pointer keys
change only through `bin/publish-asahi-channel-pointer` in `omarchy-pkgs`
(`--kind runtime` or `--kind packages`), run by its workflows.

`<channel>` is `stable` or `rc`. Nothing else is accepted anywhere in the
tooling or the app.

## Channel model

Decided 2026-09-17. `stable` and `rc` have followed it since 2026-09-18;
`edge` is not published yet.

| Channel | Kernel | How it moves |
| --- | --- | --- |
| `stable` | `linux-asahi` | Unchanged for now. Once Aurora is fully qualified, `rc` is promoted into `stable` and the Asahi kernel is retired. |
| `rc` | `linux-aurora` from `aurora-silicon/linux` branch `aurora-wip`, **pinned** to a commit qualified on real hardware | Moves only when a new pin passes hardware qualification. |
| `edge` | `linux-aurora` from `aurora-wip`, **floating** on the branch head | Follows each new build. |

The rename happened on 2026-09-18:

- `stable` was published for the first time with the signed Asahi release that
  `rc` served until then, `os-v4.0.3-mac.1.20260913`.
- Installer 2.0.5 defaults to `stable`. Earlier installers default to `rc`.
- `rc` and `rc-aurora` then moved to `os-v4.0.3-mac.2.20260913.2-aurora`. That
  is the hardware-qualified Aurora release, offering only `apple,j314s` and
  `apple,j416c`. Its catalog sets `installer.minimumVersion` to 2.0.5, so an
  older installer still on `rc` asks its user to download the current
  installer instead of silently installing Aurora.
- `rc-aurora` stays as an alias of `rc` for installers built before the
  rename, which list it by that name.

Installed Macs are unaffected. Each one records its channel from its installed
kernel (`linux-asahi` → `stable`, `linux-aurora` → `rc`, see
`bin/omarchy-apple-silicon-channel`) and updates through the runtime and
package channels, not through these installer catalogs.

### Edge, for now

- **Updater only.** An installed `rc` Mac opts into `edge`; there is no `edge`
  installer image. A full OS image per kernel is too large and slow to build
  for a lane that moves every day. Once the bootstrap installer exists (a small
  image that installs the packages on first boot), an `edge` install is simply
  the Aurora bootstrap pointed at `edge`.
- **Signing stays behind the `asahi-quattro-release` approval gate.** Each
  `edge` publish is approved after checking what changed upstream and that the
  build passed; the owner has delegated that approval to the agent working on
  their request. There is no unattended signing yet: one signing key signs
  every channel, and an automatic build would ship whatever `aurora-wip`
  receives, including a kernel that does not boot.
- **Before `edge` builds may sign themselves**, two things must exist: an
  edge-only signing key that only `edge` Macs trust, and a boot-health check
  that runs before a Mac moves to a new kernel.

### Revisit when omarchy-pool is adopted

[omarchy-pool](https://github.com/firemanxbr/omarchy-pool) brings release
rings, signed static delivery and a package factory, which is what `edge`
really wants. The choices above are interim. When omarchy-pool is adopted,
redesign `edge` on top of it: floating builds from its package factory,
ring-scoped signing instead of one key for every channel, and installer support
for `edge`.

## The runtime channel pointer

Installed Macs used to find the newest runtime channel
(`asahi-quattro-channel-<N>` releases in `maralcbr/omarchy-pkgs`) through the
anonymous GitHub API, which allows 60 requests an hour per IP address. Macs
behind a shared office address used that up, `omarchy-update-asahi-bundle`
exited 3, and `omarchy update` deferred the runtime step on every run.

`pointers/asahi-quattro-channel` names that channel instead. Its body is
exactly three lines, served as `text/plain` with
`Cache-Control: no-cache, max-age=0, must-revalidate`:

```
format=1
sequence=<N>
tag=asahi-quattro-channel-<N>
```

The pointer is not signed. It only decides which channel release to download;
the Mac still downloads the signed channel file from that GitHub release,
checks it with the release key, and requires its signed `sequence` to be `N`.
Every other check (pending migrations, rollback, reused sequence, package
signatures and versions) runs exactly as before.

`omarchy-update-asahi-bundle`, for both an update and `--check`:

| Pointer | What the Mac does |
| --- | --- |
| names `N` at or above what this Mac has installed or pending | uses `N`, no GitHub API call |
| missing or unreachable | reads the GitHub release listing, as before, without a message |
| malformed (anything but the exact bytes above, or over 256 bytes) | warns `release channel pointer is malformed; using the GitHub release listing`, then reads the listing |
| names `N` below what this Mac has installed or pending | warns that the pointer is behind this Mac, then reads the listing |

If the listing is also unavailable the update exits 3 and `omarchy update`
carries on without the runtime step, as it already did. A stale or malformed
pointer on its own never makes the update fail with 2; the listing fallback
still can, for the same reasons as before (a lower signed channel, a bad
signature, no channel, a pending mismatch). A signed-content failure on the
channel the pointer named stops the update; it does not retry through the
listing. `OMARCHY_ASAHI_CHANNEL_URL` skips the pointer and the listing
entirely, and `OMARCHY_ASAHI_CHANNEL_POINTER_URL` points the updater at a
different pointer.

What the pointer can and cannot do, accepted deliberately:

- **It can hold Macs back, never move them back.** Until the pointer moves, a
  Mac below its `N` updates to `N` and a Mac at `N` reports up to date, even if
  a newer channel exists. That includes a freshly installed Mac whose image
  predates `N`. A pointer held at a Mac's own channel looks exactly like "up to
  date", the same as a frozen GitHub listing would.
- **A pointer naming a channel that does not exist** makes updates defer
  (exit 3) until it is repaired.
- **Fresh installs read it too.** `install-omarchy-mx-mac` and the VM harness
  resolve the channel through the same pointer and only fall back to the
  listing; a pointer naming a channel that does not exist fails the install
  rather than silently pinning an old one.

Publishing and repairing it are in
[`apple-silicon-deployment.md`](apple-silicon-deployment.md#the-runtime-channel-pointer).

## The package channel

`omarchy-update-asahi-repository` moves the `[omarchy]` repository in
`/etc/pacman.conf` to the newest promoted package set,
`asahi-packages-stable-<commit>`. It used to find that set through the same
anonymous GitHub API, so Macs behind a shared address silently stayed on old
sets; on 2026-09-17 the M2 Max was still on its install-time set several runtime
releases later.

A promoted set is now announced by a signed, numbered GitHub release,
`asahi-packages-channel-<S>`, published by `publish-asahi-packages-channel.yml`
in `omarchy-pkgs`. It holds the file `asahi-packages-channel`, signed with the
release key (`.sig`):

```
format=1
channel=asahi-packages
sequence=<S>
stable_tag=asahi-packages-stable-<commit>
descriptor_sha256=<sha256 of that release's CANDIDATE>
supersedes=<commit>,<commit>,…
```

`supersedes` lists every older promoted set whose commit is an ancestor of
`<commit>` on `asahi-quattro`, including the legacy install-time
`asahi-packages-<commit>` release, sorted, and may be empty. It is the Mac's proof
that a move goes forward, so the Mac needs neither git nor the API. The file
must be exactly these six lines in this order, with no other bytes, at most
128 KiB and 2048 `supersedes` entries.

`pointers/asahi-packages-channel` names the newest channel in the same
three-line form as the runtime pointer, with `tag=asahi-packages-channel-<S>`.
Publishing and repairing both are in
[`apple-silicon-deployment.md`](apple-silicon-deployment.md#the-package-channel).

### Finding the channel

`omarchy-update-asahi-repository`, for both an update and `--check`:

| Pointer | What the Mac does |
| --- | --- |
| names `S` at or above the channel this Mac recorded | uses `S`, no GitHub API call |
| missing or unreachable | reads the GitHub release listing, without a message |
| malformed (anything but the exact bytes, or over 256 bytes) | warns `package channel pointer is malformed; using the GitHub release listing`, then reads the listing |
| names `S` below the channel this Mac recorded | warns that the pointer is behind this Mac, then reads the listing |

The listing picks the highest non-draft, non-prerelease
`asahi-packages-channel-<S>`, reading at most five pages. If it cannot be read
or holds no package channel, the update exits 3 and `omarchy update` carries
on with the pinned set. It never falls back to picking a stable release from
the listing. `OMARCHY_ASAHI_PACKAGES_CHANNEL_URL` reads that channel file
directly, with no pointer, no listing and no tag to match `S` against;
`OMARCHY_ASAHI_PACKAGES_POINTER_URL` points the updater at a different pointer.

The channel is then checked before anything else happens: its signature against
the release key, its exact format, and that release
`asahi-packages-channel-<S>` really carries `sequence=<S>`. A failure there
exits 2 and does not retry through the listing.

### When `[omarchy]` moves

The Mac records the channel it last followed as `channel_sequence` in
`/var/lib/omarchy/asahi-package-repository`. Only an update writes it, and never
lowers it. A channel below that number moves nothing, whatever it lists.
Otherwise the result depends on the `Server` line actually in `[omarchy]`:

| Current `Server` | Result |
| --- | --- |
| the stable release the channel names | up to date; the channel and its descriptor are still checked, and an update records the channel |
| a stable or legacy release whose commit is in `supersedes` | moves: descriptor and database checks, backup, cached `omarchy.db`/`.sig` dropped, rewrite of that one line, `pacman -Sy`, restore on failure |
| the legacy release of the channel's own commit | moves to the stable release of that commit, the same way |
| any other stable or legacy release | left alone: `the pinned package set <commit> is not older than channel <S> (<commit>); leaving it` |
| anything else: a mirror, a candidate or channel tag, another repository | left alone: `unrecognised [omarchy] Server; not moving it` |

Up to date and left alone both give `--check` 1 and update 0, and nothing is
written for a set that is left alone. `--check` never writes. A set is only
recognised at exactly
`https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-packages-stable-<commit>`
(stable) or `…/releases/download/asahi-packages-<commit>` (legacy). The legacy
form is what `install/hardware/pacman.sh` writes when it has nothing better
(see below); a Mac that ran its migration but never reached the old API updater
can also still be on it. Moving off it keeps the block's `SigLevel` and imports
and locally signs the ARM repository key, exactly as the old updater did.
Before a move or a refresh, that release's `CANDIDATE` must hash to
`descriptor_sha256` and pass the same subkey and field checks as before. If the
state file names the channel's set with another descriptor digest, or records
the same channel number for another set, the update exits 2 instead of
overwriting it. Build run numbers no longer decide anything, and state files
written before the channel existed are still read.

What this accepts, deliberately:

- **A pointer can hold Macs back, never move them back**, as with the runtime
  pointer. Held at a Mac's own channel, it reads as up to date.
- **Custom mirrors and hand-pinned sets are never moved.** Put the `Server`
  back on a set the channel supersedes to follow it again.
- **The guarantee is source lineage, not version order.** A move always goes to
  a set built from a later commit on `asahi-quattro`; that does not prove every
  package version went up.

### A fresh install's `[omarchy]`

A clean Asahi Arch Minimal has no `[omarchy]` section, and its first package
transaction needs one ahead of `[asahi-alarm] [core] [extra] [alarm] [aur]`:
without it every Omarchy-built package is "target not found", and below
`[extra]` Hyprland comes from Arch Linux ARM. So `bin/omarchy-install-asahi-fresh`,
after its checkpoint, user, terminal and lock checks and before that
transaction, unpacks `omarchy-dev` and `omarchy-settings-dev` from the verified
bundle into a private directory and runs their own
`omarchy-update-asahi-repository --yes --bootstrap`. Only that command sees a
root-only `sudo` stand-in (real `sudo` is not installed yet) and the bundle's
`default/` key files. `jq` is a precondition, which is why the README's
preparation step installs it.

`--bootstrap` runs every check of an ordinary update: discovery, the channel's
signature and format, the descriptor and its signature, and the database's
digests and signature, including when the pin is up to date or kept. Then:

| `[omarchy]` in `/etc/pacman.conf` | Result |
| --- | --- |
| no section | the channel's stable set, inserted before the first repository section |
| one section with one `Server` (or byte-identical copies) | that `Server` is kept, then the ordinary move rules apply: a superseded pin moves forward, a candidate, mirror or newer pin stays. The section is moved before the first repository and gets `SigLevel = Required DatabaseOptional` |
| several sections, several different `Server` lines, or none | refused, naming them; nothing is written |

In every accepted case both the release key (`5983B1CA…`, for legacy and
candidate releases) and the ARM repository key (`C81AC3E2…`, for stable sets)
are added and locally signed, the cached database is dropped if the `Server`
changed, and `pacman -Sy` must succeed with `omarchy` first in
`pacman-conf --repo-list`, or the backup is restored. The state file is written
only when the final `Server` is the channel's stable set, never for a kept
candidate or mirror. The installer then checks the order itself and exports the
final `Server` as `OMARCHY_ASAHI_KEEP_SERVER` for the rest of the run.

### The install-time `[omarchy]` pin

`install/hardware/pacman.sh` writes the `[omarchy]` block during system setup
(`install/hardware/all.sh`, `install/post-install/pacman.sh`) and again on
every existing Mac through migration `1787560726`. It repairs the section
where it stands, around the `Server` that is already there, rather than
replacing it:

| `[omarchy]` in `/etc/pacman.conf` | Result |
| --- | --- |
| one recognised `Server`, or several byte-identical copies of one | that `Server` is kept; the section, its `SigLevel` and the key trust are repaired around it |
| one `Server` byte-identical to `OMARCHY_ASAHI_KEEP_SERVER` | kept the same way; only the fresh installer sets it |
| several `Server` lines that are not identical | refused, naming them; nothing is written |
| more than one `[omarchy]` section | refused; nothing is written |
| exactly one other `Server` | replaced with the bootstrap default, in place |
| no section at all | the bootstrap default, inserted before the first repository section, never appended after `[aur]` |

Recognised means exactly the two forms the package channel moves,
`…/releases/download/asahi-packages-stable-<commit>` and
`…/releases/download/asahi-packages-<commit>`. The release key is added and
locally signed in every case, and the cached `omarchy.db`/`.sig` are dropped
only when the `Server` actually changes.

The bootstrap default stays the legacy `asahi-packages-784daa3…` release, but
only paths with no `[omarchy]` and no package channel reach it: a fresh install
has already configured the promoted set by then. It is signed by the release
key and it is in every package channel's `supersedes`, so the first
`omarchy update` moves such a Mac to the promoted set.

The effect is that a Mac the package channel already moved forward keeps its
set when the migration reruns, instead of being pinned backwards and moved
forward again on the next update, and a fresh install keeps the set, candidate
or mirror its bootstrap kept.

### What still reads the GitHub API

Five files, each only as the fallback behind a pointer:

- `bin/omarchy-update-asahi-bundle` and `bin/omarchy-update-asahi-repository`,
  behind the runtime and package channel pointers.
- `install-omarchy-mx-mac`, behind the runtime channel pointer. With neither
  resolvable the install fails rather than silently pinning an old release.
- `test/vm/asahi-fresh/guest/install`, behind the same pointer.
- `test/vm/asahi-fresh/run`, behind the package channel pointer, to resolve
  the channel it hands the guest and the stable set it expects.

`install-omarchy-mx-mac.sh` resolves nothing itself. It downloads the
bootstrap from the mx-mac `releases/latest` assets, creates an empty handover
file, exports `OMARCHY_ASAHI_CHANNEL_IDENTITY_FILE` and runs the bootstrap
twice with the same arguments: once with `--verify-only`, then to install. The
first run records the selection it made in that file
(`format=1`, `selector=release|channel|base-url`, `value=…`) and the signed
installer appends the `release_tag=` it resolved. The second run installs what
the first verified: a pointer that advanced in between changes nothing, an
explicit override that differs between the runs is refused, and a verification
run whose installer recorded no release refuses to install rather than drift.

## The signed envelope

`catalog.signed.json` carries the catalog and its signature together:

```json
{"schema_version":1,"catalog":"<base64 catalog bytes>","signature":"<base64 64 bytes>"}
```

The signature is still made over the raw catalog bytes, so the verifier in the
app is unchanged and the immutable `catalog.json` + `catalog.json.sig` pair
stays published for audit. The reason for one object is atomicity: a channel
update is a single write, so a reader can never see a new catalog beside the
previous signature.

## Catalogs do not expire

Catalog schema 4 has no `expiresAt`. A signed catalog stays valid until a
higher-sequence one replaces it, and the monotonic `sequence` is the only
machine-enforced guard. Schema 4 also drops the "issued in the past" check, so
a Mac whose clock has not yet reached a time server still installs.

The trade-off, accepted deliberately: someone able to serve an old but validly
signed catalog can hold a *first-time* installation on an old release. Once a
Mac has accepted a newer catalog, the sequence guard refuses anything older.

## The signing key

One long-lived Ed25519 key signs both channels. It lives in the operator's
login keychain as a generic password under the service
`omarchy-channel-signing-key`, and it is never written to disk on the signing
path.

### Creating it, once

Run this on the signing Mac, with an encrypted disk image mounted at
`/Volumes/Omarchy-Signing`:

```bash
cd apps/omarchy-apple-installer
xcrun swift scripts/catalog-signing.swift generate \
  /Volumes/Omarchy-Signing/trust-root.key /Volumes/Omarchy-Signing/trust-root.ed25519.pub
xcrun swift scripts/catalog-signing.swift import-keychain \
  /Volumes/Omarchy-Signing/trust-root.key omarchy-channel-signing-key
```

`import-keychain` prints the fingerprint and refuses to replace an existing
key, because overwriting it would strand every app already built against the
old public key. Keep the disk image offline as the only backup, write the
fingerprint down, then remove the on-disk copy with `rm -P`.

Generate the app's descriptor from the public key and commit both files to
`apps/omarchy-apple-installer/Release/`:

```bash
scripts/make-release-descriptor \
  --public-key /Volumes/Omarchy-Signing/trust-root.ed25519.pub \
  --base-url https://downloads.aicodelabs.com.au \
  --output Release/release.json
cp /Volumes/Omarchy-Signing/trust-root.ed25519.pub Release/
```

The descriptor names both channels even while only `stable` is in use. The app
is signed and notarized once, so a channel that is not in the descriptor cannot
be opened later without shipping another signed app.

The helper code-signing requirement in the descriptor must match the build that
will consume it, and `build-app.sh` refuses a mismatch. Pass `--adhoc` to write
the identifier-only requirement an ad-hoc local build uses; omit it for the
production Developer ID build.

### Rotating it

Rotation is a new app release, because the public key is inside the signed
bundle. Publish the new key's channel under a new prefix
(`channels/stable-k2/…`), ship an app whose descriptor names it, and keep the
old channel served until the old installers are retired. If the key is believed
compromised, delete the channel objects first so nothing is served at all, then
rotate.

## R2 quirks worth knowing

R2 speaks the S3 protocol, so the AWS CLI is the client, but it does not
implement every S3 call:

- **Server-side copies do not work at all.** `aws s3 cp s3://… s3://…` first
  fails on `GetObjectTagging` (`NotImplemented`); `--copy-props none` gets past
  that, and small objects then fail on `CopyObject` with `Header
  'x-amz-tagging-directive' with value 'REPLACE' not implemented`. Large objects
  take the multipart path and avoid the header, so a copy can half-succeed.
  Upload from a local file instead — a plain `PutObject` has none of these
  problems, which is why `publish-channels` never hits them.
- **Published objects are locked by a bucket policy.** The bucket carries an R2
  lock rule, `immutable-releases`, on the `releases/` prefix. Overwriting one
  fails with `ObjectLockedByBucketPolicy` on `CompleteMultipartUpload`, and
  deleting one fails the same way on `DeleteObject`. This is the never-clobber
  rule enforced by the storage itself rather than by the tooling, so any step
  that republishes must skip what is already present at the right size, and a
  genuine content change needs a new tag. The rule's condition decides whether
  `prune` can ever run: `Indefinite` means nothing under `releases/` is ever
  removable; an age condition (for example 7 days) keeps a fresh release
  immutable through its promotion window and lets `prune` reclaim it later.
  `installer/<version>/` is outside the rule and follows the tooling's own
  never-clobber check only.

## Runbooks

The end-to-end sequence, including the runtime fast lane, is
[`apple-silicon-deployment.md`](apple-silicon-deployment.md); the sections below cover the channel tooling itself.

### Release the app

```bash
cd apps/omarchy-apple-installer
OMARCHY_APP_VERSION=2.0.0 OMARCHY_APP_BUILD_NUMBER=20 \
  OMARCHY_APP_SIGNING_IDENTITY="Developer ID Application: …" OMARCHY_TEAM_ID=T2C384FJBD \
  Packaging/build-app.sh "$PWD/Release" /tmp/app
OMARCHY_NOTARY_PROFILE=omarchy-notary Packaging/notarize-app.sh "/tmp/app/Omarchy MX Mac Installer.app"
Packaging/pkg/build-pkg.sh --app "/tmp/app/Omarchy MX Mac Installer.app" --version 2.0.0 --out /tmp/Installer.pkg
xcrun notarytool submit /tmp/Installer.pkg --keychain-profile omarchy-notary --wait
xcrun stapler staple /tmp/Installer.pkg
scripts/publish-channels app-publish --pkg /tmp/Installer.pkg --version 2.0.0 --to rc
# test on real hardware, then:
scripts/publish-channels app-publish --pkg /tmp/Installer.pkg --version 2.0.0 --to stable
```

`app-publish` refuses a package that is not signed and stapled, and refuses to
rewrite an immutable version with different bytes.

### Release an OS package

```bash
cd apps/omarchy-apple-installer
scripts/publish-m1-release prepare --payload … --engine … --metadata Engine/installer_data.json \
  --tag os-v4.0.2-mac.1.20260902 --base-url https://downloads.aicodelabs.com.au/releases/os-v4.0.2-mac.1.20260902 \
  --out-dir /tmp/dist --no-split
python3 scripts/make-unsigned-catalog.py --base-url … --assets-dir /tmp/dist \
  --inputs scripts/release-inputs.template.json --output /tmp/catalog/catalog.json
xcrun swift scripts/catalog-signing.swift sign-keychain omarchy-channel-signing-key \
  /tmp/catalog/catalog.json /tmp/catalog/catalog.json.sig
scripts/publish-channels envelope --catalog /tmp/catalog/catalog.json \
  --signature /tmp/catalog/catalog.json.sig --output /tmp/catalog/catalog.signed.json
scripts/publish-m1-release publish-r2 --dir /tmp/dist --catalog-dir /tmp/catalog \
  --tag os-v4.0.2-mac.1.20260902 --bucket omarchy-releases \
  --endpoint https://ab85a8b9d88f084e66bf9d4a8ee5cf66.r2.cloudflarestorage.com \
  --base-url https://downloads.aicodelabs.com.au/releases/os-v4.0.2-mac.1.20260902
scripts/publish-channels os-promote --tag os-v4.0.2-mac.1.20260902 --to rc
# test on real hardware, then:
scripts/publish-channels os-promote --tag os-v4.0.2-mac.1.20260902 --to stable
```

Nothing about the app changes. `os-promote` verifies the signature against the
committed public key, proves every artifact the catalog names is already
published at the size the catalog claims and sits under that tag's own prefix,
and requires the sequence to exceed what the channel already serves.

Per-release values live in `scripts/release-inputs.template.json`, not in the
generator, so cutting a release never edits a script.

### Switch a Mac to the rc channel

From the app, use *Release Channel* in the menu bar. From a terminal:

```bash
defaults write com.omarchy.mx.installer ReleaseChannel rc
```

`defaults delete com.omarchy.mx.installer ReleaseChannel` returns to the
descriptor default. An unknown value is ignored rather than honoured. Each
channel records the release it last accepted separately, so moving back to
stable is not treated as a downgrade.

### Remove what nothing references

```bash
scripts/publish-channels prune            # plan only
scripts/publish-channels prune --confirm  # delete
```

A release set (`releases/<tag>/`) stays as long as any channel's catalog names an artifact under
it, or a channel's `channel.json` records it as `previous_os_tag` — the set that channel served
just before its current release. That one stays because rolling back re-signs a catalog over an
older set's URLs and those must still exist. An installer version (`installer/<version>/`) stays
as long as any channel's `installer.json` points at it. Everything else under those two prefixes
is deleted. A never-promoted candidate set is not rollback material and goes.

`os-promote --to stable` runs this prune itself once the promotion has been verified, so
cleanup happens at the moment the old release stops mattering; pass `--no-prune` to skip it. A
bucket lock that still protects the old set is reported after the promotion, never treated as a
failed release. Channel objects, the channel pointers, the stable/rc/edge downloads, the Arch Linux ARM snapshots
under `mirror/`, and folders published by other lanes (the generic ISO releases) are never candidates, and the
references are re-read immediately before each deletion so a promotion in between cannot be
undone by a stale plan.

### Check what is live

```bash
scripts/publish-channels channel-status --channel all
```

### Roll a channel back

A byte copy of an older catalog is the wrong move: its sequence is lower, so
every Mac that already accepted the current one refuses it while fresh Macs
accept it, splitting the fleet. Instead regenerate a catalog over the older
artifact URLs with a new, higher sequence, sign it, publish it under the old
tag's prefix, and promote that.

## The Arch Linux ARM snapshot

Arch Linux ARM keeps no dated snapshots of its repositories, and its mirrors are
push-synchronised, so every one of them shows the same state at once. While a
library transition is in flight there (`aquamarine` rebuilt for a new soname
before `hyprland` was, 2026-09-04), nothing that installs a desktop from the live
mirrors can succeed, and that includes the payload build and the VM acceptance
gate, neither of which has anything to do with the change. Both therefore read
Arch Linux ARM from a dated, immutable copy in the bucket instead:

```
mirror/alarm/<YYYYMMDD>/<repo>/os/aarch64/     repo = core, extra, alarm, aur
```

as `Server = https://downloads.aicodelabs.com.au/mirror/alarm/<YYYYMMDD>/$repo/os/$arch`.
A snapshot is never modified; a new date is a new prefix. It is not under
`releases/`, so the bucket's age lock does not apply to it, and `publish-channels
prune` never touches `mirror/`: a snapshot stays until it is removed by hand, and
the one the current rc and stable payloads were built against must stay.

Who reads it: `omarchy-iso/configs/pacman-online-arm.conf` (the payload build) and
`test/vm/asahi-fresh` (the acceptance guest). Installed Macs do not: they keep
the live mirrors, as `pacman-online-installed-arm.conf` says, and `omarchy update`
reports a mirror mid-transition as exactly that rather than as a failure.

| Snapshot | Taken from | Pinned by | Notes |
| --- | --- | --- | --- |
| `20260906` | `ca.us.mirror.archlinuxarm.org`, 2026-09-06 | payload `2026.09.06`, acceptance of `asahi-packages-candidate-f701b12` | plain copy: ALARM's aquamarine `0.15.0-2`; hyprland/hyprtoolkit now come from `[omarchy]` (built against it), so no substitution. Made as an R2 server-side copy of `20260905` plus the 134 changed files |
| `20260905` | `ca.us.mirror.archlinuxarm.org`, 2026-09-05 | payload `2026.09.05`, acceptance of `asahi-packages-candidate-5a3a266d` | `extra` carries `aquamarine 0.14.0-2` (provides `libaquamarine.so=13`) in place of the live `0.15.0-2`, so `hyprland 0.56.1-3` and `hyprtoolkit 0.5.4-5` resolve; the databases were regenerated with `repo-remove`/`repo-add`, every package keeps its Arch Linux ARM signature |

Taking one: `rsync -rtL` each repository from a mirror's `rsync://…/archlinuxarm/aarch64/<repo>/`
(dereferencing the `.db`/`.files` symlinks, skipping `*.old`), apply whatever
substitution the date needs with `repo-remove`/`repo-add` in an Arch Linux ARM
container, prove the desktop resolves against `file://` copies of the result, then
`aws s3 sync` into the dated prefix. The whole set is about 55 GB, which is under
a dollar a month at R2's rates; drop a date once nothing served or built pins it.

## Which change costs what

| Change | What ships |
| --- | --- |
| Installer UI or behaviour | a new app build: `app-publish` to rc, then stable |
| Engine planning or install fix | a catalog only: sign, publish, `os-promote`. No rebuild, no notarization |
| Engine inspection fix | a new app build, because the bundled engine runs before any download |
| New OS payload | a full OS release, then `os-promote` |

The bundled engine and the catalog's engine are deliberately allowed to differ.
Nothing may reintroduce a check that they match.
