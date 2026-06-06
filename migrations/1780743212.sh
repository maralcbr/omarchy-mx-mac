echo "Fix Mac systemd post-update warnings"

login_service=/etc/systemd/system/omarchy-seamless-login.service
if [[ -f $login_service ]]; then
  sudo perl -0pi -e '
    s/\nStartLimitIntervalSec=30\nStartLimitBurst=2\nUser=/\nUser=/;
    s/PartOf=graphical\.target\n(?:StartLimitIntervalSec=30\nStartLimitBurst=2\n)?\n\[Service\]/PartOf=graphical.target\nStartLimitIntervalSec=30\nStartLimitBurst=2\n\n[Service]/;
  ' "$login_service"
fi

if [[ -x /usr/bin/asahi-btsync && -f /etc/systemd/system/asahi-btsync.service ]]; then
  sudo mkdir -p /etc/systemd/system/asahi-btsync.service.d
  sudo tee /etc/systemd/system/asahi-btsync.service.d/ignore-missing-variable.conf >/dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=/bin/bash -o pipefail -c 'output=$(/usr/bin/asahi-btsync sync 2>&1); status=$?; printf "%%s\n" "$output"; if (( status == 0 )); then exit 0; fi; if (( status == 101 )) && [[ $output == *VariableNotFound* ]]; then exit 0; fi; exit "$status"'
EOF
fi

for unit in \
  /usr/lib/systemd/system/macsmc-battery-charge-control-end-threshold.path \
  /usr/lib/systemd/system/macsmc-battery-charge-control-end-threshold.service; do
  [[ -f $unit ]] && sudo chmod 0644 "$unit"
done

sudo systemctl daemon-reload
