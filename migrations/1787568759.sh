echo "Retire the legacy ChatGPT web app launcher"

desktop_file="$HOME/.local/share/applications/ChatGPT.desktop"

if [[ -f $desktop_file ]] &&
  grep -Eq '^Exec=omarchy-launch-webapp[[:space:]]+https://chatgpt\.com/?$' "$desktop_file"; then
  rm -f "$desktop_file"
  update-desktop-database "$(dirname "$desktop_file")" &>/dev/null || true
fi
