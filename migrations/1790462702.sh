echo "Mark this Mac for the move onto Omarchy's official packages"

# The final omarchy-mx-mac release. This marks the Mac, machine-wide; the next
# omarchy update moves it onto Omarchy's official packages for the channel it
# follows with omarchy-mac-migrate (vendored from omacom/omarchy-mac), before
# any fork step, and stops there for the reboot. Until that channel carries
# the Mac packages (stable and rc today), those updates leave the Mac on the
# fork and update it as before. Once a run marked it, other accounts skip this.
marker="${OMARCHY_MAC_CONVERSION_MARKER:-/var/lib/omarchy/migrations/1790462702}"
[[ ! -e $marker ]] || exit 0
omarchy-hw-apple-silicon || exit 0

sudo install -Dm644 /dev/null "$marker"
echo "The next omarchy update moves this Mac onto Omarchy's official packages, once its channel has a Mac release."
