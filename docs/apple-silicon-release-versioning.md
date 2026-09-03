# Apple Silicon release versioning

Status: adopted 2026-09-01 (owner-chosen format)
Scope: the Apple Silicon (`maralcbr/omarchy-mx-mac`) release lane only. The
Linux/x86 release workflow (`.github/workflows/release.yml`) keeps its
existing `vX.Y.Z-mac.N` tags and is unaffected.

## The scheme

Every Apple release is named by three components joined with dots:

```
v<omarchy version>.<installer number>.<package date MMDDYY>
```

| Component | Source of truth | Example | Moves when |
| --- | --- | --- | --- |
| omarchy version | the `version` file in this repo | `4.0.1-mac.2` | the Omarchy runtime/OS content changes |
| installer number | the installer app's number (from app version `0.<n>.0`) | `9` | the macOS installer app or helper changes |
| package date | build date of the OS payload, `MMDDYY` | `090126` | a new OS package is built |

Current release identity:

```
v4.0.1-mac.2.9.090126
```

## Where each form appears

| Surface | Value | Constraint honored |
| --- | --- | --- |
| Release tag | `v4.0.1-mac.2.9.090126` | `publish-m1-release:49` tag regex |
| Release title | `Omarchy MX Mac 4.0.1-mac.2.9.090126` | via the `--title` option in `publish-m1-release` |
| `.pkg` filename | `Omarchy-MX-Mac-Installer-4.0.1-mac.2.9.090126.pkg` | none (name is caller-chosen) |
| `.pkg --version` | `4.0.1-mac.2.9.090126` | `pkgbuild` accepts arbitrary strings |
| App `CFBundleShortVersionString` | `4.0.1-mac.2.9.090126` (the composite passes `build-app.sh:37`'s regex) | verified: `4.0.1` + `-mac` + `.2` + `.9` + `.090126` |
| App `CFBundleVersion` | integer counter, +1 every built app (currently 9, next 10) | `build-app.sh:39` requires a positive integer |
| Catalog `sequence` | epoch seconds at catalog generation (unchanged) | on-device rollback guard: never decreases |
| Catalog `engineVersion` | `v0.9.0-omarchy.N` (unchanged) | bound into the plan digest |
| Catalog `evidenceRevision` | `4.0.1-mac.2.9.090126` | lowercase `[0-9a-z.-]` only — satisfied |
| OS payload filename | `omarchy-2026.09.01-aarch64-apple-silicon-asahi-os-package.zip` (internal `YYYY.MM.DD` convention kept) | set in `builder/products/omarchy-mx-mac.json` in the ISO repo |
| Release notes header | first line names the full identity | convention only |

## Monotonicity rules

1. **The catalog `sequence` is the only machine-enforced guard** and stays
   epoch-seconds; every new signed catalog automatically satisfies the
   on-device rollback check. The tag is a human label, not a guard — note
   that `MMDDYY` does not sort naturally across years, which is fine because
   nothing machine-compares tags.
2. Each component must never move backwards in its own line: the omarchy
   version follows the repo `version` file; the installer number counts up;
   a later release must never reuse an earlier package date.
3. Two releases must never share a tag. If the same omarchy+installer pair
   ships a rebuilt payload the same day, suffix the date: `090126.2`.
4. `CFBundleVersion` increments by one for every app build that leaves the
   machine, independent of the composite.

## Reconciled / remaining pins

Reconciled on 2026-09-01:
- `Engine/source-lock.json` `full_os_payload` now names the `2026.09.01`
  payload with its true size and digest (was: `08.29` name with the `08.31`
  digest).
- `Engine/installer_data.json` is a byte copy of the `2026.09.01` payload's
  sidecar.
- `scripts/make-unsigned-catalog.py` pins the `2026.09.01` payload and
  `evidenceRevision 4.0.1-mac.2.9.090126`.

Resolved for v4.0.2-mac.1.13.090226 (engine `v0.9.0-omarchy.11` locked, `.12` shipped; `.10`/tag 1.12 could not enumerate an existing stub created under the helper's private umask; `.9` and tag 1.11 shipped an engine whose executables lost python.org's entitlements and could not launch):
1. `source-lock.json` was rekeyed to `v0.9.0-omarchy.8` with the replace and
   repair overlay files and their tests; two clean builds reproduce it.
2. The shipped `.9` comes from `scripts/resign-engine.sh` (the reusable form of
   the `.6` → `.7` procedure): prune the GUI and static-link components, drop
   dangling symlinks, re-sign every Mach-O (executables keep the entitlements in
   `Engine/python-executable.entitlements.plist`), re-seal the Python framework.
3. `Packaging/Info.plist` now carries the current version and build number.
