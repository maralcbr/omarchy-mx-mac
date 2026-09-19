echo "Let systemd-oomd kill a runaway app on Apple Silicon"

# Apple Silicon installs skipped 1785424256 while systemd-oomd was unvalidated
# on Asahi, so they still run without an OOM daemon. Everywhere else that
# migration already enabled it.
omarchy-hw-apple-silicon || exit 0

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# Machine-wide, so a second user on the same box finds it already done.
if systemctl is-enabled --quiet systemd-oomd.service 2>/dev/null; then
  # oomd reads /usr/lib/systemd/oomd.conf.d/ only at startup, so restart it to
  # pick up the thresholds the settings package just delivered.
  as_root systemctl try-restart systemd-oomd.service >/dev/null 2>&1 || true
else
  as_root systemctl enable --now systemd-oomd.service >/dev/null 2>&1 ||
    echo "Could not enable systemd-oomd.service; memory pressure will still take the session down."
fi

# Report app.slice candidacy from /etc/systemd/user/app.slice.d/10-oomd.conf
# without waiting for the next login.
systemctl --user daemon-reload >/dev/null 2>&1 || true
