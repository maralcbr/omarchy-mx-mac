#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

installer="$ROOT/bin/omarchy-install-asahi-fresh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

sandbox="$test_tmp/root"
stub_bin="$test_tmp/bin"
bundle="$test_tmp/bundle"
calls="$test_tmp/calls"
keep_server="https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-packages-stable-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
mkdir -p "$stub_bin" "$bundle" "$test_tmp/tmp"

runnable="$test_tmp/omarchy-install-asahi-fresh"
sed \
  -e 's@^(( EUID == 0 )) || fail .*@true # test-only root boundary@' \
  -e 's@^\[\[ \$(uname -m) == "aarch64" \]\] || fail .*@true # test-only architecture boundary@' \
  -e "s#\([ \"=<>]\)\(/proc/\|/usr/share/omarchy\|/boot/\|/var/lib/\|/var/cache/\|/etc/\|/run/lock/\|/sys/\|/usr/lib/modules/\|/home/\|/dev/tty\)#\1$sandbox\2#g" \
  "$installer" >"$runnable"
! grep -Eq '(EUID == 0 \)\) \|\| fail|uname -m)' "$runnable" || fail "the sandbox copy drops the root and architecture boundaries"
! grep -Eq '[ "=<>](/proc/|/boot/|/var/lib/|/var/cache/|/etc/|/run/lock/)' "$runnable" ||
  fail "the sandbox copy touches no system path" "$(grep -En '[ "=<>](/proc/|/boot/|/var/lib/|/var/cache/|/etc/|/run/lock/)' "$runnable")"

stub() {
  cat >"$stub_bin/$1"
  chmod +x "$stub_bin/$1"
}

stub pacman <<'EOF'
#!/bin/bash
installed="$FRESH_TEST_ROOT/installed"
orig=("$@")
dbpath=""
dbonly=0
parsed=()
while (($#)); do
  case "$1" in
    --dbpath) dbpath=$2; shift 2 ;;
    --dbonly) dbonly=1; shift ;;
    *) parsed+=("$1"); shift ;;
  esac
done
set -- "${parsed[@]}"
repositories() {
  awk '/^[[:space:]]*\[[^]]+\][[:space:]]*$/ { gsub(/[][[:space:]]/, ""); if ($0 != "options") { printf "%s%s", sep, $0; sep = "," } }' "$FRESH_TEST_ROOT/etc/pacman.conf"
}
record() {
  printf 'pacman %s\n' "${orig[*]}" >>"$FRESH_TEST_LOG"
}
case "$1" in
  -Q)
    shift
    (($#)) || { sed 's/$/ 1/' "$installed"; exit 0; }
    for package in "$@"; do
      grep -Fxq -- "$package" "$installed" || { echo "error: package '$package' was not found" >&2; exit 1; }
    done
    ;;
  -Qlq)
    grep -Fxq -- "$2" "$installed" || exit 1
    printf '/usr/lib/modules/%s/\n/usr/lib/modules/%s/vmlinuz\n' "$FRESH_TEST_KERNEL_VERSION" "$FRESH_TEST_KERNEL_VERSION"
    ;;
  -Sup)
    record
    [[ ${FRESH_TEST_FAIL:-} != pacman-Sup ]] || exit 1
    cat "$FRESH_TEST_ROOT/printed-sync"
    ;;
  -Up)
    record
    [[ ${FRESH_TEST_FAIL:-} != pacman-Up ]] || exit 1
    if [[ -n $dbpath && -f $dbpath/applied ]]; then
      cat "$FRESH_TEST_ROOT/printed-upgrade"
    else
      cat "$FRESH_TEST_ROOT/printed-upgrade-independent"
    fi
    ;;
  -Su)
    shift
    ignored="" targets=()
    while (($#)); do
      case "$1" in
        --ignore) ignored=$2; shift ;;
        -*) ;;
        *) targets+=("$1") ;;
      esac
      shift
    done
    if (( dbonly )); then
      [[ -n $dbpath ]] || { echo "error: --dbonly requires --dbpath" >&2; exit 1; }
      mkdir -p "$dbpath"
      cat "$installed" >"$dbpath/installed"
      printf '%s\n' "${targets[@]}" >>"$dbpath/installed"
      : >"$dbpath/applied"
      record
      echo "pacman -Su --dbonly ignore=$ignored dbpath=$dbpath repositories=$(repositories)" >>"$FRESH_TEST_LOG"
      exit 0
    fi
    echo "pacman -Su ignore=$ignored repositories=$(repositories)" >>"$FRESH_TEST_LOG"
    printf '%s\n' "${targets[@]}" >>"$installed"
    ;;
  -Syu)
    shift
    ignored="" targets=()
    while (($#)); do
      case "$1" in
        --ignore) ignored=$2; shift ;;
        -*) ;;
        *) targets+=("$1") ;;
      esac
      shift
    done
    echo "pacman -Syu ignore=$ignored repositories=$(repositories)" >>"$FRESH_TEST_LOG"
    printf '%s\n' "${targets[@]}" >>"$installed"
    ;;
  -U)
    echo "pacman -U" >>"$FRESH_TEST_LOG"
    for archive in "$@"; do
      [[ $archive == -* ]] || basename "$archive" | sed 's/-[^-]*-[^-]*-[^-]*\.pkg\.tar\..*$//' >>"$installed"
    done
    ;;
  *) echo "unexpected pacman $*" >>"$FRESH_TEST_LOG"; exit 1 ;;
esac
EOF

real_pacman_conf=$(command -v pacman-conf)
[[ -n $real_pacman_conf ]] || fail "pacman-conf is required to test LocalFileSigLevel tokens"
stub pacman-conf <<EOF
#!/bin/bash
conf="\$FRESH_TEST_ROOT/etc/pacman.conf"
while ((\$#)); do
  case "\$1" in
    --config) conf=\$2; shift 2 ;;
    --repo-list) break ;;
    LocalFileSigLevel)
      exec "$real_pacman_conf" --config "\$conf" LocalFileSigLevel
      ;;
    *) shift ;;
  esac
done
awk '/^[[:space:]]*\\[[^]]+\\][[:space:]]*\$/ { gsub(/[][[:space:]]/, ""); if (\$0 != "options") print }' "\$conf"
EOF

stub getent <<'EOF'
#!/bin/bash
[[ $1 == passwd ]] || exit 2
awk -F: -v key="$2" '$1 == key || $3 == key { print; found = 1 } END { exit !found }' "$FRESH_TEST_ROOT/passwd" || exit 2
EOF

stub useradd <<'EOF'
#!/bin/bash
echo "useradd $*" >>"$FRESH_TEST_LOG"
while (($# > 1)); do
  case "$1" in
    --uid) uid=$2; shift 2 ;;
    --home-dir) home=$2; shift 2 ;;
    --shell) shell=$2; shift 2 ;;
    --comment) comment=$2; shift 2 ;;
    --groups) shift 2 ;;
    *) shift ;;
  esac
done
printf '%s:x:%s:%s:%s:%s:%s\n' "$1" "$uid" "$uid" "$comment" "$home" "$shell" >>"$FRESH_TEST_ROOT/passwd"
mkdir -p "$home"
EOF

stub usermod <<'EOF'
#!/bin/bash
echo "usermod $*" >>"$FRESH_TEST_LOG"
if [[ $1 == --comment ]]; then
  awk -F: -v OFS=: -v user="$3" -v comment="$2" '$1 == user { $5 = comment } { print }' "$FRESH_TEST_ROOT/passwd" >"$FRESH_TEST_ROOT/passwd.new"
  mv "$FRESH_TEST_ROOT/passwd.new" "$FRESH_TEST_ROOT/passwd"
fi
EOF

stub id <<'EOF'
#!/bin/bash
echo "$2 wheel"
EOF

for logged in gpasswd passwd runuser update-m1n1 omarchy-apply-system omarchy-apple-silicon-boot-check; do
  stub "$logged" <<EOF
#!/bin/bash
echo "$logged \$*" >>"\$FRESH_TEST_LOG"
[[ \${FRESH_TEST_FAIL:-} != $logged ]] || exit 1
EOF
done

stub mkinitcpio <<'EOF'
#!/bin/bash
echo "mkinitcpio $*" >>"$FRESH_TEST_LOG"
printf 'usr/lib/modules/%s/kernel/hid.ko\n' "$FRESH_TEST_KERNEL_VERSION" >"$FRESH_TEST_ROOT/boot/initramfs-$FRESH_TEST_KERNEL.img"
EOF

stub update-grub <<'EOF'
#!/bin/bash
echo "update-grub $*" >>"$FRESH_TEST_LOG"
printf '# generated\nlinux /vmlinuz-%s root=UUID=test\ninitrd /initramfs-%s.img\n' "$FRESH_TEST_KERNEL" "$FRESH_TEST_KERNEL" >"$FRESH_TEST_ROOT/boot/grub/grub.cfg"
EOF

stub lsinitcpio <<'EOF'
#!/bin/bash
[[ $1 == -l ]] && cat "$2"
EOF

stub NetworkManager <<'EOF'
#!/bin/bash
echo "wifi.backend=iwd"
EOF

stub swapon <<'EOF'
#!/bin/bash
EOF

stub tty <<'EOF'
#!/bin/bash
EOF

stub chown <<'EOF'
#!/bin/bash
EOF

runtime="$test_tmp/runtime"
mkdir -p "$runtime/usr/bin" "$runtime/usr/share/omarchy/default" "$runtime/usr/share/omarchy/install"
: >"$runtime/usr/share/omarchy/default/omarchy-release.gpg"
: >"$runtime/usr/share/omarchy/default/omarchy-arm-repository.asc"
printf '%s\n' hyprland linux-aurora linux-aurora-headers m1n1-aurora omarchy-dev >"$runtime/usr/share/omarchy/install/omarchy-base-asahi.packages"

cat >"$runtime/usr/bin/omarchy-update-asahi-repository" <<'EOF'
#!/bin/bash
echo "bootstrap $* sudo=$(command -v sudo) path=$OMARCHY_PATH" >>"$FRESH_TEST_LOG"
conf="$FRESH_TEST_ROOT/etc/pacman.conf"
awk '
  /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { skip = ($0 ~ /\[omarchy\]/) }
  !placed && /^[[:space:]]*\[[^]]+\][[:space:]]*$/ && !/\[options\]/ { print "[omarchy]\nServer = https://example.test/omarchy\n"; placed = 1 }
  !skip { print }
' "$conf" >"$conf.new"
mv "$conf.new" "$conf"
EOF

cat >"$runtime/usr/bin/omarchy-apple-silicon-channel" <<'EOF'
#!/bin/bash
echo "channel $*" >>"$FRESH_TEST_LOG"
[[ $1 == status ]] || exit 2
[[ -z ${FRESH_TEST_CHANNEL_STATUS:-} ]] || exit "$FRESH_TEST_CHANNEL_STATUS"
[[ -n ${FRESH_TEST_CHANNEL:-} ]] || exit 3
printf 'channel=%s\nkernel=%s\n' "$FRESH_TEST_CHANNEL" "$FRESH_TEST_KERNEL"
EOF

cat >"$runtime/usr/bin/omarchy-update-aurora-repository" <<'EOF'
#!/bin/bash
echo "aurora $* sudo=$(command -v sudo) path=$OMARCHY_PATH offline=${OMARCHY_AURORA_OFFLINE:-}" >>"$FRESH_TEST_LOG"
[[ ${FRESH_TEST_FAIL:-} != aurora ]] || exit 2
conf="$FRESH_TEST_ROOT/etc/pacman.conf"
awk '
  /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { skip = ($0 ~ /\[omarchy-aurora\]/) }
  /^[[:space:]]*\[omarchy\][[:space:]]*$/ { print "[omarchy-aurora]\nServer = https://example.test/aurora\n" }
  !skip { print }
' "$conf" >"$conf.new"
mv "$conf.new" "$conf"
EOF
chmod +x "$runtime/usr/bin"/*

bsdtar -cf "$bundle/omarchy-dev-4.0.3-1-aarch64.pkg.tar.zst" -C "$runtime" usr
mkdir -p "$test_tmp/settings/usr/share/omarchy-settings"
bsdtar -cf "$bundle/omarchy-settings-dev-4.0.3-1-aarch64.pkg.tar.zst" -C "$test_tmp/settings" usr
for package in omarchy-keyring omarchy-nvim quickshell-git ttf-jetbrains-mono-nerd-basic; do
  : >"$bundle/$package-1-1-any.pkg.tar.zst"
done

builder_grub=$'# written by the image builder\nlinux /vmlinuz-KERNEL\ninitrd /initramfs-KERNEL.img'
pin_omarchy=0

reset_sandbox() {
  local kernel=${1:-linux-aurora} version=${2:-6.99.0-aurora} m1n1=${3:-m1n1-aurora}
  [[ $kernel != linux-aurora || -n ${3:-} ]] || m1n1=m1n1-aurora

  rm -rf "$sandbox"
  mkdir -p "$sandbox"/{proc/device-tree,boot/grub,etc/pacman.d,etc/NetworkManager,run/lock,sys/module/zswap/parameters,home,dev} \
    "$sandbox/usr/share/omarchy" "$sandbox/usr/lib/modules/$version" "$sandbox/var/lib/pacman/local" \
    "$sandbox/var/cache/pacman/pkg"
  printf 'apple,j314s\0apple,arm-platform\0' >"$sandbox/proc/device-tree/compatible"
  echo "4.0.3" >"$sandbox/usr/share/omarchy/version"
  echo "$kernel" >"$sandbox/usr/share/omarchy/apple-silicon-kernel"
  echo "kernel image $version" >"$sandbox/usr/lib/modules/$version/vmlinuz"
  cp "$sandbox/usr/lib/modules/$version/vmlinuz" "$sandbox/boot/vmlinuz-$kernel"
  printf '%s\n' "${builder_grub//KERNEL/$kernel}" >"$sandbox/boot/grub/grub.cfg"
  {
    cat <<'CONF'
[options]
Architecture = aarch64
LocalFileSigLevel = Required

CONF
    if (( pin_omarchy )); then
      printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\n\n' "$keep_server"
    fi
    cat <<'CONF'
[asahi-alarm]
Server = https://example.test/asahi-alarm

[core]
Server = https://example.test/core

[extra]
Server = https://example.test/extra

[alarm]
Server = https://example.test/alarm

[aur]
Server = https://example.test/aur
CONF
  } >"$sandbox/etc/pacman.conf"
  echo 'LANG=en_US.UTF-8' >"$sandbox/etc/locale.conf"
  printf 'UID_MIN 1000\nUID_MAX 60000\n' >"$sandbox/etc/login.defs"
  echo N >"$sandbox/sys/module/zswap/parameters/enabled"
  printf '%s\n' base grub jq networkmanager iwd "$kernel" "$kernel-headers" "$m1n1" >"$sandbox/installed"
  printf 'root:x:0:0::/root:/bin/bash\nalarm:x:1000:1000::/home/alarm:/bin/bash\n' >"$sandbox/passwd"
  printf 'hyprland-archive\n' >"$sandbox/var/cache/pacman/pkg/hyprland-1-1-aarch64.pkg.tar.zst"
  printf 'dep-archive\n' >"$sandbox/var/cache/pacman/pkg/wayland-1-1-aarch64.pkg.tar.zst"
  hyprland_hash=$(sha256sum "$sandbox/var/cache/pacman/pkg/hyprland-1-1-aarch64.pkg.tar.zst" | cut -d' ' -f1)
  wayland_hash=$(sha256sum "$sandbox/var/cache/pacman/pkg/wayland-1-1-aarch64.pkg.tar.zst" | cut -d' ' -f1)
  printf 'https://example.test/hyprland-1-1-aarch64.pkg.tar.zst %s\nhttps://example.test/wayland-1-1-aarch64.pkg.tar.zst %s\n' \
    "$hyprland_hash" "$wayland_hash" >"$sandbox/printed-sync"
  printf '%s %s\n' "$bundle/omarchy-dev-4.0.3-1-aarch64.pkg.tar.zst" "local" >"$sandbox/printed-upgrade"
  printf '%s %s\nhttps://example.test/extra-provider-1-1-aarch64.pkg.tar.zst %s\n' \
    "$bundle/omarchy-dev-4.0.3-1-aarch64.pkg.tar.zst" "local" "$(printf '%064d' 2)" \
    >"$sandbox/printed-upgrade-independent"
  kernel_name=$kernel
  kernel_version=$version
  : >"$calls"
}

run_installer() {
  local name=$1 assignments=()
  shift
  while (($#)) && [[ $1 == *=* && $1 != -* ]]; do
    assignments+=("$1")
    shift
  done
  env -u FRESH_TEST_FAIL -u FRESH_TEST_CHANNEL -u FRESH_TEST_CHANNEL_STATUS \
    PATH="$stub_bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin" \
    TMPDIR="$test_tmp/tmp" \
    FRESH_TEST_ROOT="$sandbox" \
    FRESH_TEST_LOG="$calls" \
    FRESH_TEST_KERNEL="$kernel_name" \
    FRESH_TEST_KERNEL_VERSION="$kernel_version" \
    OMARCHY_ASAHI_PACKAGE_SOURCE=1111111111111111111111111111111111111111 \
    OMARCHY_ASAHI_RELEASE_SEQUENCE=7 \
    OMARCHY_ASAHI_RELEASE_TAG=asahi-quattro-fe8d2bf8 \
    OMARCHY_ASAHI_RELEASE_SOURCE=2222222222222222222222222222222222222222 \
    "${assignments[@]}" bash "$runnable" --asahi-packages "$bundle" "$@" \
    >"$test_tmp/$name.out" 2>"$test_tmp/$name.err" </dev/null
}

expect_success() {
  [[ $1 == 0 ]] || fail "$2" "$(cat "$test_tmp/$3.out" "$test_tmp/$3.err")"
}

expect_failure() {
  local status=$1 name=$2 message=$3 description=$4
  [[ $status != 0 ]] || fail "$description (it succeeded)" "$(cat "$test_tmp/$name.out")"
  grep -Fq -- "$message" "$test_tmp/$name.err" || fail "$description" "$(cat "$test_tmp/$name.err")"
}

called() {
  grep -Eq "$1" "$calls"
}

no_refresh() {
  ! grep -Eq 'pacman -S[^ ]*y| --refresh( |$)| -y( |$)' "$calls" ||
    fail "$1" "$(cat "$calls")"
}

no_transaction() {
  ! grep -Eq '^pacman -Su ignore=' "$calls" && ! grep -Fxq 'pacman -U' "$calls" ||
    fail "$1" "$(cat "$calls")"
}

bash -n "$runnable"
"$installer" --help 2>&1 | grep -Fq -- '[--offline]' || fail "the fresh installer documents --offline"
pass "the usage line documents --offline beside --user/--deferred-user"

siglevel_ok() {
  grep -Fxq PackageRequired <<<"$1" && return 0
  grep -Fxq Required <<<"$1" && ! grep -Fxq PackageOptional <<<"$1"
}
siglevel_tmp=$(mktemp -d)
cat >"$siglevel_tmp/accept.conf" <<'EOF'
[options]
Architecture = auto
LocalFileSigLevel = Required

[core]
Server = file:///tmp
EOF
cat >"$siglevel_tmp/refuse.conf" <<'EOF'
[options]
Architecture = auto
LocalFileSigLevel = Optional

[core]
Server = file:///tmp
EOF
accept_tokens=$("$real_pacman_conf" --config "$siglevel_tmp/accept.conf" LocalFileSigLevel)
refuse_tokens=$("$real_pacman_conf" --config "$siglevel_tmp/refuse.conf" LocalFileSigLevel)
grep -Fxq PackageRequired <<<"$accept_tokens" || fail "Required expands to PackageRequired" "$accept_tokens"
! grep -Fxq Required <<<"$accept_tokens" || fail "Required is not printed unexpanded" "$accept_tokens"
grep -Fxq PackageOptional <<<"$refuse_tokens" || fail "Optional expands to PackageOptional" "$refuse_tokens"
siglevel_ok "$accept_tokens" || fail "the installer predicate accepts Required" "$accept_tokens"
if siglevel_ok "$refuse_tokens"; then
  fail "the installer predicate refuses Optional" "$refuse_tokens"
fi
rm -rf "$siglevel_tmp"
pass "real pacman-conf LocalFileSigLevel: Required accepted, Optional refused"

pin_omarchy=0
reset_sandbox
status=0
run_installer online --deferred-user || status=$?
expect_success "$status" "a non-offline deferred install still completes" online
called '^bootstrap --yes --bootstrap ' || fail "non-offline still bootstraps the package repository" "$(cat "$calls")"
grep -Fq 'pacman -Syu ignore=linux-aurora,linux-aurora-headers,m1n1-aurora' "$calls" ||
  fail "non-offline still refreshes with -Syu" "$(cat "$calls")"
! called '^pacman -Su ignore=' || fail "non-offline never uses -Su"
pass "non-offline deferred installs still bootstrap and run pacman -Syu"

pin_omarchy=1
reset_sandbox
status=0
run_installer offline OMARCHY_ASAHI_KEEP_SERVER="$keep_server" --offline --deferred-user || status=$?
expect_success "$status" "an offline deferred install completes" offline
! called '^bootstrap ' || fail "offline skips the repository bootstrap" "$(cat "$calls")"
no_refresh "offline emits no database refresh"
grep -Fq -- "-Sup --print-format %l %h --needed --noconfirm --ignore linux-aurora,linux-aurora-headers,m1n1-aurora" "$calls" ||
  fail "offline prints the repository transaction with -Sup" "$(cat "$calls")"
grep -Eq -- '--dbpath [^ ]+ -Su --dbonly' "$calls" ||
  fail "offline applies transaction 1 to a disposable database copy" "$(cat "$calls")"
grep -Eq -- '--dbpath [^ ]+ -Up --print --print-format %l %h --needed --noconfirm' "$calls" ||
  fail "offline prints the six archives against the simulated database" "$(cat "$calls")"
grep -Fxq 'pacman -Su ignore=linux-aurora,linux-aurora-headers,m1n1-aurora repositories=omarchy-aurora,omarchy,asahi-alarm,core,extra,alarm,aur' "$calls" ||
  fail "offline installs with -Su against the pinned [omarchy] section" "$(cat "$calls")"
called '^pacman -U$' || fail "offline still installs the six archives"
called '^omarchy-apply-system --defer-provisioning --first-install$' || fail "offline still runs deferred system setup"
grep -Fxq 'omarchy-apple-silicon-boot-check linux-aurora' "$calls" ||
  fail "offline still checks the boot chain" "$(cat "$calls")"
grep -Fq extra-provider "$sandbox/printed-upgrade-independent" ||
  fail "independent txn 2 names a provider that is not cached"
! grep -Fq extra-provider "$sandbox/printed-upgrade" || fail "sequential txn 2 does not name the extra provider"
[[ ! -e $sandbox/var/cache/pacman/pkg/extra-provider-1-1-aarch64.pkg.tar.zst ]] ||
  fail "the extra provider archive is not in the cache"
sup_line=$(grep -n -- '-Sup --print-format' "$calls" | head -1 | cut -d: -f1)
dbonly_line=$(grep -n -- '--dbonly' "$calls" | head -1 | cut -d: -f1)
up_line=$(grep -n -- '-Up --print' "$calls" | head -1 | cut -d: -f1)
su_line=$(grep -n '^pacman -Su ignore=' "$calls" | head -1 | cut -d: -f1)
[[ -n $sup_line && -n $dbonly_line && -n $up_line && -n $su_line ]] ||
  fail "sequential print-then-apply steps are logged" "$(cat "$calls")"
(( sup_line < dbonly_line && dbonly_line < up_line && up_line < su_line )) ||
  fail "transaction 2 is resolved after transaction 1 is simulated" "$(cat "$calls")"
pass "offline deferred install skips bootstrap, simulates sequentially, then installs with -Su"

reset_sandbox linux-aurora 6.99.0-aurora
status=0
run_installer aurora OMARCHY_ASAHI_KEEP_SERVER="$keep_server" FRESH_TEST_CHANNEL=rc --offline --deferred-user || status=$?
expect_success "$status" "an offline rc install completes" aurora
! called '^bootstrap ' || fail "an offline rc install still skips bootstrap"
grep -Eq '^aurora  sudo=[^ ]+/sudo/sudo path=[^ ]+/usr/share/omarchy offline=1$' "$calls" ||
  fail "the Aurora updater runs offline from the verified runtime" "$(cat "$calls")"
grep -Fxq 'pacman -Su ignore=linux-aurora,linux-aurora-headers,m1n1-aurora repositories=omarchy-aurora,omarchy,asahi-alarm,core,extra,alarm,aur' "$calls" ||
  fail "offline rc holds the Aurora boot packages" "$(cat "$calls")"
pass "offline rc pins Aurora with OMARCHY_AURORA_OFFLINE=1 and no bootstrap"

reset_sandbox
printf 'https://example.test/missing-1-1-aarch64.pkg.tar.zst %s\n' "$(printf '%064d' 1)" >"$sandbox/printed-sync"
status=0
run_installer missing OMARCHY_ASAHI_KEEP_SERVER="$keep_server" --offline --deferred-user || status=$?
[[ $status == 4 ]] || fail "a missing cached archive exits 4" "status $status: $(cat "$test_tmp/missing.err")"
grep -Fq 'Cached archive is missing: missing-1-1-aarch64.pkg.tar.zst' "$test_tmp/missing.err" ||
  fail "a missing cached archive is named" "$(cat "$test_tmp/missing.err")"
no_transaction "a missing cached archive installs nothing"
pass "a missing cached archive fails with exit 4 before any transaction"

reset_sandbox
printf 'https://example.test/hyprland-1-1-aarch64.pkg.tar.zst %s\n' "$(printf '%064d' 9)" >"$sandbox/printed-sync"
status=0
run_installer mismatch OMARCHY_ASAHI_KEEP_SERVER="$keep_server" --offline --deferred-user || status=$?
[[ $status == 4 ]] || fail "a mismatched cached archive exits 4" "status $status: $(cat "$test_tmp/mismatch.err")"
grep -Fq 'does not match the database sha256' "$test_tmp/mismatch.err" ||
  fail "a mismatched cached archive is explained" "$(cat "$test_tmp/mismatch.err")"
no_transaction "a mismatched cached archive installs nothing"
pass "a mismatched cached archive fails with exit 4 before any transaction"

reset_sandbox
tokens=$("$real_pacman_conf" --config "$sandbox/etc/pacman.conf" LocalFileSigLevel)
siglevel_ok "$tokens" || fail "the sandbox Required config is accepted by real pacman-conf" "$tokens"
sed 's/^LocalFileSigLevel = Required$/LocalFileSigLevel = Optional/' "$sandbox/etc/pacman.conf" \
  >"$sandbox/etc/pacman.conf.new"
mv "$sandbox/etc/pacman.conf.new" "$sandbox/etc/pacman.conf"
tokens=$("$real_pacman_conf" --config "$sandbox/etc/pacman.conf" LocalFileSigLevel)
grep -Fxq PackageOptional <<<"$tokens" || fail "the sandbox Optional config expands via real pacman-conf" "$tokens"
if siglevel_ok "$tokens"; then
  fail "Optional must not pass the installer predicate" "$tokens"
fi
status=0
run_installer siglevel OMARCHY_ASAHI_KEEP_SERVER="$keep_server" --offline --deferred-user || status=$?
[[ $status == 5 ]] || fail "LocalFileSigLevel Optional exits 5" "status $status: $(cat "$test_tmp/siglevel.err")"
grep -Fq 'LocalFileSigLevel must require package signatures' "$test_tmp/siglevel.err" ||
  fail "LocalFileSigLevel is named" "$(cat "$test_tmp/siglevel.err")"
! grep -Eq '^pacman -S' "$calls" && ! grep -Eq '^pacman -U' "$calls" ||
  fail "LocalFileSigLevel is checked before any pacman print or transaction" "$(cat "$calls")"
pass "real pacman-conf Optional LocalFileSigLevel fails with exit 5 before any pacman print or transaction"

reset_sandbox
: >"$sandbox/dev/tty"
status=0
run_installer named OMARCHY_ASAHI_KEEP_SERVER="$keep_server" --offline --user alice || status=$?
[[ $status == 1 ]] || fail "--offline --user exits 1" "status $status: $(cat "$test_tmp/named.err")"
grep -Fq -- '--offline requires --deferred-user' "$test_tmp/named.err" ||
  fail "--offline --user names the deferred-only restriction" "$(cat "$test_tmp/named.err")"
! called '^useradd ' && ! called '^runuser ' && ! called '^omarchy-apply-system ' && ! called '^omarchy-provision-user ' ||
  fail "--offline --user must not provision a named user" "$(cat "$calls")"
no_transaction "--offline --user installs nothing"
pass "--offline refuses --user so named-user provisioning cannot fetch"

reset_sandbox
status=0
run_installer keep-missing --offline --deferred-user || status=$?
[[ $status == 5 ]] || fail "missing KEEP_SERVER exits 5" "status $status: $(cat "$test_tmp/keep-missing.err")"
grep -Fq 'OMARCHY_ASAHI_KEEP_SERVER must name the expected asahi-packages-stable Server' "$test_tmp/keep-missing.err" ||
  fail "a missing KEEP_SERVER is named" "$(cat "$test_tmp/keep-missing.err")"
! called '^bootstrap ' && no_transaction "a missing KEEP_SERVER installs nothing"
pass "OMARCHY_ASAHI_KEEP_SERVER is mandatory in --offline mode"

reset_sandbox
status=0
run_installer keep-mismatch OMARCHY_ASAHI_KEEP_SERVER="${keep_server}ffff" --offline --deferred-user || status=$?
[[ $status == 5 ]] || fail "a KEEP_SERVER mismatch exits 5" "status $status: $(cat "$test_tmp/keep-mismatch.err")"
grep -Fq 'does not match OMARCHY_ASAHI_KEEP_SERVER' "$test_tmp/keep-mismatch.err" ||
  fail "a KEEP_SERVER mismatch is named" "$(cat "$test_tmp/keep-mismatch.err")"
! called '^bootstrap ' && no_transaction "a KEEP_SERVER mismatch installs nothing"
pass "OMARCHY_ASAHI_KEEP_SERVER must match the pinned [omarchy] Server"

pin_omarchy=0
reset_sandbox
status=0
run_installer repo-order OMARCHY_ASAHI_KEEP_SERVER="$keep_server" --offline --deferred-user || status=$?
[[ $status == 5 ]] || fail "a missing [omarchy] section exits 5" "status $status: $(cat "$test_tmp/repo-order.err")"
grep -Fq 'The [omarchy] repository must come before every other repository' "$test_tmp/repo-order.err" ||
  fail "a missing [omarchy] section is named" "$(cat "$test_tmp/repo-order.err")"
no_transaction "a missing [omarchy] section installs nothing"
pass "malformed [omarchy] configuration exits 5"
pin_omarchy=1

reset_sandbox linux-aurora 6.99.0-aurora
status=0
run_installer aurora-fail OMARCHY_ASAHI_KEEP_SERVER="$keep_server" FRESH_TEST_CHANNEL=rc FRESH_TEST_FAIL=aurora --offline --deferred-user || status=$?
[[ $status == 6 ]] || fail "an Aurora offline refusal exits 6" "status $status: $(cat "$test_tmp/aurora-fail.err")"
grep -Fq 'Could not pin the Aurora kernel repository' "$test_tmp/aurora-fail.err" ||
  fail "an Aurora offline refusal is named" "$(cat "$test_tmp/aurora-fail.err")"
no_transaction "an Aurora offline refusal installs nothing"
pass "Aurora pin/descriptor refusal exits 6"
