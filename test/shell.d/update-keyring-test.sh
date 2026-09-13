#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"
run_node_test <<'JS'
const fs=require('fs'), os=require('os'), cp=require('child_process')
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'keyring-'))
try {
  const bin=path.join(tmp,'bin'), log=path.join(tmp,'calls');fs.mkdirSync(bin)
  function stub(name, body){fs.writeFileSync(path.join(bin,name),'#!/bin/bash\n'+body+'\n',{mode:0o755})}
  stub('sudo','"$@"')
  stub('omarchy-hw-apple-silicon','[[ ${APPLE:-0} == 1 ]]')
  stub('omarchy-pkg-missing','[[ ${MISSING_PACKAGE:-0} == 1 ]]')
  stub('pacman-key','echo "key $*" >> "$CALLS"; [[ "$*" != "${FAIL_STEP:-}" ]] || exit 42; if [[ $1 == --list-keys && ${MISSING_KEY:-0} == 1 ]]; then exit 1; fi')
  stub('pacman','echo "pacman $*" >> "$CALLS"; exit "${PACMAN_STATUS:-0}"')
  stub('gpg','echo "pub:::::::::"; echo "fpr:::::::::${FINGERPRINT:-40DFB630FF42BCFFB047046CF0134EE680CAC571}:"')
  const env={...process.env,PATH:bin+':'+process.env.PATH,CALLS:log}
  function run(extra={}) {fs.writeFileSync(log,'');const result=cp.spawnSync('bash',[path.join(root,'bin/omarchy-update-keyring')],{env:{...env,...extra},encoding:'utf8'});return {...result,log:fs.readFileSync(log,'utf8')}}
  for(const apple of ['0','1']) {
    const ring=apple==='1'?'archlinuxarm':'archlinux'
    for(const missing of ['0','1']) {
      const r=run({APPLE:apple,MISSING_KEY:missing,MISSING_PACKAGE:missing})
      assertEqual(r.status,0,'keyring update succeeds with correct trust inputs')
      assert(r.log.includes(`pacman -Sy --noconfirm omarchy-keyring ${ring}-keyring`),'both correct keyring packages are refreshed')
      assert(r.log.includes(`key --populate omarchy ${ring}`),'updated trust and revocations are populated')
      assertEqual(r.log.includes('--recv-keys'),missing==='1','bootstrap fetch is limited to missing keys')
    }
    for(const extra of [{PACMAN_STATUS:'42'},{FAIL_STEP:`--populate ${ring}`},{FAIL_STEP:`--populate omarchy ${ring}`},{FAIL_STEP:'--lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571'},{MISSING_KEY:'1',FAIL_STEP:'--recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keys.openpgp.org'}]) {
      const r=run({APPLE:apple,...extra});assertEqual(r.status,42,'keyring failures propagate');assert(!r.stdout.includes('Keys are correct'),'failed update never reports success')
    }
  }
  const wrong=run({FINGERPRINT:'0000000000000000000000000000000000000000'})
  assertEqual(wrong.status,1,'wrong signing fingerprint is rejected')
  assert(!wrong.log.includes('--lsign-key')&&!wrong.log.includes('pacman -Sy'),'wrong fingerprint cannot be trusted or used to update')
} finally {fs.rmSync(tmp,{recursive:true,force:true})}
JS
