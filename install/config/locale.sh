locale_conf="${OMARCHY_LOCALE_CONF:-/etc/locale.conf}"
lang=$(sed -nE 's/^[[:space:]]*LANG[[:space:]]*=[[:space:]]*"?([^"[:space:]#]+)"?([[:space:]]*(#.*)?)?$/\1/p' "$locale_conf" 2>/dev/null | tail -n 1)

if [[ ${lang,,} =~ \.utf-?8(@[^[:space:]]+)?$ ]]; then
  return 0
fi

# This runs in chroots without systemd-localed. Replace only LANG so regional
# LC_* choices and administrator comments remain intact.
if [[ -e $locale_conf ]]; then
  sed -i '/^[[:space:]]*LANG[[:space:]]*=/d' "$locale_conf"
fi
printf 'LANG=C.UTF-8\n' >>"$locale_conf"
