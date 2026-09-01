# Installer release inputs

Production packaging must place these two immutable files in
`Omarchy MX Mac Installer.app/Contents/Resources/Release/`:

- `release.json` — strict schema version 1 descriptor containing the HTTPS
  catalog and signature URLs, expected Ed25519 trust-root fingerprint, helper
  Mach service name, and helper code-signing requirement.
- `trust-root.ed25519.pub` — exactly 32 raw Ed25519 public-key bytes matching
  the descriptor fingerprint.

The app rejects missing, symlinked, group/world-writable, oversized, unknown,
or mismatched release inputs. Do not commit a private signing key here. The
catalog signature is fetched separately as exactly 64 raw bytes and verified
before any model is admitted or artifact is downloaded.
