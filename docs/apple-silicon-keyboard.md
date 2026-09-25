# Apple Silicon keyboard

How the built-in keyboard of an Apple Silicon Mac behaves on Omarchy, and how
to tell a layout problem from a boot image problem (#235).

## Top row: media keys first

The internal keyboard binds to `hid_apple`: over SPI on M1 laptops
(`spi-hid-apple`), over dockchannel/MTP on later ones. Its `fnmode` parameter
decides what the top row sends:

| fnmode | Top row without Fn | With Fn |
| --- | --- | --- |
| 1 (fkeyslast) | mute, volume, brightness, media | F1-F12 |
| 2 (fkeysfirst) | F1-F12 | mute, volume, brightness, media |
| 3 (auto, kernel default) | 1 on Apple keyboards, 2 on the non-Apple boards `hid_apple` recognises | |

`install/hardware/fix-fkeys.sh` writes `/etc/modprobe.d/hid_apple.conf`. On
x86 it keeps upstream's `fnmode=2`, so Apple-like boards such as the Lofree
Flow84 keep F-keys first. On Apple Silicon it writes `fnmode=3`: F10 mutes,
F11 and F12 change the volume, as in macOS, and Fn+F9 sends F9 (the voxtype
push-to-talk key). Migration `1790305681` moves Macs that still carry the
stock `options hid_apple fnmode=2` line to `fnmode=3`. Any other
`hid_apple.conf` is the owner's and stays. `hid_apple` loads from the
initramfs, and `modconf` copies `/etc/modprobe.d` into it, so the migration
rebuilds the boot image (`omarchy-mac-boot-update` on a Limine Mac,
`mkinitcpio -P` on a GRUB Mac). It then writes
`/sys/module/hid_apple/parameters/fnmode`, so the change applies without a
reboot. To keep F-keys first, write `options hid_apple fnmode=2` to that file
and rebuild the boot image.

## ISO keyboards and Mac key legends

Apple ISO keyboards report the key left of `1` and the key left of `Z`
swapped. `hid_apple` swaps them back when `iso_layout` is `-1` (auto) and the
keyboard reports the ISO country code. SPI and MTP keyboards carry
`APPLE_ISO_TILDE_QUIRK`, so Omarchy leaves `iso_layout` at auto. Forcing it
would break keyboards the kernel already handles.

A key that types the PC character instead of the one printed on the key is a
layout problem, not a swap problem. On a Danish MacBook the key left of `1`
is printed with `$`, and it types `½` because XKB's `dk` layout is the PC layout.
If the swap were wrong, the key would type `<`. `dk(mac)` only changes the
`-` key and the space bar. The Mac legends come from
`macintosh_vndr/dk(macbookpro)`, which is only reachable with
`XKBMODEL=applealu_iso XKBLAYOUT=dk XKBVARIANT=macbookpro` (checked with
`xkbcli compile-keymap`, xkeyboard-config 2.42). Changing the layout also
changes the disk passphrase prompt, which reads the same settings.

## Disk passphrase prompt layout

On an encrypted Mac the passphrase is typed before the root is mounted, so the
layout comes from the boot image, not from Hyprland:

- The console prompt (`plymouth.enable=0`) uses the kernel keymap.
  `systemd-vconsole-setup`, which the `sd-vconsole` hook adds, runs `loadkeys`
  with `KEYMAP` from the image's `/etc/vconsole.conf`.
- Plymouth reads keys through evdev and builds an XKB keymap from `XKBLAYOUT`,
  `XKBMODEL`, `XKBVARIANT` and `XKBOPTIONS` in the same file. It needs the XKB
  data the plymouth hook copies. Without an XKB keymap it falls back to the
  terminal, which means the kernel keymap.

omarchy-pkgs `94-omarchy-mac-vconsole.conf` puts `sd-vconsole` and
`/etc/vconsole.conf` in every systemd image. `omarchy-apple-silicon-boot-check`
fails when the booted image (the UKI on a Limine Mac) does not carry
`/etc/vconsole.conf`'s keyboard settings, `systemd-vconsole-setup`,
`loadkeys`, the `KEYMAP` file, or, when Plymouth is in the image, the XKB
symbols of each layout. On a live Mac it also warns when
`systemd-vconsole-setup` failed during the current boot.

`Configuration of first virtual console was skipped, ignoring remaining ones.`
is not a keymap failure. `systemd-vconsole-setup` logs it when no `FONT` is
set: only the font copy to the other consoles is skipped, and `loadkeys` has
already run.

### When the prompt still types US

Run these after unlocking (typing US-style if needed). For the Plymouth
lines, first boot once with `plymouth.debug` added to the Limine entry
(press `E`):

```bash
cat /proc/cmdline
cat /etc/vconsole.conf
sudo omarchy-apple-silicon-boot-check
journalctl -b -o short-monotonic | grep -iE 'vconsole|loadkeys|keymap'
sudo dumpkeys | grep -E '^keycode +(12|53) '
sudo grep -E 'KEYMAP|XKBLAYOUT|input device|keymap' /var/log/plymouth-debug.log | head -40
sudo dmesg | grep -i 'initrd memory'
esp=$(sed -n 's/^ESP_PATH="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/default/limine)
sudo objcopy -O binary --only-section=.initrd "$esp/EFI/Linux/omarchy_$(pacman -Qq linux-asahi linux-aurora 2>/dev/null | head -1).efi" /tmp/uki.initrd
stat -c %s /tmp/uki.initrd
sudo grep -nE '^(default_entry|remember_last_entry|/|  //|    path)' "$esp/limine.conf"
```

How to read them:

- In `dumpkeys`, keycode 53 is `minus` with `dk-latin1` and `slash` with the
  US map. The root system's console should show `minus`.
- `loadkeys` errors in the journal, or a vconsole unit that failed, point to
  the console setup, not to the image.
- The Plymouth log shows which `KEYMAP` and `XKBLAYOUT` Plymouth read from the
  booted image and whether it opened the keyboard as an input device.
- The freed initrd size should be close to the size of the UKI's `.initrd`.
  A very different size means a different image booted than the one the boot
  check read.
