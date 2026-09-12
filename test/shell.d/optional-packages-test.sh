#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Optional Install rows hide when this architecture's repositories cannot
# satisfy them. The manifest names the complete transaction per menu id, the
# row's `when:` asks omarchy-install-available about it, and the aarch64
# baseline pins which transactions a port is expected to keep resolvable.
run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const byId = new Map(items.map(item => [item.id, item]))
const lines = fs.readFileSync(path.join(root, 'install/optional-packages.tsv'), 'utf8')
  .split('\n')
  .filter(line => line.startsWith('install.'))
const transactions = new Map(lines.map(line => {
  const separator = line.indexOf('|')
  return [line.slice(0, separator), line.slice(separator + 1).split(/\s+/)]
}))
const aurLines = fs.readFileSync(path.join(root, 'install/optional-aur-packages.tsv'), 'utf8')
  .split('\n')
  .filter(line => line.startsWith('install.'))
const aurTransactions = new Map(aurLines.map(line => { const [id, pkg, arches] = line.split('|'); return [id, pkg] }))
const requiredLines = fs.readFileSync(path.join(root, 'install/optional-packages-aarch64-required'), 'utf8')
  .split('\n')
  .filter(line => line.startsWith('install.'))
const required = new Set(requiredLines)

assertEqual(transactions.size, lines.length, 'optional package transaction ids are unique')
assertEqual(aurTransactions.size, aurLines.length, 'optional AUR transaction ids are unique')
assertEqual(required.size, requiredLines.length, 'required aarch64 transaction ids are unique')
assertEqual(required.size, 23, 'aarch64 support baseline covers every currently supported transaction')
assertDeepEqual(
  [...required].filter(id => !transactions.has(id)),
  [],
  'required aarch64 transactions exist in the package manifest'
)

// The availability check comes first in the guard so a row with nothing to
// install on this architecture never reaches the presence question after it.
for (const [id, packages] of transactions) {
  const item = byId.get(id)
  assert(item, `optional package transaction has a menu row: ${id}`)
  assert(
    (item.when || '').startsWith(`omarchy-install-available ${id}`),
    `optional package transaction guards its menu row: ${id}`
  )
  assert(packages.length > 0 && packages.every(packageName => /^[a-zA-Z0-9@._+:-]+$/.test(packageName)),
    `optional package transaction contains valid names: ${id}`)
}

const unknownGuards = items
  .filter(item => /omarchy-install-available /.test(item.when || ''))
  .filter(item => !transactions.has(item.id) && !aurTransactions.has(item.id))
  .map(item => item.id)
assertDeepEqual(unknownGuards, [], 'optional install guards all have a transaction')

// AUR rows use the same interface, but resolve architecture rather than sync targets.
for (const [id, packageName] of aurTransactions) {
  assert(byId.has(id), `optional AUR transaction has a menu row: ${id}`)
  assert(!transactions.has(id), `optional AUR transaction is not treated as a sync package: ${id}`)
  assert(byId.get(id).when.startsWith(`omarchy-install-available ${id} && ! omarchy-pkg-present `),
    `optional AUR transaction has an architecture availability guard: ${id}`)
  const installer = byId.get(id).action.match(/omarchy-install-[a-z0-9-]+/)[0]
  assert(new RegExp(`\\bomarchy-pkg-(aur-)?add ${packageName}\\b`).test(
    fs.readFileSync(path.join(root, 'bin', installer), 'utf8')
  ), `optional AUR transaction matches its installer: ${id}`)
}

// Install rows dim on package presence, so any row asking that question
// installs a package and has to say which ones.
const unguarded = items
  .filter(item => item.id.startsWith('install.'))
  .filter(item => /omarchy-pkg-present /.test(item.when || ''))
  .filter(item => !aurTransactions.has(item.id))
  .filter(item => !transactions.has(item.id))
  .map(item => item.id)
assertDeepEqual(unguarded, [], 'pacman-backed install rows declare complete transactions')

// The secondary packages are the ones a port loses first, and the ones a
// presence check on the primary package would never notice.
const requiredSecondaryPackages = {
  'install.service.1password': ['1password-cli'],
  'install.service.dropbox': ['dropbox-cli', 'libappindicator-gtk3', 'python-gpgme', 'nautilus-dropbox'],
  'install.service.bitwarden': ['bitwarden-cli'],
  'install.ai.dictation': ['wtype'],
  'install.gaming.retroarch': ['libretro-blastem', 'libretro-ppsspp', 'libretro-fbneo-git', 'retroarch-joypad-autoconfig-git'],
  'install.gaming.lutris': ['umu-launcher', 'wine-staging', 'wine-mono', 'wine-gecko', 'winetricks', 'python-protobuf'],
  'install.development.php.php': ['composer', 'php-sqlite', 'xdebug'],
  'install.development.php.symfony': ['composer', 'php-sqlite', 'xdebug', 'symfony-cli']
}
for (const [id, expected] of Object.entries(requiredSecondaryPackages)) {
  assertDeepEqual(
    expected.filter(packageName => !transactions.get(id).includes(packageName)),
    [],
    `optional package transaction includes secondary packages: ${id}`
  )
}
JS

# Runtime and batch behavior is exercised in optional-availability-test.sh.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

cat >"$test_tmp/bin/pacman" <<'SH'
#!/bin/bash
operation=$1
shift
case $operation in
  -Si)
    [[ $1 != missing* ]]
    ;;
  -Sp)
    [[ " $* " != *' broken '* ]]
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$test_tmp/bin/pacman"
cat >"$test_tmp/live.tsv" <<'EOF'
install.good|primary secondary
install.hidden|missing
install.required-missing|missing-required
install.broken|broken
EOF
printf '%s\n' install.good install.required-missing install.broken >"$test_tmp/required"

set +e
live_output=$(OMARCHY_OPTIONAL_PACKAGES_FILE="$test_tmp/live.tsv" \
  OMARCHY_OPTIONAL_REQUIRED_FILE="$test_tmp/required" \
  OMARCHY_OPTIONAL_PACKAGE_CACHE="$test_tmp/cache" \
  PATH="$test_tmp/bin:$PATH" "$ROOT/test/optional-packages-live" 2>&1)
live_status=$?
set -e
(( live_status != 0 )) || fail 'live optional package preflight fails unresolved transactions'
[[ $live_output == *'1 resolved, 1 hidden, 2 failed'* ]] ||
  fail 'live optional package preflight reports every transaction' "$live_output"
[[ $live_output == *'install.required-missing lost required packages: missing-required'* ]] ||
  fail 'live optional package preflight fails a support regression' "$live_output"
pass 'live optional package preflight reports hidden and unresolved transactions'
