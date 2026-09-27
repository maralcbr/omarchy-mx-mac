#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"
run_node_test <<'JS'
const fs = require('fs'), os = require('os'), cp = require('child_process')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const byId = Object.fromEntries(items.map(item => [item.id, item]))
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'availability-'))
try {
  const bin = path.join(tmp, 'bin'), calls = path.join(tmp, 'calls')
  fs.mkdirSync(bin)
  function stub(name, body) { fs.writeFileSync(path.join(bin, name), '#!/bin/bash\n'+body+'\n', {mode:0o755}) }
  stub('pacman', `echo "$*" >> "$CALLS"
case $1 in
-Slq) for p in primary secondary zed omazed xpadneo-dkms; do [[ $p == "\${MISSING:-}" ]] || echo "$p"; done ;;
-Sp) [[ \${*: -1} == provided || \${*: -1} == 'provided>=1' ]] ;;
-Qq|-Qi) exit 0 ;;
*) exit 1 ;;
esac`)
  stub('uname', 'echo uname >> "$CALLS"; echo "${ARCH:-x86_64}"')
  // Every configured repository has its sync database, except one $UNSYNCED adds.
  const sync=path.join(tmp,'db/sync');fs.mkdirSync(sync,{recursive:true})
  for (const repo of ['core','extra','omarchy']) fs.writeFileSync(path.join(sync,repo+'.db'),'db')
  stub('pacman-conf', `case $1 in
DBPath) echo "$DBPATH" ;;
--repo-list) printf '%s\\n' core extra omarchy \${UNSYNCED:-} ;;
*) exit 1 ;;
esac`)
  const env = {...process.env, OMARCHY_PATH:root, CALLS:calls, DBPATH:path.join(tmp,'db'), PATH:bin+':'+root+'/bin:'+process.env.PATH}
  function run(script, extra={}) { return cp.spawnSync('bash', ['-euo','pipefail','-c',script], {env:{...env,...extra},encoding:'utf8'}) }
  const prelude = menu.guardScript({probe:{id:'probe',when:'true'}}).split('\n').filter(l=>!l.startsWith('if {')).join('\n')
  for (const targets of ['', 'primary secondary', 'primary missing', 'provided', "'provided>=1'", "'provided>=9'", "''"]) {
    const expected = ['primary missing', "'provided>=9'", "''"].includes(targets)?1:0
    for (const script of [`"${root}/bin/omarchy-pkg-available" ${targets}`, prelude+`\nomarchy-pkg-available ${targets}`]) {
      const result=run(script); assertEqual(result.status,expected,`CLI/batch explicit targets: ${targets}`,result.stderr)
    }
  }
  function checkRow(id, expected, extra={}) {
    const item=byId[id]; assert(item,`menu row exists: ${id}`)
    const direct=run(item.when,extra)
    const batch=run(menu.guardScript({[id]:{...item,disabled:''}}),extra)
    assertEqual(direct.status,expected,`direct guard ${id}`,direct.stderr)
    assertEqual(batch.status,0,`batch evaluates ${id}`,batch.stderr)
    assertEqual(batch.stdout.trim(),`${id}:w:${expected===0?1:0}`,`batch guard ${id}`)
  }
  for (const arch of ['x86_64','aarch64','riscv64']) {
    checkRow('install.browser.edge', arch==='x86_64'?0:1,{ARCH:arch})
    for (const browser of ['chrome','brave','brave-origin','zen']) checkRow('install.browser.'+browser,arch==='riscv64'?1:0,{ARCH:arch})
  }
  checkRow('install.editor.zed',0)
  checkRow('install.editor.zed',1,{MISSING:'zed'})
  checkRow('install.gaming.xbox-controllers',0)
  checkRow('install.gaming.xbox-controllers',1,{MISSING:'xpadneo-dkms'})
  // A configured repository with no sync database (a fresh ISO install before
  // its first update) leaves availability unknown, so rows show as before the
  // guards, without asking pacman; so does a configuration pacman-conf can't read.
  for (const extra of [{UNSYNCED:'multilib'},{DBPATH:''},{DBPATH:path.join(tmp,'nowhere')}]) {
    fs.writeFileSync(calls,'')
    checkRow('install.editor.zed',0,{...extra,MISSING:'zed'})
    checkRow('install.gaming.xbox-controllers',0,{...extra,MISSING:'xpadneo-dkms'})
    for (const script of [`"${root}/bin/omarchy-pkg-available" primary missing 'provided>=9'`, prelude+`\nomarchy-pkg-available primary missing 'provided>=9'`])
      assertEqual(run(script,extra).status,0,`unknown availability shows the row: ${JSON.stringify(extra)}`)
    assertEqual(run(`"${root}/bin/omarchy-pkg-available" missing ''`,extra).status,1,'an empty target is refused even when availability is unknown')
    assert(!/^-S/m.test(fs.readFileSync(calls,'utf8')),'unknown availability does not query the sync databases')
  }
  fs.writeFileSync(calls,'')
  const cacheItems={}
  for (const id of ['install.browser.chrome','install.browser.brave']) cacheItems[id]={...byId[id],disabled:''}
  const cache=run(menu.guardScript(cacheItems)+'\nomarchy-pkg-available primary provided\nomarchy-pkg-available secondary provided')
  assertEqual(cache.status,0,'cached batch completes',cache.stderr)
  const lines=fs.readFileSync(calls,'utf8').trim().split('\n')
  assertEqual(lines.filter(l=>l==='uname').length,1,'architecture is read once per batch')
  assertEqual(lines.filter(l=>l==='-Slq').length,1,'sync database is read once per batch')
  assertEqual(lines.filter(l=>l.startsWith('-Sp')&&l.endsWith('provided')).length,1,'provider lookup is cached')
  const incomplete=path.join(tmp,'incomplete');fs.mkdirSync(path.join(incomplete,'bin'),{recursive:true})
  stub('omarchy-pkg-available','echo recursive-dispatch >> "$CALLS"; exit 42')
  const file=path.join(incomplete,'bin/omarchy-pkg-available')
  for (const content of [null,'','return 1','omarchy-pkg-available() { return 0; }','__omarchy_pkg_available_ready=true']) {
    fs.rmSync(file,{force:true});if(content!==null)fs.writeFileSync(file,content)
    fs.writeFileSync(calls,'')
    const result=run(prelude+'\nomarchy-pkg-available primary',{OMARCHY_PATH:incomplete})
    assertEqual(result.status,1,'incomplete source aborts the batch')
    assert(!fs.readFileSync(calls,'utf8').includes('recursive-dispatch'),'incomplete source never dispatches through PATH')
  }
} finally { fs.rmSync(tmp,{recursive:true,force:true}) }
JS
