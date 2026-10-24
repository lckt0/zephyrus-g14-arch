# 02 - Desktop

KDE Plasma 6 on Wayland, SDDM, PipeWire, Bluetooth, fonts, the NVIDIA driver stack,
system services, snapshots and package management. Continues from
[01-base-install.md](01-base-install.md) (booted system, CachyOS v4 repos enabled,
logged in as your user).

G14-specific power and hardware tuning (GPU switching behaviour, audio quirk, EDID/HDR,
panel, sleep) is in the [docs/03](03-g14-hardware-and-power.md) guide; custom packages (kernel, Plymouth, KWin
patches) are in [04-custom-packages.md](04-custom-packages.md); user-level configs
(Plasma, shell, apps) are in [05-dotfiles-and-desktop.md](05-dotfiles-and-desktop.md).

## Contents

1. [pacman configuration and package cache](#1-pacman-configuration-and-package-cache)
2. [AUR helper (yay)](#2-aur-helper-yay)
3. [KDE Plasma 6 and SDDM](#3-kde-plasma-6-and-sddm)
4. [Audio: PipeWire](#4-audio-pipewire)
5. [Bluetooth](#5-bluetooth)
6. [Fonts](#6-fonts)
7. [NVIDIA dGPU driver stack](#7-nvidia-dgpu-driver-stack)
8. [ASUS tools and power profiles](#8-asus-tools-and-power-profiles)
9. [Firewall, printing, other services](#9-firewall-printing-other-services)
10. [Enabled system units](#10-enabled-system-units)
11. [Snapshots: snapper + snap-pac](#11-snapshots-snapper--snap-pac)
12. [Update notifier](#12-update-notifier)
13. [Face login (optional)](#13-face-login-optional)
14. [The rest of the packages](#14-the-rest-of-the-packages)

---

## 1. pacman configuration and package cache

**What:** [`system/etc/pacman.conf`](../system/etc/pacman.conf). Besides the CachyOS
repo blocks (01, section 10) the options that differ from a stock install are:

```ini
Architecture = auto        # CachyOS pacman: resolves to x86_64 + x86_64_v2/v3/v4
Color                      # coloured output
CheckSpace                 # refuse a transaction that would not fit
ParallelDownloads = 5      # download five packages at once
DownloadUser = alpm        # downloads run unprivileged (pacman 7 default)
```

plus `[multilib]` enabled for 32-bit libraries (Wine, Steam, games).

**Mirrors:** `/etc/pacman.d/mirrorlist` holds a few close mirrors for the Arch repos;
the CachyOS mirrorlists come from the `cachyos-*mirrorlist` packages. To generate your
own Arch list: `reflector --country <CC> --protocol https --sort rate --save
/etc/pacman.d/mirrorlist` (`reflector` is a separate package).

**Package cache cleanup:** `paccache.timer` (from `pacman-contrib`) runs weekly and
keeps the last three versions of each package (`PACCACHE_ARGS=` is empty in
`/etc/conf.d/pacman-contrib`, so `paccache -r` uses its default `-k3`). The cache lives
on its own subvolume (`@pkg`) so it is not included in snapshots.

```sh
pacman -S --needed pacman-contrib
systemctl enable --now paccache.timer
```

**Verify:** `systemctl list-timers paccache.timer`; `paccache -dv` shows what would be
removed.

## 2. AUR helper (yay)

With the CachyOS repos enabled, `yay` is a regular package:

```sh
pacman -S --needed yay
```

Without them, bootstrap it from the AUR once:

```sh
pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
cd /tmp/yay-bin && makepkg -si
```

Never run `makepkg` or `yay` as root.

## 3. KDE Plasma 6 and SDDM

**What:** `plasma-meta` (the full Plasma 6.8 desktop: KWin, Plasma Workspace,
System Settings, PowerDevil, KScreen, Discover, xdg-desktop-portal-kde, bluedevil,
plasma-nm, plasma-pa, Spectacle, ...) plus the core KDE apps, and SDDM as the display
manager with its greeter running on Wayland.

```sh
pacman -S --needed plasma-meta sddm sddm-kcm \
  konsole dolphin kate ark gwenview kio-admin kwalletmanager partitionmanager \
  kdeconnect xdg-utils wl-clipboard
systemctl enable sddm
```

`plasma-meta` 6.8 also pulls in `plasma-login-manager` (its `plasmalogin.service`). It
is installed but **not enabled**; SDDM is the display manager here. Enable only one of
the two.

**SDDM on Wayland.** By default the SDDM greeter starts an X server. On the reference
machine `/etc/sddm.conf` runs it on `kwin_wayland` instead, so no X server is started
at all and the greeter behaves the same as the session (same scaling, HDR-capable
output configuration). Shipped as a drop-in,
[`system/etc/sddm.conf.d/10-wayland.conf`](../system/etc/sddm.conf.d/10-wayland.conf):

```ini
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
```

```sh
install -Dm644 system/etc/sddm.conf.d/10-wayland.conf /etc/sddm.conf.d/10-wayland.conf
```

The SDDM theme itself is set in `/etc/sddm.conf.d/kde_settings.conf`, written by the
SDDM page in System Settings (`sddm-kcm`); the custom theme used on the reference
machine is covered with the user configuration in [05-dotfiles-and-desktop.md](05-dotfiles-and-desktop.md). Use Breeze until then.

Pick "Plasma (Wayland)" at the greeter. Reboot (or `systemctl start sddm`).

**Verify:** `echo $XDG_SESSION_TYPE` in Konsole prints `wayland`;
`loginctl show-session $XDG_SESSION_ID -p Type` prints `Type=wayland`.

**Revert:** remove the drop-in (greeter goes back to X11);
`systemctl disable sddm` to boot to a text console.

## 4. Audio: PipeWire

**What:** PipeWire as the audio server with WirePlumber as session manager, and its
PulseAudio, ALSA and JACK compatibility layers.

```sh
pacman -S --needed pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-jack \
  gst-plugin-pipewire rtkit alsa-utils sof-firmware pavucontrol qpwgraph easyeffects lsp-plugins
```

| Package | Why |
|---|---|
| `pipewire-pulse` | PulseAudio clients (browsers, most apps) |
| `pipewire-alsa`, `pipewire-jack` | ALSA-only and JACK apps go through PipeWire |
| `rtkit` | lets PipeWire get realtime scheduling without root |
| `easyeffects`, `lsp-plugins` | speaker EQ/limiter for the laptop speakers |
| `pavucontrol`, `qpwgraph` | per-stream volume and routing graph |

No system service is needed: `pipewire.socket`, `pipewire-pulse.socket` and
`wireplumber.service` are **user** units, enabled by the packages' presets.

**[GA403GM]** The internal speakers need an ALC285 codec fixup and a volume cap; that is
in [docs/03](03-g14-hardware-and-power.md) (it adds `/etc/modprobe.d/60-alc285-g14-quirk.conf` and the
`alsa-card-volume-cap.service` listed in section 10).

**Verify:** `wpctl status` lists the sinks; `pactl info | grep 'Server Name'` shows
`PulseAudio (on PipeWire ...)`.

## 5. Bluetooth

```sh
pacman -S --needed bluez bluez-utils
systemctl enable --now bluetooth
```

The Plasma applet (`bluedevil`) comes with `plasma-meta`. `/etc/bluetooth/main.conf` is
left at its defaults. The AX210's Bluetooth USB autosuspend is turned off by a modprobe
option described in [docs/03](03-g14-hardware-and-power.md).

**Verify:** `bluetoothctl show` prints `Powered: yes`.

## 6. Fonts

```sh
pacman -S --needed noto-fonts noto-fonts-cjk noto-fonts-emoji \
  ttf-dejavu ttf-liberation ttf-jetbrains-mono ttc-iosevka-ss14 gsfonts
yay -S --needed otf-apple-sf-pro otf-apple-sf-mono      # optional, AUR
```

| Font | Role |
|---|---|
| Noto (+ CJK, emoji) | fallback coverage for every script and emoji |
| DejaVu, Liberation | metric-compatible replacements for common document fonts |
| JetBrains Mono | system UI font on the reference machine (also used by the fallback GRUB menu) |
| Iosevka SS14 | terminal font |
| gsfonts | Ghostscript/PDF base fonts |

The UI font itself is chosen in System Settings -> Text & Fonts (see [05-dotfiles-and-desktop.md](05-dotfiles-and-desktop.md)).

## 7. NVIDIA dGPU driver stack

**What is installed** on the reference machine (RTX 5060 Laptop, Blackwell, GB206):

| Package | Version | Why |
|---|---|---|
| `nvidia-open-dkms` | 615.78.08 | Open kernel modules. **Blackwell (RTX 50) GPUs are only supported by the open modules**, not by the old proprietary `nvidia` modules. DKMS so the module is rebuilt for every installed kernel, including the custom one. |
| `nvidia-utils`, `lib32-nvidia-utils` | 615.78.08 | userspace driver (GL, Vulkan, EGL), 32-bit for games |
| `opencl-nvidia` | | OpenCL on the dGPU |
| `nvidia-settings` | | GUI/CLI settings tool |
| `nvidia-prime` | | `prime-run <app>` to run one program on the dGPU |
| `egl-wayland`, `egl-wayland2`, `egl-gbm`, `egl-x11` | | EGL platform glue for Wayland/Xwayland (pulled in by `nvidia-utils`) |
| `supergfxctl` (AUR) | 5.2.7 | GPU mode switching (Integrated / Hybrid); the reference machine runs in **Integrated** mode by default, which keeps the dGPU powered off |
| `nvidia-laptop-power-cfg` | | custom package with the NVIDIA module options (runtime D3 power management, S0ix, VRAM preservation across suspend) - see [04-custom-packages.md](04-custom-packages.md) |

AMD side: `mesa`, `vulkan-radeon`, `lib32-vulkan-radeon` (iGPU, drives the panel).
`linux-headers` (and the custom kernel's headers) must be installed for DKMS.

```sh
pacman -S --needed nvidia-open-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia \
  nvidia-settings nvidia-prime mesa vulkan-radeon lib32-vulkan-radeon linux-headers
yay -S supergfxctl
systemctl enable nvidia-suspend nvidia-resume nvidia-hibernate supergfxd
```

**Why the suspend services:** with `NVreg_PreserveVideoMemoryAllocations=1` (set by
the module options) the driver saves VRAM to disk on suspend through these units;
without them resume from sleep was not clean on this machine.

`nvidia-powerd.service` is also enabled (Dynamic Boost: shifts power between CPU and
dGPU when the dGPU is in use). How it interacts with Integrated mode and ASUS's
battery settings is in [docs/03](03-g14-hardware-and-power.md); read that before enabling it.

Not in the initramfs: the NVIDIA modules load from the root filesystem; early KMS and
the boot splash use amdgpu (01, section 13). `nouveau` is blacklisted.

**Verify:** `supergfxctl -g` prints the current mode; in Hybrid mode
`prime-run glxinfo -B | grep 'OpenGL renderer'` shows the GeForce GPU;
`dkms status` lists `nvidia/615.78.08` for every installed kernel.

**Revert:** `pacman -Rns nvidia-open-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia
nvidia-settings nvidia-prime` and disable the four services; the iGPU keeps working.

## 8. ASUS tools and power profiles

```sh
pacman -S --needed asusctl rog-control-center power-profiles-daemon
systemctl enable power-profiles-daemon
```

- `asusctl` / `asusd`: keyboard backlight, charge limit, fan curves, firmware
  attributes. `asusd` is D-Bus activated, so it does not show up as an enabled unit.
- `rog-control-center`: GUI for asusd.
- `power-profiles-daemon`: the power profiles Plasma's battery applet switches between.
  TLP is **not** used (it conflicts with power-profiles-daemon).

Settings (charge limit, profiles, etc.) are in [docs/03](03-g14-hardware-and-power.md).

## 9. Firewall, printing, other services

**Firewall (ufw):** deny incoming, allow outgoing, logging off. Open only what LAN
features need:

```sh
pacman -S --needed ufw
ufw default deny incoming
ufw default allow outgoing
ufw logging off
ufw allow 1714:1764/udp        # KDE Connect
ufw allow 1714:1764/tcp        # KDE Connect
ufw allow from 192.168.0.0/16 to any port 53317 comment 'LocalSend'      # adjust to your LAN
ufw allow from 192.168.0.0/16 to any port 53318 proto tcp comment 'QuickShare'
ufw enable
systemctl enable ufw
```

Plasma's firewall page (`plasma-firewall`, part of `plasma-meta`) edits the same rules.

**Printing:** `cups`, `cups-pk-helper`, `system-config-printer` (Plasma's printer page
is `print-manager`). `cups.socket`/`cups.path` start CUPS on demand.

```sh
pacman -S --needed cups cups-pk-helper system-config-printer ghostscript
systemctl enable cups.socket cups.path
```

**SSD TRIM:** `systemctl enable fstrim.timer` (weekly, covers `/` through LUKS
discards and the ESP).

## 10. Enabled system units

`systemctl list-unit-files --state=enabled` on the reference machine, with the reason
for each:

| Unit | Reason |
|---|---|
| `NetworkManager.service` | network management (01, section 11) |
| `NetworkManager-dispatcher.service` | runs NetworkManager hook scripts; enabled together with NetworkManager |
| `systemd-resolved.service` (+ `-monitor`/`-varlink` sockets) | DNS resolver, DNS over TLS |
| `systemd-timesyncd.service` | NTP time sync |
| `sddm.service` | display manager |
| `bluetooth.service` | Bluetooth stack |
| `power-profiles-daemon.service` | power profiles for Plasma |
| `supergfxd.service` | GPU mode switching (Integrated by default) |
| `nvidia-suspend.service`, `nvidia-resume.service`, `nvidia-hibernate.service` | save/restore VRAM around sleep (section 7) |
| `nvidia-powerd.service` | NVIDIA Dynamic Boost (section 7, read [docs/03](03-g14-hardware-and-power.md)) |
| `alsa-card-volume-cap.service` | **[GA403GM]** caps the speaker amplifier volume; local unit from [docs/03](03-g14-hardware-and-power.md) |
| `ufw.service` | firewall rules at boot |
| `cups.socket`, `cups.path`, `cups.service` | printing, socket-activated |
| `proton.VPN.service` | Proton VPN daemon (from `proton-vpn-gtk-app`), optional |
| `fstrim.timer` | weekly TRIM |
| `paccache.timer` | weekly package cache cleanup |
| `snapper-timeline.timer`, `snapper-cleanup.timer` | hourly snapshots and their cleanup (section 11) |
| `getty@.service`, `remote-fs.target`, `systemd-userdbd.socket` | systemd defaults |

Masked:

| Unit | Reason |
|---|---|
| `systemd-boot-update.service` | no systemd-boot installed (01, section 15) |
| `hibernate.target`, `systemd-hibernate.service`, `suspend-then-hibernate.target`, `systemd-suspend-then-hibernate.service` | hibernation does not resume reliably on this machine; s2idle is used instead ([docs/03](03-g14-hardware-and-power.md)) |
| `systemd-backlight@backlight:nvidia_0.service` | the panel is on the iGPU; this unit only saved/restored a stale `nvidia_0` backlight device and woke the dGPU early in boot |

## 11. Snapshots: snapper + snap-pac

**What:** snapper configs for `/` and `/home`, hourly timeline snapshots, and a
pre/post snapshot pair of `/` around every pacman transaction (`snap-pac`).
`btrfs-assistant` is the GUI for browsing and restoring.

**Why:** an update that breaks the system can be undone from a snapshot, and the
timeline covers accidental deletions in `/home`.

```sh
pacman -S --needed snapper snap-pac btrfs-assistant
snapper -c root create-config /
snapper -c home create-config /home
systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
```

`create-config` creates `.snapshots` as a nested subvolume inside `@` and `@home`. The
other subvolumes (`@pkg`, `@log`, `@swap`) are separate top-level subvolumes, so they
are never part of a snapshot.

Both configs use snapper's defaults except as shown in
[`system/etc/snapper/configs/root`](../system/etc/snapper/configs/root) and
[`home`](../system/etc/snapper/configs/home):

```
NUMBER_LIMIT="50"            # pre/post pairs kept (about 25 pacman transactions)
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="yes"
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="10"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="10"
TIMELINE_LIMIT_YEARLY="10"
SPACE_LIMIT="0.5"            # snapshots may use at most 50% of the filesystem
FREE_LIMIT="0.2"             # cleanup keeps at least 20% free
```

`snap-pac` has no config file here (`/etc/snap-pac.ini` absent), so it uses the `root`
config only.

**Known limits:**

- The ESP (`/boot`, with the UKIs) is **not** in any snapshot. If you restore a root
  snapshot from before a kernel update, `/usr/lib/modules` goes back but the UKI does
  not. Reinstall the kernel package afterwards (`pacman -S linux` or the custom kernel)
  to rebuild a matching UKI.
- `fstab` and the kernel command line mount `subvol=@` by name, so
  `snapper rollback` (which changes the default subvolume) has no effect. Restore with
  btrfs-assistant's "Restore" instead, which replaces `@` with the snapshot.

**Practice on the reference machine:** before a large system change (kernel swap,
boot-chain change, removing packages), take a manual snapshot, reboot, check, then
delete that snapshot:

```sh
snapper -c root create --description "before <change>" --cleanup-algorithm number
# reboot and verify, then:
snapper -c root delete <number>
```

**Verify:** `snapper -c root list` shows `pre`/`post` pairs after a `pacman -S`.

## 12. Update notifier

`cachy-update` (CachyOS repo; the binary is `arch-update`) checks for repo, AUR and
Flatpak updates once a day, shows a tray icon only when updates exist, and opens the
update in a terminal with pre/post checks (pacnew files, services to restart, news).

```sh
pacman -S --needed cachy-update
systemctl --user enable --now arch-update.timer
```

Its config (`~/.config/arch-update/arch-update.conf`) and the terminal used are part
of the user configuration ([05-dotfiles-and-desktop.md](05-dotfiles-and-desktop.md)).

## 13. Face login (optional)

The reference machine uses the laptop's IR camera for authentication with
`howdy-next` (AUR). The `pam_howdy.so` line is placed before the normal stack in three
PAM files, so a recognised face is enough and anything else falls through to the
password:

| PAM file | Used by |
|---|---|
| [`system/etc/pam.d/sddm`](../system/etc/pam.d/sddm) | SDDM login |
| [`system/etc/pam.d/kde`](../system/etc/pam.d/kde) | Plasma lock screen |
| [`system/etc/pam.d/polkit-1`](../system/etc/pam.d/polkit-1) | polkit prompts (GUI admin actions) |

```
auth        sufficient  /usr/lib/security/pam_howdy.so
auth        include     system-login
```

It is not used for `sudo`. Trade-off: face recognition is weaker than a password, and
with it in `polkit-1` a face is enough to approve admin actions in the GUI; leave that
file alone if you do not want that. Set up with `yay -S howdy-next`, then follow its
documentation to select the IR camera and add a face model. Revert by removing the
`pam_howdy.so` lines.

## 14. The rest of the packages

Everything else that is installed (browsers, editors, development tools,
virtualisation, games tooling, alternative compositors) is listed in
[`packages/`](../packages); see [`packages/README.md`](../packages/README.md) for how
to install from the lists.
