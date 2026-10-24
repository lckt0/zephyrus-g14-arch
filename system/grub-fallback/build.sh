#!/usr/bin/env bash
# build.sh -- builds, signs and installs the standalone fallback GRUB for the G14.
#
#   ./build.sh build     # build into ./build only (does not touch the ESP)
#   ./build.sh sign      # build + write build/grubx64.signed.efi (sbctl -o, not
#                        # added to sbctl's database) -- use this copy for QEMU tests
#   ./build.sh install   # copy the EXISTING build/grubx64.efi to the ESP and sign it
#                        # in place with `sbctl sign -s` (added to the database).
#                        # Does not rebuild: grub-mkstandalone output is not
#                        # byte-reproducible, so install what you tested.
#
# The NVRAM boot entry is not created here (see docs/01-base-install.md).
# Only \EFI\grub-fallback\grubx64.efi is written on the ESP.
#
# Why it is built this way:
#  * One self-contained binary (grub-mkstandalone): modules, grub.cfg, fonts and
#    theme are in memdisk. kern/verifiers.c exempts memdisk files from the
#    verifiers, so fonts and theme load under Secure Boot lockdown.
#  * No --sbat: SBAT is only checked by shim, and there is no shim in this chain.
#  * --disable-shim-lock: no shim; the firmware's LoadImage() checks signatures.
#  * The tpm module is REQUIRED: under lockdown, chainloaded images are marked
#    DEFER_AUTH; without shim_lock the only verifier that claims the file is the
#    tpm verifier (it measures into PCR 9). With TPM disabled in firmware the
#    chainloader fails with "verification requested but nobody cares".
#  * --disable-cli: the tpm verifier also accepts unsigned modules from disk, so an
#    open command line would let someone `insmod` arbitrary code without changing
#    PCR 7 -- and the LUKS TPM policy is bound to PCR 7 only. With the CLI disabled,
#    all menu entries must be --unrestricted.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/build"
ESP_DIR="/boot/EFI/grub-fallback"
ESP_TARGET="$ESP_DIR/grubx64.efi"
FONT_DIR="/usr/share/fonts/TTF"   # ttf-jetbrains-mono

# Built-in (preloaded) modules -- no insmod needed.
MODULES="normal part_gpt fat search search_fs_uuid chain efifwsetup reboot halt \
test echo sleep terminal font gfxterm gfxmenu png video video_fb efi_gop all_video tpm"

build() {
  grep -q '<ESP-UUID>' "$HERE/grub.cfg" && {
    echo "Replace <ESP-UUID> in grub.cfg first (blkid -s UUID -o value /dev/nvme0n1p1)." >&2; exit 1; }
  rm -rf "$BUILD"
  mkdir -p "$BUILD/memdisk/fonts" "$BUILD/memdisk/themes/black"

  # Only the glyph ranges that are needed: ASCII, Latin-1 + Latin Extended-A,
  # general punctuation, arrows, box drawing (text-mode frame), geometric shapes.
  local RANGE="0x20-0x7E,0xA0-0x17F,0x2010-0x2027,0x2190-0x2195,0x2500-0x257F,0x25A0-0x25CF"
  grub-mkfont -s 32 -r "$RANGE" -o "$BUILD/memdisk/fonts/jbm-regular-32.pf2" "$FONT_DIR/JetBrainsMono-Regular.ttf"
  grub-mkfont -s 32 -r "$RANGE" -o "$BUILD/memdisk/fonts/jbm-bold-32.pf2"    "$FONT_DIR/JetBrainsMono-Bold.ttf"
  grub-mkfont -s 24 -r "$RANGE" -o "$BUILD/memdisk/fonts/jbm-regular-24.pf2" "$FONT_DIR/JetBrainsMono-Regular.ttf"

  # Theme pixmaps (PNG24 -- GRUB's PNG reader does not support palette PNGs).
  # Inactive item: #1C1C1C background, 28 px side padding in the same colour.
  # Selected item: pure black background, 6 px white bar on the left.
  local T="$BUILD/memdisk/themes/black"
  cp "$HERE/theme/theme.txt" "$T/theme.txt"
  magick -size 1x1  xc:'#1C1C1C' "PNG24:$T/item_c.png"
  magick -size 28x1 xc:'#1C1C1C' "PNG24:$T/item_w.png"
  magick -size 28x1 xc:'#1C1C1C' "PNG24:$T/item_e.png"
  magick -size 1x1  xc:'#000000' "PNG24:$T/select_c.png"
  magick -size 28x1 xc:'#000000' -fill '#FFFFFF' -draw 'rectangle 0,0 5,0' "PNG24:$T/select_w.png"
  magick -size 28x1 xc:'#000000' "PNG24:$T/select_e.png"

  grub-script-check "$HERE/grub.cfg"

  local ARGS=() f
  ARGS+=("boot/grub/grub.cfg=$HERE/grub.cfg")
  for f in "$BUILD"/memdisk/fonts/*.pf2; do ARGS+=("boot/grub/fonts/$(basename "$f")=$f"); done
  for f in "$T"/*; do ARGS+=("boot/grub/themes/black/$(basename "$f")=$f"); done

  grub-mkstandalone \
    --format=x86_64-efi \
    --disable-shim-lock \
    --disable-cli \
    --modules="$MODULES" \
    --install-modules="$MODULES" \
    --fonts="" --themes="" --locales="" \
    --compress=xz \
    --output="$BUILD/grubx64.efi" \
    "${ARGS[@]}"

  echo "built: $BUILD/grubx64.efi ($(stat -c %s "$BUILD/grubx64.efi") bytes)"
}

sign() {
  sudo sbctl sign -o "$BUILD/grubx64.signed.efi" "$BUILD/grubx64.efi"
  sudo chown "$(id -u):$(id -g)" "$BUILD/grubx64.signed.efi"
}

install_esp() {
  [ -f "$BUILD/grubx64.efi" ] || { echo "run '$0 sign' (and test) first" >&2; exit 1; }
  local free
  free=$(df --output=avail -B1 /boot | tail -1)
  if [ "$free" -lt $((20 * 1024 * 1024)) ]; then
    echo "Less than 20 MB free on the ESP ($free bytes) -- aborting." >&2
    exit 1
  fi
  sudo install -d -m 0700 "$ESP_DIR"
  # Copy the UNSIGNED (tested) binary and sign it in place: sbctl silently skips
  # adding an already-signed file to its database ("already signed").
  sudo install -m 0700 "$BUILD/grubx64.efi" "$ESP_TARGET"
  sudo sbctl sign -s "$ESP_TARGET"
  sudo sbctl verify 2>&1 | grep -F "$ESP_TARGET" || true
  echo "installed: $ESP_TARGET"
}

case "${1:-build}" in
  build)   build ;;
  sign)    build; sign ;;
  install) install_esp ;;
  *) echo "usage: $0 {build|sign|install}" >&2; exit 2 ;;
esac
