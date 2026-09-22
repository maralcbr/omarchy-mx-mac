---
title: Architecture
description: The three repositories, the signed channels and the installer, and how they pin each other.
section: How it is built
---

Omarchy MX Mac is two repositories and a download host. The fork of Omarchy holds the desktop runtime, the Apple Silicon layer and the macOS installer app. The fork of omarchy-pkgs builds every aarch64 package, the Mac image and the release lanes. Cloudflare R2 serves the signed catalogs, installers and immutable releases.

{{diagram:repositories}}

## omarchy-mx-mac

[maralcbr/omarchy-mx-mac](https://github.com/maralcbr/omarchy-mx-mac) is a fork of [omacom/omarchy](https://github.com/omacom/omarchy) on a single maintained branch, `main`. Upstream is merged regularly. The layout is upstream's, with four fork-only areas:

| Area | Purpose |
| --- | --- |
| `apps/omarchy-apple-installer/` | The macOS installer: a SwiftPM package with the app, a root helper, trust and UX cores, and the pinned Asahi engine |
| `install/hardware/apple/` | Hardware fixes that only run when `omarchy-hw-apple-silicon` says the machine is an Apple Silicon Mac |
| `test/vm/` | The KVM acceptance harness that installs every candidate from scratch |
| `docs/`, `evidence/` | Design records, runbooks and the hardware evidence behind each release |

Changes to upstream files are gated by `omarchy-hw-apple-silicon`, so they stay inert on x86 and merge cleanly. General fixes go upstream; Apple-specific ones stay in the fork or in packages.

## omarchy-pkgs

[maralcbr/omarchy-pkgs](https://github.com/maralcbr/omarchy-pkgs) forks [omacom/omarchy-pkgs](https://github.com/omacom/omarchy-pkgs). The `master` branch mirrors upstream; all fork work is on `asahi-quattro`. It provides:

- **PKGBUILDs** for the runtime pair `omarchy-dev` and `omarchy-settings-dev` (built from a pinned omarchy-mx-mac commit), `omarchy-mac-boot`, the three `linux-aurora` lanes, `uboot-asahi`, the Limine hooks and every other aarch64 package that Omarchy's default set needs but Arch Linux ARM does not carry.
- **Release lanes** on GitHub's arm64 runners: incremental candidate builds, promotion, the runtime channel and the Mac image.
- **The `[omarchy]` repository** for aarch64, published as immutable GitHub releases with a channel pointer on R2.
- **The Mac image builder** that turns a promoted package set into the `root.img` and `boot.img` the installer writes.

## Cross-repository pins

Each repository pins the one before it by content, never by branch:

1. `pkgbuilds/omarchy-source.conf` in omarchy-pkgs names the omarchy-mx-mac commit that the runtime packages are built from.
2. The runtime channel release names the promoted package release it was accepted with.
3. The Mac image records the package channel, the runtime channel and every input digest in `PROVENANCE`.
4. The installer catalog names the image by URL and SHA-256, and the app checks the catalog signature and sequence before it downloads anything.

A change anywhere therefore produces a new artefact all the way down, and an old artefact can always be reproduced from its pins.

## What signs what

Nothing in the chain is trusted because of where it came from. Each step carries its own signature or digest, and each is checked on the user's Mac by something that was not downloaded alongside it.

{{diagram:trust-chain}}

The one key that matters most never leaves the owner's Keychain: the Ed25519 key that signs a channel catalog. Its public half is compiled into the installer app, so rotating it means shipping a new app rather than editing a file on the server.

## Distribution

`downloads.aicodelabs.com.au` is a Cloudflare R2 bucket:

```
channels/<channel>/catalog.signed.json   the signed catalog the app reads
channels/<channel>/channel.json          human-readable pointer
installer/<channel>/Omarchy-MX-Mac-Installer.pkg
installer/<channel>/installer.json
releases/<os-tag>/…                      immutable image, descriptors, signatures
installer/<version>/…                    immutable installer builds
mirror/alarm/<date>/                     the Arch Linux ARM snapshot used by image builds and acceptance
```

`releases/` is protected by a bucket lock. Only the channel and installer pointers change, and each change is a signed catalog with a larger sequence number than the last.

## Upstream

The fork tracks upstream Omarchy closely. Package recipes that make sense for every aarch64 user are contributed to omacom/omarchy-pkgs directly. Kernel fixes go to aurora-silicon/linux. Compositor fixes go to Hyprland and aquamarine. See [Upstream and contributing]({{page:upstream}}).
