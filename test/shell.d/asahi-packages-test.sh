#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

base_manifest="$ROOT/install/omarchy-base-asahi.packages"
other_manifest="$ROOT/install/omarchy-other-asahi.packages"

for package in linux-asahi linux-asahi-headers asahi-desktop-meta asahi-fwextract mesa vulkan-asahi; do
  grep -Fx "$package" "$base_manifest" "$other_manifest" >/dev/null || fail "Asahi manifests include $package"
done
pass "Asahi manifests include Apple Silicon platform requirements"

forbidden='^(asdcontrol|linux|linux-headers|linux-ptl|linux-ptl-headers|limine|limine-mkinitcpio-hook|limine-snapper-sync|snapper|broadcom-wl|egl-wayland|intel-.*|libva-intel-driver|libva-nvidia-driver|libvpl|vpl-gpu-rt|sof-firmware|thermald|nvidia-.*|lib32-.*|macbook12-spi-driver-dkms|apple-bcm-firmware|apple-t2-audio-config|linux-t2|linux-t2-headers|t2fanrd|tiny-dfr|tuxedo-drivers-nocompatcheck-dkms|yt6801-dkms)$'
if grep -Eh "$forbidden" "$base_manifest" "$other_manifest" >"${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$"; then
  detail=$(<"${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$")
  rm -f "${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$"
  fail "Asahi manifests exclude PC-specific package assumptions" "$detail"
fi
rm -f "${TMPDIR:-/tmp}/omarchy-asahi-forbidden.$$"
pass "Asahi manifests exclude x86 kernels, Limine, multilib, NVIDIA, Intel, and T2 packages"
