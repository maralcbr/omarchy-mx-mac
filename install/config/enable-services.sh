# Enable services only. Installs are followed by reboot, so don't start/reload
# daemons mid-install. UFW and hardware-gated services stay in their own scripts.
systemctl enable cups.service
systemctl enable cups-browsed.service
systemctl enable avahi-daemon.service
systemctl enable linux-modules-cleanup.service
systemctl enable docker.socket
systemctl enable systemd-resolved.service
systemctl enable NetworkManager.service
# Don't let network-online.target (pulled in by cups-browsed) hold up
# graphical.target waiting for DHCP/Wi-Fi association. Nothing in the session
# needs to block on the network. Mirrors the systemd-networkd-wait-online mask
# in install/hardware/network.sh.
systemctl mask NetworkManager-wait-online.service
systemctl enable power-profiles-daemon.service

# Older installs claimed tty1 directly. Retire that path before enabling SDDM,
# including on a fresh install over a system with leftover Omarchy state.
if [[ -e /etc/systemd/system/omarchy-seamless-login.service ||
  -L /etc/systemd/system/graphical.target.wants/omarchy-seamless-login.service ||
  -e /usr/local/bin/seamless-login ]]; then
  systemctl disable omarchy-seamless-login.service >/dev/null 2>&1 || true
  rm -f \
    /etc/systemd/system/graphical.target.wants/omarchy-seamless-login.service \
    /etc/systemd/system/omarchy-seamless-login.service \
    /etc/systemd/system/getty@tty1.service.d/autologin.conf \
    /etc/systemd/system/plymouth-quit.service.d/wait-for-graphical.conf \
    /usr/local/bin/seamless-login
  systemctl daemon-reload
fi
systemctl enable sddm.service
if ! omarchy-hw-apple-silicon; then
  # [Install] also enables the socket that reports app.slice candidacy.
  systemctl enable systemd-oomd.service
fi
