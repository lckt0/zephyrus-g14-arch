# 05 - Dotfiles and desktop

This part covers everything that lives in your home directory: the shell, the
terminal, fonts, the KDE Plasma settings that matter, the launcher, a few user
services and small helper scripts. Nothing here needs root. System files
(kernel, udev rules, power daemons, `/usr/local/bin` helpers) are installed by
following [docs/03](03-g14-hardware-and-power.md).

Everything is under [`home/`](../home), with paths that mirror `$HOME`.
KDE settings are not shipped as whole rc files; KDE rc files are full of
machine IDs, window geometry and state, so only the meaningful non-default
keys are written by [`scripts/apply-kde-settings.sh`](../scripts/apply-kde-settings.sh).

Contents:

1. [Packages](#1-packages)
2. [Applying, verifying, reverting](#2-applying-verifying-reverting)
3. [Shell: fish](#3-shell-fish)
4. [Terminal: Konsole](#4-terminal-konsole)
5. [Editor: micro](#5-editor-micro)
6. [Fonts](#6-fonts)
7. [Theme: the Iris family](#7-theme-the-iris-family)
8. [KWin: effects off, behaviour scripts on](#8-kwin-effects-off-behaviour-scripts-on)
9. [Launcher: rofi](#9-launcher-rofi)
10. [Global shortcuts](#10-global-shortcuts)
11. [Power-related user settings](#11-power-related-user-settings)
12. [G14 hardware helpers](#12-g14-hardware-helpers)
13. [Notifications](#13-notifications)
14. [Update notifier](#14-update-notifier)
15. [File indexing](#15-file-indexing)
16. [Other small settings](#16-other-small-settings)
17. [What is deliberately not included](#17-what-is-deliberately-not-included)

---

## 1. Packages

```sh
sudo pacman -S --needed fish konsole micro fastfetch rofi mpv yt-dlp \
    ttf-jetbrains-mono ttf-jetbrains-mono-nerd papirus-icon-theme \
    alsa-utils libpulse kde-gtk-config spectacle
# AUR (Qt style + window decoration used by the Iris theme):
yay -S klassy
```

`asusctl` and `supergfxctl` come from the hardware part ([docs/03](03-g14-hardware-and-power.md)).
`cachy-update` (section 14) is optional.

## 2. Applying, verifying, reverting

**What.** Two scripts:

| Script | Does |
| --- | --- |
| `scripts/apply-dotfiles.sh` | Copies (or with `--link`, symlinks) every file under `home/` into `$HOME`. |
| `scripts/apply-kde-settings.sh` | Writes the KDE keys listed in this document with `kwriteconfig6`. |

Neither script writes outside `$HOME` or uses sudo.

**How.**

```sh
git clone https://github.com/lckt0/zephyrus-g14-arch.git
cd zephyrus-g14-arch

scripts/apply-dotfiles.sh --dry-run      # see what would change
scripts/apply-dotfiles.sh                # copy (use --link to symlink instead)

systemctl --user daemon-reload
systemctl --user enable --now alc285-port-watch.service   # G14 speaker fix, section 12
systemctl --user enable --now stuck-watch.timer           # optional, see docs/03
kbuildsycoca6                                             # register the .desktop files

# If you use the Iris theme, run its installer first (section 7), then:
scripts/apply-kde-settings.sh --dry-run
scripts/apply-kde-settings.sh --shortcuts
```

Log out and back in afterwards. `environment.d` files, the KWin window title
font and global shortcuts are only read at login.

`--shortcuts` writes `kglobalshortcutsrc`. kglobalaccel keeps shortcuts in
memory and may write its own copy back, so log out right after running it. If
a shortcut does not stick, set it in System Settings > Keyboard > Shortcuts
(section 10 lists them).

**Verify.**

```sh
scripts/apply-dotfiles.sh --dry-run     # prints "Nothing to do" when everything is in place
systemctl --user status alc285-port-watch.service
kreadconfig6 --file kwinrc --group Plugins --key blurEnabled   # false
```

**Revert.**

- Dotfiles: every run that changes something saves the replaced files and a
  `MANIFEST` under `~/.local/state/g14-dotfiles/backup-<timestamp>/`.
  `scripts/apply-dotfiles.sh --restore ~/.local/state/g14-dotfiles/backup-<timestamp>`
  puts the old files back and removes the files that run created.
- KDE settings: the rc files are copied to
  `~/.local/state/g14-dotfiles/kde-backup-<timestamp>/` before the first
  write. Copy them back into `~/.config/` and log out/in.
- User units: `systemctl --user disable --now alc285-port-watch.service`.

## 3. Shell: fish

Files: `home/.config/fish/`.

| File | Purpose |
| --- | --- |
| `config.fish` | `EDITOR=micro`, default (emacs-style) key bindings, aliases `c` = clear, `ff` = fastfetch. |
| `conf.d/interactive.fish` | No greeting; run fastfetch when an interactive shell starts and after `clear`; Ctrl+Backspace deletes a word. |
| `functions/pacman.fish`, `yay.fish`, `sudo.fish`, `__pkg_noconfirm_needed.fish` | Package wrappers, below. |
| `functions/fish_mode_prompt.fish` | Hides the vi-mode indicator. |

### pacman / yay default answers

**What.** In an interactive fish shell, `pacman`, `yay` and `sudo pacman`
get `--noconfirm` added automatically for operations that change something
(`-S`, `-R`, `-U`, `-D` and their long forms). A bare `yay` runs
`yay -Syu --noconfirm`.

**Why.** Almost every pacman/yay question is answered with the default anyway.
Accepting defaults automatically saves a keypress per prompt without changing
what gets chosen.

Rules, all in `__pkg_noconfirm_needed.fish`:

- only in an interactive shell; scripts (bash, makepkg, fish scripts, update
  tools) are never affected;
- pass `--confirm` to get the questions back for one command
  (`sudo pacman -Rns foo --confirm`);
- if you already passed `--noconfirm`/`--confirm`, nothing is changed;
- queries (`-Q`, `-Si`, `-Ss` ...) and `yay <term>` (the numbered search menu) are untouched;
- `sudo` is only rewritten when its first argument is exactly `pacman`.

yay's own menus are also off: in `~/.config/yay/config.json`,
`answerclean`, `answerdiff` and `answeredit` are `None` (set once with
`yay --answerclean None --answerdiff None --answeredit None --save`).

**Verify.** `type pacman` shows the wrapper. `pacman -S foo --confirm` asks again.

**Revert.** Delete the four function files and open a new shell.

### Prompt

The prompt is [Tide](https://github.com/IlanCosman/tide) v6 (Classic style,
two lines with frame, 12-hour time on the right, transient prompt). Tide is
not copied here; install it with [fisher](https://github.com/jorgebucaran/fisher):

```fish
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
fisher install jorgebucaran/fisher ilancosman/tide@v6
tide configure --auto --style=Classic --prompt_colors='True color' \
    --classic_prompt_color=Light --show_time='12-hour format' \
    --classic_prompt_separators=Angled --powerline_prompt_heads=Sharp \
    --powerline_prompt_tails=Round --powerline_prompt_style='Two lines, frame' \
    --prompt_connection=Solid --powerline_right_prompt_frame=Yes \
    --prompt_connection_andor_frame_color=Dark --prompt_spacing=Compact \
    --icons='Many icons' --transient=Yes
```

Or run `tide configure` and pick interactively.

### fastfetch

`home/.config/fastfetch/config.jsonc`: a grouped layout (user/OS, hardware,
OS age and uptime). Needs a Nerd Font in the terminal for the icons. OS age is
the birth time of `/`.

## 4. Terminal: Konsole

**What.** Konsole is the terminal (ghostty is not used). Profile
`home/.local/share/konsole/G14.profile`: JetBrainsMono Nerd Font 10, the
built-in "Linux" colour scheme, fish as the shell, no menu bar, no dimming of
inactive splits, scrollbar hidden, 115x32 initial size.
`apply-kde-settings.sh` makes it the default profile (`konsolerc`).

**Why.** Konsole is part of Plasma (same shortcuts, colour schemes and KIO
as the rest of the desktop, and the same engine as Dolphin's terminal panel),
so there is one less thing to theme and configure separately.

**Verify.** Konsole > Settings > Manage Profiles shows "G14" as default.
**Revert.** Pick another default profile there, or delete the profile file.

## 5. Editor: micro

[micro](https://micro-editor.github.io/) with its defaults; there is no
`settings.json` to ship. `EDITOR=micro` is set in `config.fish`, so git and
other tools that honour `EDITOR` open it from fish.

## 6. Fonts

**What.** JetBrains Mono 10 for the entire Plasma UI (general, fixed, menu,
toolbar, window titles; 8 pt for the smallest readable size). The terminal is
the exception: Konsole uses JetBrainsMono Nerd Font 10, the same design with
the extra icon glyphs. rofi uses JetBrains Mono 11.

**Why.** A monospaced UI font keeps columns and numbers aligned everywhere.
Iosevka (SS14) was tried first, but at 0.5 em per character it was too tight
to read comfortably in menus and dialogs; JetBrains Mono's 0.6 em width reads
like a normal UI font. Narrow monospace families (Iosevka, Ubuntu Mono, M+)
all have the same problem.

**How.** `scripts/apply-kde-settings.sh` writes the `kdeglobals` keys `font`,
`fixed`, `menuFont`, `toolBarFont`, `smallestReadableFont`, `[WM] activeFont`,
plus slight hinting with RGB subpixel rendering.

GTK apps follow automatically: Plasma's GTK settings module (`kde-gtk-config`)
regenerates `~/.config/gtk-3.0/settings.ini`, `gtk-4.0/settings.ini`,
`~/.gtkrc-2.0` and `xsettingsd.conf` from `kdeglobals`, so those files are not
shipped.

**Verify.** System Settings > Text & Fonts. Window title bars only switch
after logging out and in; `qdbus6 org.kde.KWin /KWin reconfigure` does not
reload the decoration font.

**Revert.** System Settings > Text & Fonts > Defaults, or restore the
`kdeglobals` backup.

## 7. Theme: the Iris family

The look comes from separate projects, each with its own installer and
uninstaller. They are not copied into this repository.

| Project | What it is |
| --- | --- |
| [iris-desktop](https://github.com/lckt0/iris-desktop) | Pitch-black Plasma 6 theme: colour scheme, Plasma style, Klassy decoration config, panel widgets (task manager, clock, battery, power), rofi theme, look-and-feel package, wallpaper. |
| [iris-greeter](https://github.com/lckt0/iris-greeter) | Matching SDDM login screen, lock screen and splash. |
| [iris-volume](https://github.com/lckt0/iris-volume) | Fork of the Plasma volume applet that can play on several outputs at once. |
| [onyx-greeter](https://github.com/lckt0/onyx-greeter) | Alternative true-black SDDM + lock screen. |
| [gnomish-greeter](https://github.com/lckt0/gnomish-greeter) | Alternative GNOME-style SDDM + lock screen. |

Order: install iris-desktop (and a greeter) first, then run
`scripts/apply-kde-settings.sh`. The iris-desktop installer enables blur,
fade and scale effects; this repository's script turns them off again
(section 8).

iris-greeter activates its lock screen with a user drop-in,
`~/.config/systemd/user/plasma-kwin_wayland.service.d/iris.conf`
(`PLASMA_DEFAULT_SHELL=iris`). It is installed and removed by iris-greeter,
so it is not part of `home/`.

### Colour conventions

- Everything sits on pure black (`#000000`), which on the OLED panel means
  pixels that are off. Raised surfaces use neutral greys only (14 / 20 / 28),
  never bluish greys.
- Active vs. inactive: the active item is black and the inactive item's
  **background** turns `#1C1C1C` (28,28,28); the text is not dimmed. This is
  the rule used for browser tabs. The alternative colour scheme
  `home/.local/share/color-schemes/BreezeTrueBlack.colors` (Breeze Dark on
  pure black, neutral greys) applies it to inactive title bars too; select it
  in System Settings > Colours if you do not use Iris.
- The Iris colour scheme as currently shipped keeps both active and inactive
  title bars black and greys the inactive title text instead. If you want the
  background rule for title bars as well, set
  `inactiveBackground=28,28,28` in the `[WM]` group of
  `~/.local/share/color-schemes/Iris.colors`.
- A KWin window rule ("Black title bar (Iris)", written by
  `apply-kde-settings.sh` only when Iris is installed) forces the Iris
  colour scheme onto every title bar, so applications that set their own
  colour scheme still get the black title bar.

### Panel and desktop

The panel layout file (`plasma-org.kde.plasma.desktop-appletsrc`) is not
shipped: it is full of containment IDs and screen-specific geometry and does
not transfer between machines. The layout is:

- one panel at the top, 30 px, not floating;
- left to right: a "show desktop" button (the "Mike Desktop" widget from the
  KDE Store), Iris task manager (minimised windows are not dimmed and stay in
  the bar), spacer, Iris clock, spacer, system tray, network, Bluetooth,
  iris-volume, Iris battery, Iris power and notifications, with
  [Advanced Separator](https://github.com/luisbocanegra/plasma-advanced-separator)
  widgets between the groups;
- the system tray keeps the stock Plasma indicators with the Papirus icon theme;
- the desktop is a folder view with the Iris fetch widget.

Rebuild it by hand: right-click the panel > Add Widgets.

## 8. KWin: effects off, behaviour scripts on

**What.** All purely visual KWin effects are disabled: blur, background
contrast, dim inactive, dim screen, fade, scale, slide, sliding popups and
notifications, maximize, fullscreen, squash, magic lamp, wobbly windows,
window aperture, translucency, login/logout/session-quit animations, frozen
app, dialog parent, blend changes, startup feedback, screen transform, system
bell, kscreen, shake cursor.

Kept at their defaults (on): effects that only run while you use them
(Overview, Window View, tiles editor, zoom, colour picker, screen edge, output
locator, highlight window).

Kept on explicitly, because they are behaviour scripts, not visual effects:

| Script | Source | Purpose |
| --- | --- | --- |
| `rofi-autoclose` | `home/.local/share/kwin/scripts/` | closes rofi when it loses focus (section 9) |
| `alt-f4-desktop` | KDE Store, "Alt-F4 Desktop" by micha4w | Alt+F4 on the desktop opens the logout dialog |
| `iris-popup-anchor` | iris-desktop | positions Iris panel popups |
| `desktopchangeosd` | stock | short text-only OSD on virtual desktop switch (500 ms) |
| `minimizeall` | stock | Meta+D minimises all windows |

**Why.** If any active effect reports that it blocks direct scanout, KWin
composites every frame itself and cannot hand fullscreen or windowed content
to a hardware overlay plane (MPO). Dim inactive was confirmed to do this
constantly. Losing the planes costs power on video and idle desktops, which
matters more on a laptop than the animations. See [docs/03](03-g14-hardware-and-power.md) for the overlay
plane setup this supports. If you turn an effect back on, check that overlay
planes still work.

Note: when switching effects off in bulk, name them one by one (as the script
does). Disabling everything with `Enabled=true` in `kwinrc` also kills the
behaviour scripts; Alt+F4 stops working on some windows, for example.

Other KWin keys written: Alt+Tab uses the thumbnail grid, no Overview hot
corner, middle-click paste (primary selection) off, 3 virtual desktops in one
row.

**Verify.**

```sh
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects   # empty when idle
```

**Revert.** System Settings > Window Management > Desktop Effects, or restore
the `kwinrc` backup.

## 9. Launcher: rofi

**What.** rofi (application launcher mode only) opened with the Meta key,
with a KRunner-like search: plain substring matching, space-separated tokens
in any order, case-insensitive. Terminal apps open in Konsole.

| File | Purpose |
| --- | --- |
| `.config/rofi/config.rasi` | rofi configuration; uses the Iris theme from iris-desktop (`@theme "themes/iris"`). Without iris-desktop, change it to a built-in theme, e.g. `@theme "Arc-Dark"`. |
| `.local/bin/rofi-toggle` | same shortcut opens and closes rofi; a different rofi shortcut switches mode (`drun`, `clipboard`, `power`). |
| `.local/bin/rofi-clipboard` | Klipper history in rofi; the pick goes back to the clipboard. |
| `.local/bin/rofi-power` | lock / sleep / log out / restart / shut down through KDE's session manager. |
| `.local/share/kwin/scripts/rofi-autoclose` | KWin script: when another window becomes active, starts `rofi-kill.service`. |
| `.config/systemd/user/rofi-kill.service` | `pkill -x rofi`. |
| `.local/share/applications/net.local.rofi-toggle.desktop` | target for the Meta shortcut. |

**Why the detour through a service.** rofi is started with `-normal-window`
so KWin treats it as a normal window and can tell when it loses focus. A KWin
script cannot run commands, only D-Bus calls, so it asks systemd to start a
oneshot unit that kills exactly the rofi process. Killing a cgroup or scope
instead would also kill the application rofi just launched, since it is
rofi's child in the same scope. rofi's window-switcher mode is not used: KWin
does not implement the `wlr-foreign-toplevel-management` protocol it needs.

The `.desktop` files call `rofi-toggle` by name. That works because
`~/.config/environment.d/10-user-paths.conf` puts `~/.local/bin` on the
session `PATH` (KDE shortcuts use the systemd user environment, not fish's).

**Verify.** Press Meta: rofi opens; press Meta again or click another window: it closes.

## 10. Global shortcuts

Written by `apply-kde-settings.sh --shortcuts`, or set by hand in System
Settings > Keyboard > Shortcuts (Add New > Command).

| Shortcut | Action |
| --- | --- |
| Meta | rofi launcher (`rofi-toggle drun`); the Plasma launcher stays on Alt+F1 |
| Meta+T | Konsole (the tiles editor's Meta+T is released) |
| Meta+D | minimise all windows (Peek at Desktop is released) |
| Meta+Q | close window / logout dialog on the desktop (Activity Switcher's Meta+Q is released) |
| Alt+F4 | same as Meta+Q |
| Meta+Shift+S | Spectacle, rectangular region to clipboard |
| Alt+F12 | Spectacle, active window to clipboard |
| Launch (3) (G14 Fn key) | toggle the Slash LED (section 12) |
| KRunner | unbound (rofi replaces it) |

## 11. Power-related user settings

These complement the system-level power setup in [docs/03](03-g14-hardware-and-power.md).

**`~/.config/environment.d/90-powerdevil-no-ddcutil.conf`** sets
`POWERDEVIL_NO_DDCUTIL=1`.
Why: at login PowerDevil probed every I2C bus with libddcutil looking for
external monitors with DDC/CI brightness. On this machine that was about 15 s
of 100% CPU with retry errors on one bus. Worse, when DDC transactions do run,
PowerDevil's main thread can block and the brightness keys stop working. The
internal panel's brightness is unaffected; only DDC brightness control of
external monitors is lost. Also keep your user out of the `i2c` group for the
same reason. Revert: delete the file and log in again.

**PowerDevil profile (`powerdevilrc`, written by `apply-kde-settings.sh`)**:
balanced power profile on AC, power-saver on battery; lid and power button
suspend; no idle suspend on AC; low battery at 15%.

**`.local/bin/powerdevil-restart`**: restarts PowerDevil and checks that its
brightness D-Bus interface answers. For the case where brightness keys hang.

**`.config/mpv/mpv.conf`**:
- `hwdec=vaapi` and `vo=dmabuf-wayland`: decode on the GPU and hand the
  decoded buffer straight to the compositor. With software decoding mpv used
  about 2.7 W more than the browser for the same VP9 video (measured on this
  machine, on battery).
- `ytdl-format` capped at 1440p60: the 2880x1800 panel gains nothing from 4K
  streams.
- `[mpo-sdr-gamma22]` profile: tags SDR video as gamma 2.2 instead of
  BT.1886. With the BT.1886 tag KWin needs a transfer-function conversion and
  will not put the video on a hardware plane; Windows also passes SDR video
  through unconverted. HDR (PQ/HLG) is left alone.

**`.local/bin/video-mode`**: manual switch for long video sessions. Sets the
internal panel to 1920x1200@60 with VRR "always" and restores the previous
mode afterwards (`video-mode on|off|status`, or `video-mode with mpv file.mkv`).
Measured on this machine: about 3 W less while playing video. It is
deliberately manual, not an automatic rule on battery.

The stuck-task / awake-dGPU watcher (`stuck-watch` and its timer) is also a
user unit under `home/`, but it is described with the power setup in [docs/03](03-g14-hardware-and-power.md).

## 12. G14 hardware helpers

**Speakers after unplugging headphones (ALC285).**
`.local/bin/alc285-port-watch` + `alc285-port-watch.service` watch the
active port of the analog sink with `pactl subscribe`; on every switch,
`.local/bin/alc285-audio-fix` sets the mixer: for speakers it unmutes
Speaker, Bass Speaker and the two amplifier controls and sets them to 100%;
for headphones it mutes the speakers. Without it the speakers (in particular
the bass speakers) can stay muted after headphones are removed.
The card index is looked up from the PCI address by
`/usr/local/bin/alc285-card` (installed with the system files, [docs/03](03-g14-hardware-and-power.md)),
because it shifts when the dGPU's HDMI audio function disappears. The sink
name contains the PCI address `65:00.6` (GA403); override it with
`ALC285_SINK=...` in a service drop-in if `pactl list short sinks` shows
something else.
Verify: `systemctl --user status alc285-port-watch`, plug and unplug headphones.
Revert: `systemctl --user disable --now alc285-port-watch.service`.

**Slash LED toggle.** `.local/bin/slash-toggle` turns the lid light bar on or
off with `asusctl slash` and shows the state in the Plasma OSD. The
`net.local.slash-toggle.desktop` entry is bound to the G14 Fn key that sends
`Launch (3)`.

**Touchpad** (`kcminputrc`, G14 touchpad `ASCF1206:00 2808:0250`): natural
scrolling, scroll speed 0.3 (slower than the default 1.0, which felt too fast
on this large touchpad), disable while typing. On other hardware the group simply does not
match and is ignored.

**Display.** The internal panel runs at 150% scale (System Settings >
Display). That is stored in `kwinoutputconfig.json` together with
per-machine output IDs, so it is not shipped; set it by hand.

## 13. Notifications

**`.local/bin/notify-send`** wraps `/usr/bin/notify-send`. Plasma makes a
notification persistent when it has `-t 0` or critical urgency (critical
forces the timeout to 0 and ignores `-t`). Scripts that send critical
notifications then leave popups on screen until clicked. The wrapper turns
both into normal urgency with Plasma's default timeout; the notification
still lands in the history. A positive `-t` is kept. For a truly persistent
notification: `NOTIFY_SEND_PERSISTENT=1 notify-send ...`. It only works
because `~/.local/bin` comes before `/usr/bin` in `PATH`.

`plasmanotifyrc`: Do Not Disturb is not switched on automatically for
fullscreen windows; low-priority notifications are kept in the history.

## 14. Update notifier

[cachy-update](https://github.com/CachyOS/cachy-update), the CachyOS fork
of [arch-update](https://github.com/Antiz96/arch-update), with the
[arch-update-gui](https://github.com/lckt0/arch-update-gui) popup instead of
a terminal window.

- `.config/arch-update/arch-update.conf`: `ShowTrayWhenRelevant`, so the tray
  icon only appears when there is something to do.
- `.local/share/icons/hicolor/scalable/apps/cachy-update*.svg`: the nine tray
  and notification icons redrawn with the Arch logo instead of the CachyOS
  one, keeping the original status badges. Icons in `~/.local/share/icons`
  take precedence over `/usr/share/icons`, so the package is not modified.
  `scripts/gen-arch-update-icons.py <dir>` regenerates them from the installed
  package icons and `/usr/share/pixmaps/archlinux-logo.svg`; rerun it if a
  cachy-update release adds or renames icons.
- Enable the periodic check and the tray applet:
  `systemctl --user enable --now arch-update.timer` and
  `arch-update --tray --enable`.

Revert: delete the SVGs and run `kbuildsycoca6`.

## 15. File indexing

**`.config/systemd/user/kde-baloo.service.d/offscreen.conf`**:
`QT_QPA_PLATFORM=offscreen` for Baloo. The KF6 content extractor loads a Qt
platform plugin; started before `WAYLAND_DISPLAY` exists it fails to load
wayland/xcb and aborts in a loop (hundreds of core dumps a minute, DrKonqi
popups). The indexer does not need a display.

Keep Baloo away from large trees it has no business indexing (backups, kernel
and other build directories): one big backup directory cost about 1 W
continuously while it was being indexed. Add them in System Settings > File
Search, or:

```sh
balooctl6 config add excludeFolders ~/Backups
```

If something pulls in GNOME's indexer (for example `xdg-desktop-portal-gnome`
depends on Nautilus, which brings `localsearch`), you get a second indexer
running next to Baloo. Mask it:

```sh
systemctl --user mask localsearch-3.service localsearch-control-3.service localsearch-writeback-3.service
```

## 16. Other small settings

Written by `apply-kde-settings.sh`:

- `ksmserverrc`: start with an empty session instead of restoring the previous one.
- `krunnerrc`: KRunner is free-floating (centred) rather than attached to the top edge.
- `kdeglobals`: Papirus icon theme, animation speed factor 0.5.
- `konsolerc`: default profile, no menu bar, do not remember window size.

`~/.config/environment.d/10-user-paths.conf` adds `~/.local/bin` to the
session `PATH`.

## 17. What is deliberately not included

- Browser profiles, browser flags (there are no `~/.config/*-flags.conf`
  files in this setup), KDE Wallet, KDE Connect pairings, NetworkManager
  connections, SSH/GPG, shell history, caches, recently-used lists.
- Whole KDE rc files, the panel layout and output configuration (machine IDs,
  geometry).
- GTK settings files (regenerated by Plasma, section 6), `fontconfig/fonts.conf`
  (written by System Settings > Fonts).
- Third-party KWin scripts and Plasma widgets; install them from the KDE Store.
- Theme files that belong to the Iris projects (section 7).
- Other personal projects that run on this machine:
  [zephyrusctl](https://github.com/lckt0/zephyrusctl) (Qt/Kirigami control
  panel for the G14, a replacement for ROG Control Center) and
  [harfiyen](https://github.com/lckt0/harfiyen) (touch-typing trainer).
