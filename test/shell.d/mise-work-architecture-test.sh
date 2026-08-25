#!/bin/bash

source "$(dirname "$0")/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/packages"

cat >"$tmp/bin/uname" <<'SH'
#!/bin/bash
printf '%s\n' "$TEST_UNAME"
SH

cat >"$tmp/bin/mise" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$MISE_TEST_LOG"
SH

chmod +x "$tmp/bin/uname" "$tmp/bin/mise"

run_arch_case() {
  local machine="$1" archive_arch="$2" version="$3"
  local home="$tmp/home-$machine" payload="$tmp/payload-$machine"
  local archive="$tmp/packages/node-v$version-linux-$archive_arch.tar.gz"
  local log="$tmp/mise-$machine.log"

  mkdir -p "$home" "$payload/node-v$version-linux-$archive_arch/bin"
  printf '%s\n' "$machine" >"$payload/node-v$version-linux-$archive_arch/bin/node-marker"
  tar -C "$payload" -czf "$archive" "node-v$version-linux-$archive_arch"

  HOME="$home" \
    PATH="$tmp/bin:$PATH" \
    TEST_UNAME="$machine" \
    MISE_TEST_LOG="$log" \
    OMARCHY_SETUP_CONTEXT=iso-chroot \
    OMARCHY_NODE_PACKAGE_DIR="$tmp/packages" \
    bash -eE -c 'source "$1"' bash "$ROOT/install/user/mise-work.sh"

  grep -Fxq "$machine" "$home/.local/share/mise/installs/node/$version/bin/node-marker" ||
    fail "$machine installs the matching bundled Node archive"
  grep -Fxq "use -g node@$version" "$log" ||
    fail "$machine activates the matching bundled Node version"
  pass "$machine uses the $archive_arch Node bundle"
}

run_arch_case aarch64 arm64 26.7.0
run_arch_case x86_64 x64 24.0.0
