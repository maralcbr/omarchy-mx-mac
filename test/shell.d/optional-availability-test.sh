#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export CALLS="$test_tmp/calls" OMARCHY_PATH="$ROOT"
cat >"$test_tmp/bin/pacman" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$CALLS"
case $1 in
-Slq)
  printf '%s\n' primary secondary zed omazed xpadneo-dkms linux-headers linux-asahi-headers | while read -r p; do
    [[ $p == "${MISSING:-}" ]] || echo "$p"
  done ;;
-Sp)
  [[ ${*: -1} == provided || ${*: -1} == 'provided>=1' ]] ;;
-Qq|-Qi) exit 0 ;;
*) exit 1 ;;
esac
STUB
cat >"$test_tmp/bin/uname" <<'STUB'
#!/bin/bash
printf 'uname\n' >>"$CALLS"
echo "${ARCH:-x86_64}"
STUB
cat >"$test_tmp/bin/omarchy-hw-apple-silicon" <<'STUB'
#!/bin/bash
[[ ${APPLE:-0} == 1 ]]
STUB
cat >"$test_tmp/bin/omarchy-hw-apple-kernel" <<'STUB'
#!/bin/bash
echo "${TEST_KERNEL:-linux-asahi}"
STUB
chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:$PATH"
prelude=$(node -e 'console.log(require(process.argv[1]).guardScript({ probe: { id: "probe", when: "true" } }))' "$ROOT/shell/plugins/menu/MenuModel.js" | grep -v '^if {')
check() {
  local expected=$1 helper=$2 argument=$3 actual
  for mode in cli batch; do
    actual=0
    : >"$CALLS"
    if [[ $mode == cli ]]; then
      "$ROOT/bin/$helper" "$argument" || actual=$?
    else
      bash -c "$prelude"$'\n''"$1" "$2"' bash "$helper" "$argument" || actual=$?
    fi
    [[ $actual == "$expected" ]] || fail "$mode $helper $argument" "expected=$expected actual=$actual"
    if [[ $argument == install.browser.* || $argument == install.service.nordvpn ]]; then
      ! grep -E -- '^-Slq|^-Sp' "$CALLS" >/dev/null || fail 'AUR availability must not query sync targets'
    fi
  done
}
for arch in x86_64 aarch64; do
  export ARCH=$arch
  expected=0
  [[ $arch != aarch64 ]] || expected=1
  check "$expected" omarchy-install-available install.browser.edge
  for browser in chrome brave brave-origin zen; do
    check 0 omarchy-install-available "install.browser.$browser"
  done
  check 0 omarchy-install-available install.service.nordvpn
  check 0 omarchy-pkg-available provided
  check 0 omarchy-pkg-available 'provided>=1'
  check 1 omarchy-pkg-available 'provided>=9'
  check 1 omarchy-pkg-available missing
  check 0 omarchy-install-available install.editor.zed
  MISSING=omazed check 1 omarchy-install-available install.editor.zed
  for apple in 0 1; do
    export APPLE=$apple
    selected=linux-headers
    other=linux-asahi-headers
    if [[ $apple == 1 ]]; then selected=linux-asahi-headers; other=linux-headers; fi
    check 0 omarchy-install-available install.gaming.xbox-controllers
    MISSING=$selected check 1 omarchy-install-available install.gaming.xbox-controllers
    MISSING=$other check 0 omarchy-install-available install.gaming.xbox-controllers
  done
done
ARCH=riscv64 check 1 omarchy-install-available install.browser.chrome
check 1 omarchy-install-available install.unknown
: >"$CALLS"
bash -c "$prelude"$'\n''omarchy-pkg-available primary provided; omarchy-pkg-available secondary provided; omarchy-install-available install.browser.chrome; omarchy-install-available install.browser.brave'
[[ $(grep -c -- '^-Slq$' "$CALLS") == 1 ]] || fail 'one sync snapshot per batch'
[[ $(grep -c -- '^-Sp .*provided$' "$CALLS") == 1 ]] || fail 'provided results cached per batch'
[[ $(grep -c '^uname$' "$CALLS") == 1 ]] || fail 'one architecture probe per batch'
pass 'CLI and menu agree across architectures, provides and selected dependencies'
pass 'batch caches database, architecture and fallback lookups'

# A missing helper must stop at the source error. Calling the wrapper's own
# command name without its function would recurse through PATH until OOM.
mkdir -p "$test_tmp/incomplete" "$test_tmp/recursion-bin"
export RECURSION_LOG="$test_tmp/recursion"
for helper in omarchy-pkg-available omarchy-install-available; do
  cat >"$test_tmp/recursion-bin/$helper" <<'STUB'
#!/bin/bash
echo recursive-dispatch >> "$RECURSION_LOG"
exit 42
STUB
  chmod +x "$test_tmp/recursion-bin/$helper"
  status=0
  OMARCHY_PATH="$test_tmp/incomplete" PATH="$test_tmp/recursion-bin:$PATH" \
    "$ROOT/bin/$helper" install.browser.chrome 2>/dev/null || status=$?
  [[ $status == 1 && ! -e $RECURSION_LOG ]] || fail 'missing helper stops before recursive command dispatch'
done
status=0
OMARCHY_PATH="$test_tmp/incomplete" bash -c "$prelude"$'\n''echo continued >> "$RECURSION_LOG"' 2>/dev/null || status=$?
[[ $status == 1 && ! -e $RECURSION_LOG ]] || fail 'missing helper stops the menu guard batch'
pass 'missing shared helper fails safely without recursive dispatch'
