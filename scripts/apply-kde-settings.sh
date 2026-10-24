#!/usr/bin/env bash
# apply-kde-settings.sh: write the non-default KDE Plasma settings of this
# setup with kwriteconfig6. Only the keys listed here are touched; everything
# else in your rc files stays as it is.
#
# Usage:
#   scripts/apply-kde-settings.sh [--dry-run] [--shortcuts]
#
#   --dry-run    print the kwriteconfig6 calls, change nothing
#   --shortcuts  also write the custom global shortcuts (kglobalshortcutsrc);
#                log out right after, see docs/05
#
# Run it AFTER the Iris theme installer (iris-desktop/install.sh): that
# installer turns some effects on, this script turns them off again.
# The rc files that are about to change are copied to
#   ~/.local/state/g14-dotfiles/kde-backup-<timestamp>/
# first. To undo, copy them back and log out/in.
#
# Changes take effect after logging out and back in. KWin settings can also be
# reloaded with:  qdbus6 org.kde.KWin /KWin reconfigure
set -euo pipefail

DRY=0
SHORTCUTS=0
for a in "$@"; do
    case "$a" in
        --dry-run)   DRY=1 ;;
        --shortcuts) SHORTCUTS=1 ;;
        -h|--help)   sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="${XDG_STATE_HOME:-$HOME/.local/state}/g14-dotfiles/kde-backup-$STAMP"

command -v kwriteconfig6 >/dev/null || { echo "kwriteconfig6 not found (package kconfig)" >&2; exit 1; }

declare -A backed_up=()
backup() {
    local f="$CFG/$1"
    [[ -n ${backed_up[$1]:-} ]] && return 0
    backed_up[$1]=1
    if (( DRY )); then return 0; fi
    if [[ -f $f ]]; then
        mkdir -p "$BACKUP"
        cp -a "$f" "$BACKUP/"
    fi
}

# w <file> <group[/subgroup...]> <key> <value>
# Nested groups are separated with "/" (e.g. "AC/Performance").
w() {
    local file=$1 group=$2 key=$3 value=$4
    local -a gargs=()
    IFS='/' read -r -a parts <<< "$group"
    for g in "${parts[@]}"; do gargs+=(--group "$g"); done
    backup "$file"
    if (( DRY )); then
        printf 'kwriteconfig6 --file %q' "$CFG/$file"
        printf ' %q' "${gargs[@]}" --key "$key" "$value"
        printf '\n'
    else
        kwriteconfig6 --file "$CFG/$file" "${gargs[@]}" --key "$key" "$value"
    fi
}

# ------------------------------------------------------------------ fonts
# JetBrains Mono 10 everywhere in the UI (terminal excluded: Konsole uses
# JetBrainsMono Nerd Font through its profile). Package: ttf-jetbrains-mono.
FONT='JetBrains Mono,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0'
FONT_SMALL='JetBrains Mono,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0'
for k in font fixed menuFont toolBarFont; do w kdeglobals General "$k" "$FONT"; done
w kdeglobals General smallestReadableFont "$FONT_SMALL"
w kdeglobals WM activeFont "$FONT"
w kdeglobals General XftAntialias true
w kdeglobals General XftHintStyle hintslight
w kdeglobals General XftSubPixel rgb

# ------------------------------------------------------------ icons, misc UI
w kdeglobals Icons Theme Papirus
w kdeglobals KDE AnimationDurationFactor 0.5

# --------------------------------------------------------- KWin: effects off
# Any active effect that blocks direct scanout keeps KWin from putting
# fullscreen/windowed content on hardware overlay planes (MPO), which costs
# power. All purely visual effects are off. Functional effects that only run
# while used (overview, windowview, tileseditor, zoom, colorpicker,
# screenedge, outputlocator, highlightwindow) stay at their defaults.
for e in blendchanges blur contrast dialogparent diminactive dimscreen fade \
         fadingpopups frozenapp fullscreen kscreen kwin4_effect_fade \
         kwin4_effect_scale kwin4_effect_translucency login logout magiclamp \
         maximize scale screentransform sessionquit shakecursor slide \
         slidingnotifications slidingpopups squash startupfeedback systembell \
         windowaperture wobblywindows; do
    w kwinrc Plugins "${e}Enabled" false
done

# Behaviour scripts: these are not visual effects, keep them on.
#   rofi-autoclose  ships in home/.local/share/kwin/scripts
#   alt-f4-desktop  https://github.com/micha4w/ (KWin script store: "Alt-F4 Desktop")
#   minimizeall     stock "Minimize all" script (Meta+D style shortcut)
#   desktopchangeosd stock script: small text-only OSD on virtual desktop change
w kwinrc Plugins rofi-autocloseEnabled true
w kwinrc Plugins alt-f4-desktopEnabled true
w kwinrc Plugins minimizeallEnabled true
w kwinrc Plugins desktopchangeosdEnabled true
w kwinrc Script-desktopchangeosd PopupHideDelay 500
w kwinrc Script-desktopchangeosd TextOnly true
# iris-popup-anchor comes with iris-desktop; enable it only if installed.
if [[ -d $DATA/kwin/scripts/iris-popup-anchor ]]; then
    w kwinrc Plugins iris-popup-anchorEnabled true
fi

# ------------------------------------------------------------- KWin: other
w kwinrc TabBox LayoutName thumbnail_grid        # Alt+Tab: thumbnail grid
w kwinrc Effect-overview BorderActivate 9        # no hot corner for Overview
w kwinrc Wayland EnablePrimarySelection false    # no middle-click paste
w kwinrc Desktops Number 3
w kwinrc Desktops Rows 1

# Force the Iris colour scheme on every title bar: apps with their own colour
# scheme still get Iris title bars, and the grey inactive title bar survives
# Plasma rewriting [Colors:Header][Inactive] in kdeglobals. Same rule as the
# iris-desktop installer writes, so the two do not stack. Only if Iris is
# installed.
if [[ -f $DATA/color-schemes/Iris.colors || -f /usr/share/color-schemes/Iris.colors ]]; then
    RULE=iris-titlebar
    w kwinrulesrc "$RULE" Description "Iris title bar"
    w kwinrulesrc "$RULE" decocolor Iris
    w kwinrulesrc "$RULE" decocolorrule 2       # 2 = Force
    order=$(kreadconfig6 --file "$CFG/kwinrulesrc" --group General --key Order 2>/dev/null || true)
    if [[ ",$order," != *",$RULE,"* ]]; then
        w kwinrulesrc General Order "${order:+$order,}$RULE"
    fi
fi

# ------------------------------------------------------------ power (Plasma)
# Power profile follows the power source: balanced on AC, power-saver on
# battery. Lid and power button suspend (s2idle/"SuspendToRam" in Plasma's
# terms). No idle suspend on AC.
w powerdevilrc AC/Performance PowerProfile balanced
w powerdevilrc Battery/Performance PowerProfile power-saver
w powerdevilrc AC/SuspendAndShutdown AutoSuspendAction 0
for p in AC Battery LowBattery; do
    w powerdevilrc "$p/SuspendAndShutdown" SleepMode SuspendToRam
done
for p in AC Battery; do
    w powerdevilrc "$p/SuspendAndShutdown" LidAction Sleep
    w powerdevilrc "$p/SuspendAndShutdown" PowerButtonAction Sleep
done
w powerdevilrc BatteryManagement BatteryLowLevel 15

# ------------------------------------------------------- touchpad (G14 only)
# GA403 touchpad: ASCF1206:00 2808:0250 (vendor 10248, product 592).
# Check yours in System Settings > Touchpad or `libinput list-devices`.
TP='Libinput/10248/592/ASCF1206:00 2808:0250 Touchpad'
w kcminputrc "$TP" NaturalScroll true
w kcminputrc "$TP" ScrollFactor 0.3
w kcminputrc "$TP" DisableWhileTyping true

# --------------------------------------------------------------- session etc.
w ksmserverrc General loginMode emptySession     # start with an empty session
w krunnerrc General FreeFloating true            # KRunner centred, not at the top edge
w plasmanotifyrc DoNotDisturb WhenFullscreen false
w plasmanotifyrc Notifications LowPriorityHistory true

# ----------------------------------------------------------------- Konsole
w konsolerc "Desktop Entry" DefaultProfile G14.profile
w konsolerc MainWindow MenuBar Disabled
w konsolerc KonsoleWindow RememberWindowSize false

# ---------------------------------------------------------------- shortcuts
# The .desktop files referenced here ship in home/.local/share/applications.
if (( SHORTCUTS )); then
    w kglobalshortcutsrc 'services/net.local.rofi-toggle.desktop'   _launch Meta
    w kglobalshortcutsrc 'services/net.local.spectacle-2.desktop'   _launch Meta+Shift+S
    w kglobalshortcutsrc 'services/net.local.spectacle.desktop'     _launch Alt+F12
    w kglobalshortcutsrc 'services/net.local.slash-toggle.desktop'  _launch 'Launch (3)'
    w kglobalshortcutsrc 'services/org.kde.konsole.desktop'         _launch Meta+T
    w kglobalshortcutsrc 'services/org.kde.krunner.desktop'         _launch none
    # Free the defaults that would collide. Format: "current,default,label".
    # Meta alone opens rofi instead of the Plasma launcher (Alt+F1 still does).
    w kglobalshortcutsrc plasmashell 'activate application launcher' $'Alt+F1,Meta\tAlt+F1,Activate Application Launcher'
    w kglobalshortcutsrc plasmashell 'manage activities' 'none,Meta+Q,Show Activity Switcher'
    w kglobalshortcutsrc kwin 'Edit Tiles' 'none,Meta+T,Toggle Tiles Editor'
    w kglobalshortcutsrc kwin 'Show Desktop' 'none,Meta+D,Peek at Desktop'
    w kglobalshortcutsrc kwin MinimizeAll 'Meta+D,none,Minimize all windows'
    w kglobalshortcutsrc kwin Alt-F4-Desktop $'Alt+F4\tMeta+Q,none,Close Window or show Logout Option'
fi

if (( DRY )); then
    echo "# dry run: nothing written"
else
    if [[ -d $BACKUP ]]; then
        echo "Previous rc files saved in: $BACKUP"
    fi
    echo "Done. Log out and back in to apply everything."
fi
