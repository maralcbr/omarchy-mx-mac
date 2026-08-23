echo "Set the system locale to UTF-8 (C.UTF-8) when it is missing"

# Fresh installs from the Asahi base image keep /etc/locale.conf at LANG=C, so
# system services run non-UTF-8 while user sessions repair themselves. Repair
# once through localectl, which validates the value and applies it live.
#
# Idempotent: a configured UTF-8 locale (any region, any spelling) is left
# alone; machines without /etc/locale.conf never had the problem.
if [[ -r /etc/locale.conf ]] && grep -Eqi '^LANG=.*\.(UTF-8|utf8)$' /etc/locale.conf; then
  exit 0
fi

sudo localectl set-locale LANG=C.UTF-8
