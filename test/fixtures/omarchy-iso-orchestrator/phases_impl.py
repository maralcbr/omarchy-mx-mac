# Vendored from maralcbr/omarchy-iso@268bac16d351a21d867e37565738f458b11cb06c (quattro)
# Source: configs/airootfs/usr/share/omarchy-iso/orchestrator/phases_impl.py
# Phase list and run_system_finalizer only — the Snapper-delegation contract.

"""Concrete phase implementations.

Phase ordering (full-disk and protected/pre-mounted):

    prepare_live           → disk cleanup when wiping, load configurator
                             handlers (archinstall patch happens in the
                             wrapper before Python imports it)
    prepare_install_target → verify pre-mounted target/ESP when the JSON uses
                             pre_mounted_config; no-op for full-disk installs
    arch_install_system    → one archinstall flow for partition/mount-or-use,
                             base install, early Omarchy packages, Limine setup,
                             useradd, runtime Omarchy packages, fstab
    configure_hibernation  → root-owned swap/resume drop-ins
    run_system_finalizer   → arch-chroot root omarchy-apply-system, including Snapper
    finalize_limine_boot   → final Limine config/UKI build after hardware drop-ins
    run_chroot_finalizer   → arch-chroot -u user omarchy-provision-user
    configure_login        → sddm state + encrypted-install autologin
    configure_ssh_access   → authorized_keys for autoinstall; no-op otherwise
    configure_tailscale    → tailnet join staged for first boot; no-op otherwise
    validate_boot          → assert UKI / limine.conf / kernel cmdline are sane
"""


def run_system_finalizer(ctx: InstallContext) -> None:
    if ctx.defer_provisioning:
        cmd = ["/usr/bin/omarchy-apply-system", "--defer-provisioning", "--first-install"]
    else:
        cmd = ["/usr/bin/omarchy-apply-system", "--install-user", ctx.username, "--first-install"]

    _mask_mkinitcpio_pacman_hooks(ctx, ctx.target, TARGET_DEFERRED_BOOT_HOOKS)
    try:
        _run_target_setup_command(ctx, cmd)
    finally:
        _unmask_mkinitcpio_pacman_hooks(ctx, ctx.target, TARGET_DEFERRED_BOOT_HOOKS)
