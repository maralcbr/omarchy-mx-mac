# Original Omarchy icon on Cobalt

Uses the unchanged project-root icon.png, composited with AppKit onto an opaque #102867 rounded square. Original color, transparency, geometry and orientation are preserved. No generated or redrawn symbol.

Source SHA-256: edd69e61d711d8b423555f27a5afc64935c299f6e7f779112d2ce970ec0236e4

The source has a Display P3 profile. Native color management preserves its appearance; no foreground recoloring is applied.
Canvas: 1024px. Background inset: 64px, corner radius: 180px. Original icon drawn at 720px centered with nearest-neighbor scaling.

Regenerate master:
swift compose.swift original-icon.png Omarchy-Cobalt-1024.png 102867

The iconset contains all ten standard macOS PNG sizes (16px to 1024px).
Compile: iconutil -c icns OmarchyInstaller.iconset -o OmarchyInstaller.icns

Review experiment. Cobalt is palette 07 from the original board; there was no palette named Basalt.
