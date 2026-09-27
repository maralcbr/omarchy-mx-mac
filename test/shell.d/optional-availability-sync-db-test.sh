#!/bin/bash
# The Install rows' availability guards against real pacman, in a root laid out
# as a fresh ISO install leaves it: pacman.conf names the online repositories,
# but the only sync database is the offline repository's the ISO installed
# from. Nothing is known about the online repositories until the first update
# syncs them, so every row shows, as it did before the guards existed. Once
# every configured repository has its database, the guards answer from them.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"
require_command pacman
require_command pacman-conf
require_command tar

run_node_test <<'JS'
const fs = require('fs'), os = require('os'), cp = require('child_process')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const guarded = items.filter(item => (item.when || '').includes('omarchy-pkg-available'))
assert(guarded.length > 20, 'the menu has availability-guarded Install rows')
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sync-db-'))
try {
  const bin = path.join(tmp, 'bin'), db = path.join(tmp, 'db'), sync = path.join(db, 'sync'), conf = path.join(tmp, 'pacman.conf')
  fs.mkdirSync(bin); fs.mkdirSync(sync, {recursive: true}); fs.mkdirSync(path.join(db, 'local'))
  fs.writeFileSync(path.join(db, 'local/ALPM_DB_VERSION'), '9\n')
  fs.writeFileSync(conf, `[options]\nDBPath = ${db}/\nArchitecture = auto\nSigLevel = Never\n`
    + ['core', 'extra', 'omarchy'].map(repo => `[${repo}]\nServer = file://${tmp}/mirror/${repo}\n`).join(''))
  for (const tool of ['pacman', 'pacman-conf'])
    fs.writeFileSync(path.join(bin, tool), `#!/bin/bash\nexec /usr/bin/${tool} --config "$PACMAN_TEST_CONF" "$@"\n`, {mode: 0o755})

  // A sync database is a gzipped tar of one <name>-<version>/desc per package.
  function database(repo, names) {
    const stage = fs.mkdtempSync(path.join(tmp, 'stage-'))
    for (const name of names) {
      fs.mkdirSync(path.join(stage, `${name}-1-1`))
      fs.writeFileSync(path.join(stage, `${name}-1-1/desc`),
        `%FILENAME%\n${name}-1-1-any.pkg.tar.zst\n\n%NAME%\n${name}\n\n%VERSION%\n1-1\n\n%ARCH%\nany\n\n%CSIZE%\n1\n\n%ISIZE%\n1\n`)
    }
    cp.execFileSync('tar', ['-czf', path.join(sync, `${repo}.db`), ...names.map(name => `${name}-1-1`)], {cwd: stage})
    fs.rmSync(stage, {recursive: true})
  }

  const env = {...process.env, OMARCHY_PATH: root, PACMAN_TEST_CONF: conf, PATH: bin + ':' + root + '/bin:' + process.env.PATH}
  const run = (script, args = []) => cp.spawnSync('bash', ['-euo', 'pipefail', '-c', script, 'bash', ...args], {env, encoding: 'utf8'})
  const available = targets => run(`"${root}/bin/omarchy-pkg-available" "$@"`, targets).status
  function rows() {
    const batch = run(menu.guardScript(Object.fromEntries(guarded.map(item => [item.id, {when: item.when}]))))
    assertEqual(batch.status, 0, 'the guard batch completes', batch.stderr)
    return Object.fromEntries(batch.stdout.trim().split('\n').map(line => line.split(':w:')))
  }

  // Fresh ISO install: offline.db alone. pacman itself knows nothing of the
  // online repositories, which is what hid the rows.
  database('offline', ['base', 'zed'])
  assertEqual(run('pacman -Slq').stdout, '', 'pacman lists nothing from repositories with no database')
  assertEqual(run('pacman -Sp zed').status, 1, 'pacman resolves nothing from repositories with no database')
  let shown = rows()
  for (const item of guarded) assertEqual(shown[item.id], '1', `fresh ISO install shows ${item.id}`)
  assertEqual(available(['zed', 'absent']), 0, 'fresh ISO install: an unknown name counts as available')
  assertEqual(available(['zed', '']), 1, 'fresh ISO install: an empty target is still refused')

  // After an update every configured repository has its database: accurate.
  database('core', ['base', 'zed'])
  database('extra', ['vim'])
  database('omarchy', ['omazed'])
  assertEqual(available(['zed', 'omazed']), 0, 'synced: offered names are available')
  assertEqual(available(['absent']), 1, 'synced: a name no repository offers is not')
  shown = rows()
  assertEqual(shown['install.editor.zed'], '1', 'synced: the Zed row shows')
  assertEqual(shown['install.editor.helix'], '0', 'synced: the Helix row hides with no helix package')

  // One configured repository without its database makes the answer unknown
  // again; a name found in the others stays available.
  fs.rmSync(path.join(sync, 'omarchy.db'))
  assertEqual(available(['zed']), 0, 'partial: a found name stays available')
  assertEqual(available(['absent']), 0, 'partial: a name not found may be in the missing database')
  assertEqual(rows()['install.editor.helix'], '1', 'partial: the Helix row shows')
  fs.writeFileSync(path.join(sync, 'omarchy.db'), '')
  assertEqual(available(['absent']), 0, 'an empty database file answers nothing')
} finally { fs.rmSync(tmp, {recursive: true, force: true}) }
JS
pass "availability guards show every row until each configured repository has its sync database"
