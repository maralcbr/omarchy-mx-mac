#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

admission="$ROOT/bin/omarchy-update-apple-boot-admission"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

grep -Fq '# omarchy:hidden=true' "$admission" || fail "boot file admission is hidden from command listings"

# Exact bytes Apple Silicon images wrote, as omarchy-apple-boot ships them.
declare -A laid_down=(
  [/etc/initcpio/install/omarchy-vendorfw]=IyEvYmluL2Jhc2gKIyBTUERYLUxpY2Vuc2UtSWRlbnRpZmllcjogTUlUCgpidWlsZCgpIHsKICAgIGFkZF9iaW5hcnkgdHIKICAgIGFkZF9iaW5hcnkgY3BpbwogICAgYWRkX2ZpbGUgL3Vzci9saWIvb21hcmNoeS9pbml0Y3Bpby9vbWFyY2h5LXZlbmRvcmZ3LnNoCiAgICBhZGRfZmlsZSAvdXNyL2xpYi9vbWFyY2h5L2luaXRjcGlvL29tYXJjaHktdmVuZG9yZncuc2VydmljZSBcCiAgICAgICAgL3Vzci9saWIvc3lzdGVtZC9zeXN0ZW0vb21hcmNoeS12ZW5kb3Jmdy5zZXJ2aWNlIDY0NAogICAgYWRkX3N5bWxpbmsgL3Vzci9saWIvc3lzdGVtZC9zeXN0ZW0vaW5pdHJkLnRhcmdldC53YW50cy9vbWFyY2h5LXZlbmRvcmZ3LnNlcnZpY2UgXAogICAgICAgIC4uL29tYXJjaHktdmVuZG9yZncuc2VydmljZQogICAgYWRkX2RpciAvbGliL2Zpcm13YXJlCiAgICBhZGRfc3ltbGluayAvbGliL2Zpcm13YXJlL3ZlbmRvciAvdmVuZG9yZncKfQoKaGVscCgpIHsKICAgIGNhdCA8PEhFTFBFT0YKU3lzdGVtZC1pbml0cmQgY291bnRlcnBhcnQgb2YgdGhlIGFzYWhpIGhvb2sncyBlYXJseS9sYXRlIHJ1bnNjcmlwdHM6IHVucGFja3MKdGhlIHZlbmRvciBmaXJtd2FyZSBmcm9tIHRoZSBFU1AgYW5kIGNvcGllcyBpdCB0byAvbGliL2Zpcm13YXJlL3ZlbmRvciBvZiB0aGUKcm9vdCBmaWxlc3lzdGVtIGJlZm9yZSB1ZGV2IHByb2JlcyB0aGUgd2lyZWxlc3MsIEJsdWV0b290aCBhbmQgaW5wdXQgZHJpdmVycy4KSEVMUEVPRgp9Cg==
  [/etc/mkinitcpio.conf.d/90-omarchy-asahi.conf]=IyBHZW5lcmF0ZWQgYnkgdGhlIE9tYXJjaHkgQXBwbGUgU2lsaWNvbiBpbWFnZSBidWlsZGVyLgpfb21hcmNoeV9hc2FoaV9ob29rcz0oKQpfb21hcmNoeV9hc2FoaV9hZGRlZD1mYWxzZQpmb3IgX29tYXJjaHlfYXNhaGlfaG9vayBpbiAiJHtIT09LU1tAXX0iOyBkbwogIGlmIFtbICRfb21hcmNoeV9hc2FoaV9ob29rID09IGFzYWhpIF1dOyB0aGVuCiAgICBfb21hcmNoeV9hc2FoaV9hZGRlZD10cnVlCiAgZmkKICBpZiBbWyAkX29tYXJjaHlfYXNhaGlfaG9vayA9PSBmaWxlc3lzdGVtcyAmJiAkX29tYXJjaHlfYXNhaGlfYWRkZWQgPT0gZmFsc2UgXV07IHRoZW4KICAgIF9vbWFyY2h5X2FzYWhpX2hvb2tzKz0oYXNhaGkgb21hcmNoeS12ZW5kb3JmdykKICAgIF9vbWFyY2h5X2FzYWhpX2FkZGVkPXRydWUKICBmaQogIF9vbWFyY2h5X2FzYWhpX2hvb2tzKz0oIiRfb21hcmNoeV9hc2FoaV9ob29rIikKZG9uZQppZiBbWyAkX29tYXJjaHlfYXNhaGlfYWRkZWQgPT0gZmFsc2UgXV07IHRoZW4KICBfb21hcmNoeV9hc2FoaV9ob29rcys9KGFzYWhpIG9tYXJjaHktdmVuZG9yZncpCmZpCkhPT0tTPSgiJHtfb21hcmNoeV9hc2FoaV9ob29rc1tAXX0iKQp1bnNldCBfb21hcmNoeV9hc2FoaV9ob29rcyBfb21hcmNoeV9hc2FoaV9ob29rIF9vbWFyY2h5X2FzYWhpX2FkZGVkCg==
  [/etc/systemd/system/omarchy-vendor-firmware.service]=W1VuaXRdCkRlc2NyaXB0aW9uPUluc3RhbGwgQXBwbGUgdmVuZG9yIGZpcm13YXJlIGludG8gL2xpYi9maXJtd2FyZQpBZnRlcj1sb2NhbC1mcy50YXJnZXQKQ29uZGl0aW9uUGF0aEV4aXN0cz0vYm9vdC9lZmkvdmVuZG9yZncvZmlybXdhcmUudGFyCgpbU2VydmljZV0KVHlwZT1vbmVzaG90ClJlbWFpbkFmdGVyRXhpdD15ZXMKRXhlY1N0YXJ0PS91c3IvYmluL3NoIC1jICdzZXQgLWU7IHNyYz0vYm9vdC9lZmkvdmVuZG9yZncvZmlybXdhcmUudGFyOyBzdGFtcD0vdmFyL2xpYi9vbWFyY2h5L3ZlbmRvci1maXJtd2FyZS5zdGFtcDsgaWYgWyAhIC1mICIkc3RhbXAiIF0gfHwgWyAiJHNyYyIgLW50ICIkc3RhbXAiIF07IHRoZW4gaW5zdGFsbCAtZCAtbSAwNzU1IC9saWIvZmlybXdhcmUgL3Zhci9saWIvb21hcmNoeTsgdGFyIC14ZiAiJHNyYyIgLUMgL2xpYi9maXJtd2FyZTsgdG91Y2ggLXIgIiRzcmMiICIkc3RhbXAiOyBmaScKRXhlY1N0YXJ0UG9zdD0tL3Vzci9iaW4vc2ggLWMgJ21vdW50cG9pbnQgLXEgL2xpYi9maXJtd2FyZS92ZW5kb3IgJiYgZXhpdCAwOyBmb3IgbSBpbiBicmNtZm1hYyBoY2lfYmNtNDM3NzsgZG8gbW9kcHJvYmUgLXIgIiRtIiAyPi9kZXYvbnVsbCB8fCB0cnVlOyBtb2Rwcm9iZSAiJG0iIDI+L2Rldi9udWxsIHx8IHRydWU7IGRvbmUnCgpbSW5zdGFsbF0KV2FudGVkQnk9bXVsdGktdXNlci50YXJnZXQK
  [/usr/lib/omarchy/initcpio/omarchy-vendorfw.service]=W1VuaXRdCkRlc2NyaXB0aW9uPUxvYWQgQXBwbGUgdmVuZG9yIGZpcm13YXJlIGZyb20gdGhlIEVGSSBzeXN0ZW0gcGFydGl0aW9uCkRlZmF1bHREZXBlbmRlbmNpZXM9bm8KQ29uZGl0aW9uUGF0aEV4aXN0cz0vcHJvYy9kZXZpY2UtdHJlZS9jaG9zZW4vYXNhaGksZWZpLXN5c3RlbS1wYXJ0aXRpb24KQWZ0ZXI9c3lzcm9vdC5tb3VudApCZWZvcmU9aW5pdHJkLWZzLnRhcmdldCBpbml0cmQtc3dpdGNoLXJvb3QudGFyZ2V0CgpbU2VydmljZV0KVHlwZT1vbmVzaG90CkV4ZWNTdGFydD0vdXNyL2xpYi9vbWFyY2h5L2luaXRjcGlvL29tYXJjaHktdmVuZG9yZncuc2gK
  [/usr/lib/omarchy/initcpio/omarchy-vendorfw.sh]=IyEvdXNyL2Jpbi9zaApzZXQgLWV1CmR0PS9wcm9jL2RldmljZS10cmVlL2Nob3Nlbi9hc2FoaSxlZmktc3lzdGVtLXBhcnRpdGlvbgpbIC1lICIkZHQiIF0gfHwgZXhpdCAwCmVzcD0kKHRyIC1kICdcMCcgPCIkZHQiKQpbIC1uICIkZXNwIiBdIHx8IGV4aXQgMAptbnQ9L3J1bi9vbWFyY2h5LXZlbmRvcmZ3LWVzcApta2RpciAtcCAiJG1udCIKbW91bnQgLW8gcm8gIlBBUlRVVUlEPSRlc3AiICIkbW50IgppZiBbIC1mICIkbW50L3ZlbmRvcmZ3L2Zpcm13YXJlLmNwaW8iIF07IHRoZW4KICAgIChjZCAvICYmIGNwaW8gLWkgPCIkbW50L3ZlbmRvcmZ3L2Zpcm13YXJlLmNwaW8iKQpmaQp1bW91bnQgIiRtbnQiClsgLWQgL3ZlbmRvcmZ3IF0gfHwgZXhpdCAwCmRzdD0vc3lzcm9vdC9saWIvZmlybXdhcmUvdmVuZG9yCm1rZGlyIC1wICIkZHN0Igptb3VudCAtdCB0bXBmcyAtbyBtb2RlPTA3NTUgdmVuZG9yZncgIiRkc3QiCmNwIC1yIC92ZW5kb3Jmdy8uICIkZHN0Ii8K
)

# $1 root; lays down every image-written file.
image_root() {
  local path
  mkdir -p "$1/var/lib/pacman/local"
  for path in "${!laid_down[@]}"; do
    mkdir -p "$1${path%/*}"
    base64 -d <<<"${laid_down[$path]}" >"$1$path"
  done
}

check() {
  OMARCHY_APPLE_BOOT_ROOT="$1" bash "$admission"
}

# $1 description, $2 root, $3 expected output.
expect() {
  local output
  output=$(check "$2") || fail "$1" "admission exited non-zero"
  [[ $output == "$3" ]] || fail "$1" "expected: $3"$'\n'"got:      $output"
  pass "$1"
}

root="$test_tmp/v2"
image_root "$root"
before=$(cd "$root" && find . -exec stat -c '%n %s %Y %a' {} + | sort | sha256sum)
expect "a Mac with every image-written file intact is adopted" "$root" adopt
[[ $(cd "$root" && find . -exec stat -c '%n %s %Y %a' {} + | sort | sha256sum) == "$before" ]] ||
  fail "the admission check changes nothing on disk"
pass "the admission check changes nothing on disk"

root="$test_tmp/owned"
image_root "$root"
mkdir -p "$root/var/lib/pacman/local/omarchy-apple-boot-20260917-1"
expect "a Mac that already has the package reports it owned" "$root" owned

root="$test_tmp/empty"
mkdir -p "$root/var/lib/pacman/local"
expect "a Mac the image never wrote boot files to is left alone" "$root" "skip: no image-written boot files"

root="$test_tmp/partial"
image_root "$root"
rm "$root/usr/lib/omarchy/initcpio/omarchy-vendorfw.sh"
expect "a Mac missing some of the files is left alone" "$root" "skip: only 4 of 5 image-written boot files are present"

root="$test_tmp/edited"
image_root "$root"
printf '# local change\n' >>"$root/etc/mkinitcpio.conf.d/90-omarchy-asahi.conf"
expect "an edited file keeps the Mac out of adoption" "$root" \
  "skip: /etc/mkinitcpio.conf.d/90-omarchy-asahi.conf differs from what the image laid down"

root="$test_tmp/symlink"
image_root "$root"
mv "$root/etc/systemd/system/omarchy-vendor-firmware.service" "$root/etc/systemd/system/real.service"
ln -s real.service "$root/etc/systemd/system/omarchy-vendor-firmware.service"
expect "a symlink where a file belongs is not adopted" "$root" \
  "skip: /etc/systemd/system/omarchy-vendor-firmware.service is not a regular file"

root="$test_tmp/directory"
image_root "$root"
rm "$root/etc/initcpio/install/omarchy-vendorfw"
mkdir "$root/etc/initcpio/install/omarchy-vendorfw"
expect "a directory where a file belongs is not adopted" "$root" \
  "skip: /etc/initcpio/install/omarchy-vendorfw is not a regular file"

root="$test_tmp/linked-parent"
image_root "$root"
mv "$root/usr/lib/omarchy" "$root/usr/lib/omarchy-real"
ln -s omarchy-real "$root/usr/lib/omarchy"
expect "a symlinked parent directory is not adopted" "$root" "skip: /usr/lib/omarchy is not a plain directory"

root="$test_tmp/foreign"
image_root "$root"
mkdir -p "$root/var/lib/pacman/local/some-other-1.0-1"
printf '%%FILES%%\netc/\netc/initcpio/\netc/initcpio/install/\netc/initcpio/install/omarchy-vendorfw\n' \
  >"$root/var/lib/pacman/local/some-other-1.0-1/files"
expect "a file another package owns is not adopted" "$root" \
  "skip: /etc/initcpio/install/omarchy-vendorfw belongs to another package"

root="$test_tmp/owned-damaged"
image_root "$root"
mkdir -p "$root/var/lib/pacman/local/omarchy-apple-boot-20260917-1"
rm "$root/etc/initcpio/install/omarchy-vendorfw"
expect "an installed package reports owned even with a file deleted; owned is not a health check" "$root" owned

if ((EUID != 0)); then
  root="$test_tmp/unreadable-db"
  image_root "$root"
  mkdir -p "$root/var/lib/pacman/local/some-other-1.0-1"
  printf '%%FILES%%\n' >"$root/var/lib/pacman/local/some-other-1.0-1/files"
  chmod 000 "$root/var/lib/pacman/local/some-other-1.0-1/files"
  expect "an unreadable package database keeps the Mac out of adoption" "$root" "skip: the package database could not be read"
fi
