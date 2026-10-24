# Shared decision for the pacman/yay/sudo wrappers: should --noconfirm be added
# to these arguments? (0 = add it, 1 = leave the command alone)
# - Only in an interactive shell; fish scripts are not affected.
# - If the user passed --confirm or --noconfirm, nothing is changed
#   (--confirm = "ask me this time").
# - Only for operations that change something: -S -R -U -D (and their long
#   forms); for yay also a bare `yay` (which means `yay -Syu`).
function __pkg_noconfirm_needed --description 'Should --noconfirm be added to these pacman/yay arguments'
    status is-interactive; or return 1
    set -l tool $argv[1]
    set -l args $argv[2..-1]
    if contains -- --confirm $args; or contains -- --noconfirm $args
        return 1
    end
    if test "$tool" = yay; and not set -q args[1]
        return 0
    end
    for a in $args
        test "$a" = --; and break
        if string match -qr -- '^--(sync|remove|upgrade|database)$' $a
            return 0
        end
        if string match -qr -- '^-[A-Za-z]*[SRUD]' $a
            return 0
        end
    end
    return 1
end
