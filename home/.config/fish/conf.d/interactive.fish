# Interactive shell setup.
set fish_greeting ""
if status is-interactive
    fastfetch
    alias clear="clear && fastfetch"
    # Ctrl+Backspace deletes the previous word (terminals send \b for it).
    bind \b backward-kill-word
end
