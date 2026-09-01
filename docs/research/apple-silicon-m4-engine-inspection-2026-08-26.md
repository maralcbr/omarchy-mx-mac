# Locked engine M4 read-only inspection

## Scope

This is validation evidence for the downstream Asahi `inspect` mode only. It is
not an install, support enablement, physical acceptance result, or release
artifact. The run did not reach partition enumeration because the exact model
is unsupported by the pinned Asahi source.

## Bound inputs

- Engine version: `v0.9.0-omarchy.1`
- Archive size: `22075118` bytes
- Archive SHA-256: `4658124ad75436289bd984fc4f06092bd04aa128144e954b968df62f7fb75d7a`
- Asahi installer commit: `f0469cea0899f3efed8efead604174c7a53c4451`
- Installer-data commit: `42648e71423eba308d2e3e6228253eff679b068b`
- Mode: `inspect`
- Environment: private temporary extraction root, closed PATH, no standard
  input, no expert mode, no authorization or mutation adapter

## Result

The engine emitted one schema-v1 record and exited with status 1, matching the
upstream unsupported-device path:

```json
{"payload":{"device_identifier":"apple,j614s","support":"unsupported"},"schema_version":1,"sequence":1,"type":"inspection"}
```

Transcript SHA-256:
`ec3e6f20ac317c6228f6dd8cd39ef3f5c4e894db1c622e7b8f46db547b577a36`.

The sanitized transcript is retained as
`apps/omarchy-apple-installer/Tests/OmarchyAppleInstallerTests/Fixtures/asahi-v0.9.0-m4-unsupported.jsonl`.
The private full run remains on the validation Mac at
`/tmp/omarchy-engine-readonly.lbxDVN`; it may disappear on reboot and is not a
release evidence store.

## Interpretation

This proves that the corrected reproducible archive launches on the M4 and
fails closed at exact-model admission. It also confirms that the pinned Asahi
v0.9.0 source cannot support or enable this M4. It does not exercise disk
inventory, planning, APFS preparation, recoveryOS, firmware, boot policy,
handoff, media boot, installation, reboot, update, or rollback.

The official Asahi installer `main` source checked on 2026-08-26 also lists
device support only through M3 and does not contain `j614s`, so there is no
newer official M4 admission record to repin:
<https://github.com/AsahiLinux/asahi-installer/blob/main/src/main.py>.
