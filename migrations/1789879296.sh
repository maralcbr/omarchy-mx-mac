echo "Replace leftover linux-asahi-headers on Aurora with linux-aurora-headers"

# linux-aurora provides linux-asahi; list exact names with pacman -Qq. The channel
# record is the Aurora/stable split; leftover Asahi headers are rc-only. Only a
# successful status that is not this Mac may settle the migration; a failed read
# stays pending. Replacement headers must be the installed linux-aurora's version
# from [omarchy-aurora]; a hold or a missing match would recreate the hazard.

pending="${OMARCHY_AURORA_ASAHI_HEADERS_PENDING:-/var/lib/omarchy/migrations/1789879296-aurora-headers}"
script="${OMARCHY_UPDATE_M1N1_SCRIPT:-/usr/bin/update-m1n1}"
config="${OMARCHY_UPDATE_M1N1_CONFIG:-/etc/default/update-m1n1}"

status=0
record=$(omarchy-apple-silicon-channel status) || status=$?
if (( status != 0 )); then
  echo "Replace leftover linux-asahi-headers: the Apple Silicon channel record could not be read." >&2
  exit 1
fi
channel="" kernel=""
while IFS= read -r line; do
  case "$line" in
    channel=*) channel=${line#channel=} ;;
    kernel=*) kernel=${line#kernel=} ;;
  esac
done <<<"$record"
[[ $channel == rc && $kernel == linux-aurora ]] || exit 0

installed=$(pacman -Qq) || {
  echo "Replace leftover linux-asahi-headers: cannot list installed packages." >&2
  exit 1
}

asahi_headers=0
if grep -Fxq linux-asahi-headers <<<"$installed"; then
  asahi_headers=1
fi
(( asahi_headers )) || [[ -f $pending ]] || exit 0

held_status=0
held=$(omarchy-apple-silicon-channel held) || held_status=$?
if (( held_status != 0 )); then
  echo "Replace leftover linux-asahi-headers: pacman holds could not be read." >&2
  exit 1
fi
if [[ -n $held ]]; then
  echo "IgnorePkg/IgnoreGroup holds $held; leftover linux-asahi-headers cannot be replaced until that hold is removed." >&2
  exit 1
fi

grep -Fxq linux-aurora <<<"$installed" || {
  echo "Replace leftover linux-asahi-headers: linux-aurora is not installed." >&2
  exit 1
}
kernel_record=$(pacman -Q linux-aurora) || {
  echo "Replace leftover linux-asahi-headers: cannot read the installed linux-aurora version." >&2
  exit 1
}
[[ $kernel_record == linux-aurora\ * ]] || {
  echo "Replace leftover linux-asahi-headers: unexpected pacman -Q linux-aurora output." >&2
  exit 1
}
kernel_version=${kernel_record#linux-aurora }
[[ $kernel_version =~ ^[A-Za-z0-9._+-]+$ ]] || {
  echo "Replace leftover linux-asahi-headers: unexpected linux-aurora version '$kernel_version'." >&2
  exit 1
}

available=$(pacman -Si omarchy-aurora/linux-aurora-headers | awk -F'[[:space:]]+:[[:space:]]+' '/^Version / { print $2; exit }') || available=""
if [[ $available != "$kernel_version" ]]; then
  echo "linux-aurora-headers $kernel_version is not available from [omarchy-aurora] (has ${available:-nothing}); leftover linux-asahi-headers repair will retry." >&2
  exit 1
fi

if (( asahi_headers )); then
  sudo install -Dm644 /dev/null "$pending"
  # --noconfirm answers No to conflicts. -Rns refuses (and -Rcns would remove)
  # DKMS modules that depend on the headers; -Rdd drops only this package.
  sudo pacman -Rdd --noconfirm linux-asahi-headers
fi

sudo pacman -S --noconfirm --needed "omarchy-aurora/linux-aurora-headers=$kernel_version" || {
  echo "Could not install linux-aurora-headers $kernel_version from [omarchy-aurora]; leftover linux-asahi-headers repair will retry." >&2
  exit 1
}

dtbs_default=0
if [[ -r $script ]] && grep -Eq '^[[:space:]]*:[[:space:]]+\$\{DTBS:=.*/modules/\*-ARCH' "$script"; then
  if [[ ! -e $config ]]; then
    dtbs_default=1
  elif configured=$(env -i PATH=/usr/bin:/bin bash --noprofile --norc -c '
    unset DTBS M1N1_UPDATE_DISABLED
    . "$1" >/dev/null 2>&1 || exit 1
    printf "%s" "${DTBS-}${M1N1_UPDATE_DISABLED-}"
  ' _ "$config") && [[ -z $configured ]]; then
    dtbs_default=1
  fi
fi

if (( dtbs_default )); then
  sudo env -u TARGET -u DTBS -u SOURCE -u M1N1 -u U_BOOT -u CONFIG -u M1N1_UPDATE_DISABLED update-m1n1 </dev/null || {
    echo "update-m1n1 failed after replacing linux-asahi-headers; run sudo update-m1n1, then omarchy update." >&2
    exit 1
  }
fi

omarchy-apple-silicon-boot-check linux-aurora || {
  echo "Apple Silicon boot check failed after replacing linux-asahi-headers; the migration will retry." >&2
  exit 1
}

sudo rm -f "$pending"
