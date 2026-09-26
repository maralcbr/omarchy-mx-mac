echo "Prepare this Mac's move onto Omarchy's official packages"

# The final omarchy-mx-mac release. This fetches the official omarchy-mac-boot
# for the channel the Mac follows and checks it against the Omarchy packaging
# key (omarchy-mac-migrate-bootstrap --prime). The next omarchy update moves the
# Mac onto Omarchy's packages with it, and stops there. Until that package is
# published with its migration target this stays pending (75) without holding
# up the update. Machine-wide: once it ran, the marker spares other accounts.
marker="${OMARCHY_MAC_CONVERSION_MARKER:-/var/lib/omarchy/migrations/1790462702}"
[[ ! -e $marker ]] || exit 0
omarchy-hw-apple-silicon || exit 0

channel=$(omarchy-apple-silicon-channel current 2>/dev/null) || channel=""
[[ $channel =~ ^(stable|rc|edge)$ ]] || channel=stable
sudo omarchy-mac-migrate-bootstrap --prime --channel "$channel"
sudo install -Dm644 /dev/null "$marker"
