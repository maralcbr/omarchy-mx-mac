# Maintaining Omarchy Mac

This fork keeps Omarchy usable on Apple Silicon through Asahi ALARM. The goal is to combine official Omarchy updates with the Arch Linux ARM and Asahi ALARM package stack.

## Remotes

Use these remotes in the development clone:

```bash
origin            https://github.com/maralcbr/omarchy-mx-mac.git
upstream-omarchy  https://github.com/basecamp/omarchy.git
asahi-alarm       https://github.com/asahi-alarm/asahi-alarm.git
```

Fetch official Omarchy without importing tags into the normal tag namespace:

```bash
git fetch upstream-omarchy --no-tags master dev rc
```

Official Omarchy tags can point to different commits than historical Omarchy Mac tags. Keep Mac releases in the `v<omarchy-version>-mac.<n>` namespace, for example `v3.8.2-mac.1`.

## Release Flow

1. Create a sync branch from `main`.
2. Fetch official Omarchy with `--no-tags`.
3. Merge the official release commit or branch into the sync branch.
4. Resolve conflicts by preserving Asahi ALARM and Apple Silicon behavior.
5. Run shell syntax checks and the tests under `tests/`.
6. Merge to `main`.
7. Tag the release as `v<upstream-version>-mac.<n>`.
8. Push `main` and the Mac release tag.

## Asahi ALARM Updates

Asahi ALARM is updated by pacman through the configured `[asahi-alarm]` repository. `omarchy-update` runs `sudo pacman -Syyu --noconfirm`, so kernel, firmware, Mesa, Vulkan, and related Asahi ALARM packages update through package repositories instead of git merges.

Track https://github.com/asahi-alarm/asahi-alarm for repository, keyring, mirror, and installer changes.

## Critical Guardrails

- Keep `/etc/pacman.conf` defaults on `Architecture = aarch64`.
- Keep `[asahi-alarm]` configured before Arch Linux ARM repositories.
- Keep Mac release tags separate from official Omarchy tags.
- Do not make `omarchy-reinstall-git` clone `basecamp/omarchy` directly.
- Test update and reinstall behavior on Apple Silicon before publishing a release.
