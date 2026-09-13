# Apple Silicon review integration

## Availability and hardware

Menu package conditions name complete explicit targets and use one sourceable `bin/omarchy-pkg-available`. Executing the command checks its arguments; sourcing it only defines the checker and process-local caches. The menu verifies the complete source loaded before dispatch. AUR conditions use architecture checks, not the sync database. Chrome and Edge remain x86-only. Test fixtures retain the supported ARM cases independently of current repository availability.

The Broadcom leaf explicitly skips Apple Silicon. Changing its former `&& return 0` to `||` would reverse the hardware exclusion. SPI detection tolerates missing or unreadable DMI while retaining its Intel model matches.

Keyring refresh now bootstraps the full pinned Omarchy fingerprint when needed, refreshes both Omarchy and platform packages, populates installed trust/revocation metadata and propagates failures. Presence alone is not treated as a completed update.

## Package-owned Apple Wi-Fi

Publish `omarchy-settings-asahi` from the companion package change before releasing this runtime. The architecture-specific add-on depends on the virtual `omarchy-settings` capability, so normal and development settings packages both satisfy it. The package owns `/usr/lib/NetworkManager/conf.d/wifi_backend.conf`; the installer and migration never replace administrator `/etc` configuration or restart networking. Fresh Apple profiles must include the add-on before offline hardware setup. Existing Apple users install it through a retryable migration from the signed sync repository.

The add-on has its own static source checksum and package version. It is a repository package, not a seventh member of the immutable six-package MX Mac runtime bundle. The package candidate and Apple image inputs must include it. Rebuild/promote the repository through the full candidate lane before publishing the matching runtime; the runtime-only fast lane cannot introduce this dependency.

## Channel qualification

`install/helpers/pacman.sh` defines configuration staging with no package transaction. Refresh preflights candidate databases and package targets in a temporary directory before backing up and replacing live configuration. Post-install finalization performs no synchronization.

Upstream ARM channels have an empty source-controlled qualification allowlist. To enable a channel, first publish or alias its ARM repository including the settings add-on, verify package signatures and dependency closure, and qualify upgrade, downgrade and reboot in a disposable Apple ARM VM. Record the exact tested package/source identities with the allowlist change. Edge returning a database is not qualification. Development uses the Edge repository and the same gate. Unavailable or unqualified channels are rejected before prompts, checkout changes or package operations.

MX Mac keeps its signed immutable repository/runtime and Aurora kernel pins. Upstream rolling-channel qualification does not enable rolling switching in the fork. Existing signed pins and offline repositories survive hardware setup. A failed package transaction is not rolled back by restoring a configuration backup; diagnose its package state before retrying.

## Acceptance and publication

Run CLI/menu cache and architecture fixtures, keyring failure cases, Intel/Apple hardware fixtures, package ownership/override checks and offline staging tests. Build the runtime/settings pair and settings add-on. Qualify the signed package candidate in a disposable VM, then verify effective NetworkManager configuration, Wi-Fi reconnect and reboot on physical Apple hardware before release. Fixture and package-content checks are not physical acceptance.

Prepare a response for all nine PR review threads. Source commits, package builds, PR publication, channel enablement and Stable/shared-feed promotion are separate recorded steps.
