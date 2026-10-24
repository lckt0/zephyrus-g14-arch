# Package lists

Explicitly installed packages of the reference system, generated with:

```sh
pacman -Qqen > pkglist-native.txt     # from the configured repos (CachyOS + Arch)
pacman -Qqem > pkglist-foreign.txt    # from the AUR
```

A handful of personal and unrelated packages were removed before publishing. Treat the
lists as "what this laptop has", not as a recommendation: read them and delete what you
do not need before installing.

## Installing from the lists

Requires the CachyOS repositories (see `docs/01-base-install.md`, section 10) and
`multilib`. Some entries only exist in the CachyOS repos: `cachyos-keyring`,
`cachyos-*mirrorlist`, `cachy-update`, `yay`, `brave-origin-bin`, `helium-browser-bin`,
`etcher-bin`, `ventoy-bin`, `faugus-launcher`, `freetube`, `r-quick-share`. Without
CachyOS repos, drop them or take the AUR versions.

```sh
# repo packages
sudo pacman -S --needed - < pkglist-native.txt

# AUR packages (yay must already be installed)
yay -S --needed - < pkglist-foreign.txt
```

`--needed` skips what is already installed, so both commands are safe to re-run.
Packages that no longer exist make pacman abort; remove those lines and retry.

## Not in the lists: custom packages

These are installed on the reference system but are built locally from the PKGBUILDs
in this directory, so they are left out of `pkglist-foreign.txt` (yay cannot find them
in the AUR). See `docs/04-custom-packages.md`.

| Package | What it is |
|---|---|
| `linux-lapidary`, `linux-lapidary-headers` | CachyOS-based kernel with G14 display patches; booted as the default UKI |
| `plymouth-lapidary` | patched Plymouth build used by the boot splash |
| `nvidia-laptop-power-cfg` | NVIDIA module options for runtime power management and suspend |
| `plasma-applet-lckt0-volume` | local Plasma audio applet (multi-output, per-popup volume meters) |

`kwin` in `pkglist-native.txt` is the regular repo package; a patched KWin, if you use
one, is described in `docs/04-custom-packages.md`.

## Packages also referenced by the guides

| List entry | Covered in |
|---|---|
| `base`, `linux`, `linux-firmware`, `amd-ucode`, `btrfs-progs`, `sbctl`, `efibootmgr`, `mkinitcpio`, `zram-generator`, `grub` | `docs/01-base-install.md` |
| `plasma-meta`, `sddm-kcm`, `pipewire*`, `wireplumber`, `bluez*`, fonts, `nvidia-*`, `supergfxctl`, `asusctl`, `rog-control-center`, `power-profiles-daemon`, `snapper`, `snap-pac`, `btrfs-assistant`, `ufw`, `cups`, `howdy-next` | `docs/02-desktop.md` |
| `plymouth-theme-monoarch` | installed but not the active Plymouth theme; the active one is described in `docs/04-custom-packages.md` |
