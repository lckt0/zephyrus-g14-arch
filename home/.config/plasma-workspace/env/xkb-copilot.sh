#!/bin/sh
# Make the Copilot key bindable as a KDE shortcut.
#
# The key's firmware sends Shift+Super+F23. xkeyboard-config maps that to the
# XF86Assistant keysym, which Qt 6 does not know, so the KDE shortcut dialog
# only shows "Meta+Shift" and the key cannot be bound.
# ~/.config/xkb/symbols/copilot turns that level into a plain F19 (Qt knows it).
#
# KWin takes its keymap options from this environment variable, not from kxkbrc.
if [ -n "$XKB_DEFAULT_OPTIONS" ]; then
    export XKB_DEFAULT_OPTIONS="$XKB_DEFAULT_OPTIONS,custom:copilot"
else
    export XKB_DEFAULT_OPTIONS="terminate:ctrl_alt_bksp,custom:copilot"
fi
