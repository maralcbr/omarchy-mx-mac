# The Asahi Arch Minimal base ships /etc/locale.conf with LANG=C, and only the
# built-in C/C.utf8/POSIX locales are generated. System services then run in a
# non-UTF-8 locale (SDDM/Qt warn and substitute C.UTF-8 on their own), so seed
# the neutral UTF-8 default when no regional UTF-8 locale is configured.
#
# Direct write rather than localectl: this runs in install contexts (ISO
# chroot, fresh-install finalization) with no dbus/systemd-localed available.
if [[ -r /etc/locale.conf ]] && grep -Eqi '^LANG=.*\.(UTF-8|utf8)$' /etc/locale.conf; then
  return 0
fi

printf 'LANG=C.UTF-8\n' >/etc/locale.conf
