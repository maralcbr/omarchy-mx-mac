# Fix Wi-Fi failing to reconnect after wake from suspend on Apple Silicon
# iwd and NetworkManager become desynced from the Wi-Fi hardware state upon waking up

omarchy-hw-apple-silicon || return 0

echo "Applying Wi-Fi resume fix for Apple Silicon..."

mkdir -p /etc/systemd/system
cat > /etc/systemd/system/omarchy-wifi-resume.service <<'EOF'
[Unit]
Description=Omarchy Wi-Fi Resume Fix for Apple Silicon
After=suspend.target

[Service]
Type=simple
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/systemctl restart iwd
ExecStartPost=/usr/bin/systemctl restart NetworkManager

[Install]
WantedBy=suspend.target
EOF

systemctl enable omarchy-wifi-resume.service
