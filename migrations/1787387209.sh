echo "Remove the retired seamless login service that conflicts with SDDM"

legacy_unit=/etc/systemd/system/omarchy-seamless-login.service
legacy_link=/etc/systemd/system/graphical.target.wants/omarchy-seamless-login.service
legacy_helper=/usr/local/bin/seamless-login

if [[ ! -e $legacy_unit && ! -L $legacy_link && ! -e $legacy_helper ]]; then
  exit 0
fi

sudo systemctl disable omarchy-seamless-login.service >/dev/null 2>&1 || true
sudo rm -f \
  "$legacy_link" \
  "$legacy_unit" \
  /etc/systemd/system/getty@tty1.service.d/autologin.conf \
  /etc/systemd/system/plymouth-quit.service.d/wait-for-graphical.conf \
  "$legacy_helper"
sudo systemctl daemon-reload
