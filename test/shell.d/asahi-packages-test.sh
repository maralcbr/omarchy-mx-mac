#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

base_manifest="$ROOT/install/omarchy-base-asahi.packages"
other_manifest="$ROOT/install/omarchy-other-asahi.packages"

for package in linux-asahi linux-asahi-headers asahi-desktop-meta asahi-fwextract mesa vulkan-asahi ddcutil qrencode libvips rtkit zbar; do
  grep -Fx "$package" "$base_manifest" "$other_manifest" >/dev/null || fail "Asahi manifests include $package"
done
pass "Asahi manifests include Apple Silicon platform requirements"

forbidden='^(linux|linux-headers|linux-ptl|linux-ptl-headers|limine|limine-mkinitcpio-hook|limine-snapper-sync|snapper|broadcom-wl(-dkms)?|egl-wayland|intel-.*|libva-intel-driver|libva-nvidia-driver|libvpl|vpl-gpu-rt|sof-firmware|thermald|nvidia-.*|lib32-.*|macbook12-spi-driver-dkms|apple-bcm-firmware|apple-t2-audio-config|linux-t2|linux-t2-headers|t2fanrd|tiny-dfr|tuxedo-drivers-nocompatcheck-dkms|yt6801-dkms|kvantum-qt5|qt5-wayland|rust)$'
if grep -Eh "$forbidden" "$base_manifest" "$other_manifest" >"${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$"; then
  detail=$(<"${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$")
  rm -f "${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$"
  fail "Asahi manifests exclude PC-specific package assumptions" "$detail"
fi
rm -f "${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$"
pass "Asahi manifests exclude x86 kernels, Limine, multilib, NVIDIA, Intel, and T2 packages"

# Every default package the x86 install ships is also a default on Apple
# Silicon; packages Arch Linux ARM lacks are built into the omarchy repository.
x86_manifest="$ROOT/install/omarchy-base.packages"
declare -A asahi_equivalent=([mise-bin]=mise [nvim]=neovim [quickshell]=quickshell-git)
while IFS= read -r package; do
  [[ -n $package && $package != \#* ]] || continue
  package=${asahi_equivalent[$package]:-$package}
  grep -Fxq "$package" "$base_manifest" || fail "Asahi manifest carries the x86 default package $package"
done <"$x86_manifest"
for substitute in gnome-calculator wf-recorder python-terminaltexteffects; do
  if grep -Fxq "$substitute" "$base_manifest"; then
    fail "Asahi manifest retired the interim substitute $substitute"
  fi
done
pass "Asahi manifest reaches parity with the x86 default package set"

utilities="$ROOT/default/hypr/bindings/utilities.lua"
grep -Fxq 'o.bind("SUPER + CTRL + Q", "Calculator", "omacalc")' "$utilities" || fail "Asahi calculator shortcut uses omacalc"
grep -Fxq 'o.bind("XF86Calculator", "Calculator", "omacalc")' "$utilities" || fail "Asahi calculator key uses omacalc"
if grep -Fq 'gnome-calculator' "$utilities"; then
  fail "Asahi calculator bindings no longer point at the interim GNOME Calculator"
fi
pass "Asahi defaults use the Omarchy calculator"

nordvpn_installer="$ROOT/bin/omarchy-install-service-nordvpn"
grep -Fxq 'omarchy-pkg-aur-add nordvpn-bin' "$nordvpn_installer" || fail "Asahi NordVPN installation retains the aarch64 AUR path"
if grep -Fxq 'omarchy-pkg-add nordvpn-bin' "$nordvpn_installer"; then
  fail "Asahi NordVPN installation avoids the unavailable direct package"
fi
grep -Fq '"label":"NordVPN [AUR]"' "$ROOT/default/omarchy/omarchy-menu.jsonc" || fail "Asahi menu identifies NordVPN as an AUR install"
pass "Asahi NordVPN installation uses the available package source"
