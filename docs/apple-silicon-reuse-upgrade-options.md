# Reuse-and-upgrade an existing Omarchy: decided

Status: DECIDED by the owner, 2026-09-01 — **Option C only.**

## The decision

Upgrading or reusing an existing Omarchy install happens exactly one way:
**Replace** — the installer detects the existing install, the owner chooses
"Replace it" on the choice screen, and the approved plan removes the old
install and installs the new package into its space. This is implemented
(engine kind `"replace"`, catalog operation `"install"`, no schema change).

Rejected with this decision:

- **A. Owner-signed per-machine repair catalogs** — not part of the upgrade
  story. The schema-3 repair mechanism remains in the code only as the
  historical one-machine rescue path; it is not offered, extended, or used
  for upgrades.
- **B. In-place upgrade with locally derived identity** — not built. Its
  trust regression (the signed catalog would no longer cover *where* the
  write lands) is not accepted.

## What this means in practice

1. An "upgrade" is: run the new installer → choose Replace → fresh install of
   the new package into the old install's space. Data on the Omarchy side is
   not carried over; day-to-day updates on a running system remain the job of
   the in-Omarchy updater (`omarchy-update-asahi-bundle`).
2. No per-machine catalog signing sessions, no schema-4 work, no
   locally-derived in-place write path.
3. Optional future cleanup (separate, owner-approved change): retire the
   unused repair overlay/schema-3 surface once it is certain no rescue will
   need it. Nothing depends on doing this.

In short, the rejected options were: (A) sign a bespoke catalog for every
machine that needs an in-place fix — safe but unscalable; (B) let the engine
fingerprint the install locally and rewrite it in place — scalable but the
signature would no longer cover where the bytes land. C avoids both costs.
