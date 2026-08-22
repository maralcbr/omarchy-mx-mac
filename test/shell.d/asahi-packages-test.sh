#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

base_manifest="$ROOT/install/omarchy-base-asahi.packages"
other_manifest="$ROOT/install/omarchy-other-asahi.packages"

for package in linux-asahi linux-asahi-headers asahi-desktop-meta asahi-fwextract mesa vulkan-asahi ddcutil gnome-calculator qrencode libvips zbar; do
  grep -Fx "$package" "$base_manifest" "$other_manifest" >/dev/null || fail "Asahi manifests include $package"
done
pass "Asahi manifests include Apple Silicon platform requirements"

forbidden='^(asdcontrol|linux|linux-headers|linux-ptl|linux-ptl-headers|limine|limine-mkinitcpio-hook|limine-snapper-sync|snapper|broadcom-wl|egl-wayland|intel-.*|libva-intel-driver|libva-nvidia-driver|libvpl|vpl-gpu-rt|sof-firmware|thermald|nvidia-.*|lib32-.*|macbook12-spi-driver-dkms|apple-bcm-firmware|apple-t2-audio-config|linux-t2|linux-t2-headers|t2fanrd|tiny-dfr|tuxedo-drivers-nocompatcheck-dkms|yt6801-dkms|kvantum-qt5|omacalc|qt5-wayland|rust)$'
if grep -Eh "$forbidden" "$base_manifest" "$other_manifest" >"${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$"; then
  detail=$(<"${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$")
  rm -f "${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$"
  fail "Asahi manifests exclude PC-specific package assumptions" "$detail"
fi
rm -f "${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$"
pass "Asahi manifests exclude x86 kernels, Limine, multilib, NVIDIA, Intel, and T2 packages"

utilities="$ROOT/default/hypr/bindings/utilities.lua"
grep -Fxq 'o.bind("SUPER + CTRL + Q", "Calculator", "gnome-calculator")' "$utilities" || fail "Asahi calculator shortcut uses the available GNOME Calculator"
grep -Fxq 'o.bind("XF86Calculator", "Calculator", "gnome-calculator")' "$utilities" || fail "Asahi calculator key uses the available GNOME Calculator"
if grep -Fq '"omacalc"' "$utilities"; then
  fail "Asahi calculator bindings exclude unavailable omacalc"
fi
grep -Fq '"org.gnome.Calculator"' "$ROOT/default/hypr/apps/system.lua" || fail "Asahi window rules match GNOME Calculator"
pass "Asahi defaults retain GNOME Calculator"

nordvpn_installer="$ROOT/bin/omarchy-install-service-nordvpn"
grep -Fxq 'omarchy-pkg-aur-add nordvpn-bin' "$nordvpn_installer" || fail "Asahi NordVPN installation retains the aarch64 AUR path"
if grep -Fxq 'omarchy-pkg-add nordvpn-bin' "$nordvpn_installer"; then
  fail "Asahi NordVPN installation avoids the unavailable direct package"
fi
grep -Fq '"label":"NordVPN [AUR]"' "$ROOT/default/omarchy/omarchy-menu.jsonc" || fail "Asahi menu identifies NordVPN as an AUR install"
pass "Asahi NordVPN installation uses the available package source"

zed_installer="$ROOT/bin/omarchy-install-editor-zed"
if grep -Eq 'omarchy-pkg-add[[:space:]]+zed[[:space:]]+omazed' "$zed_installer"; then
  fail "Zed installer does not require unpublished omazed"
fi
grep -Fxq 'omarchy-pkg-add zed' "$zed_installer" || fail "Zed installer still installs zed"
grep -Fxq 'if omarchy-pkg-available omazed; then' "$zed_installer" || fail "Zed installer treats omazed as architecture-optional"
pass "Zed installer does not require unpublished omazed"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const unguarded = items.filter(item =>
  item.id.startsWith('install.') &&
  /omarchy-pkg-present /.test(item.when) &&
  !/\[AUR\]/.test(item.label) &&
  !/omarchy-pkg-available /.test(item.when)
).map(item => item.id)
assertDeepEqual(unguarded, [], 'install menu rows hide packages missing from the sync database')
JS
