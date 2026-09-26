echo "Hand the machine to its platform's migration onto the official packages, where there is one"

# Machine-wide work, but migration completion is recorded per user: once one
# account ran it, the marker spares the others a root prompt they may not be
# allowed to answer. Written last, so a refused or interrupted run is retried.
marker="${OMARCHY_PLATFORM_MIGRATION_MARKER:-/var/lib/omarchy/migrations/1790347292}"
if [[ -e $marker ]]; then
  exit 0
fi

# A no-op wherever no boot package implements it. Where the dispatcher can't
# resolve it (the platform can't be told, say), nothing has run: the migration
# waits (75), staying pending without stopping later migrations or the update,
# whose boot verification then fails on that machine.
entrypoint=$(omarchy-lifecycle-dispatch --resolve migrate) || exit 75
if [[ -n $entrypoint ]]; then
  sudo omarchy-lifecycle-dispatch migrate
  sudo install -Dm644 /dev/null "$marker"
fi
