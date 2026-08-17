echo "Update About branding to Omarchy Mx Mac"

fastfetch_config="$HOME/.config/fastfetch/config.jsonc"
[[ -f $fastfetch_config ]] || exit 0

sed -i \
  -e 's/echo \\"Omarchy Mac \$version\\"/echo \\"Omarchy Mx Mac \$version\\"/' \
  -e 's/echo \\"Omarchy \$version\\"/echo \\"Omarchy Mx Mac \$version\\"/' \
  "$fastfetch_config"
