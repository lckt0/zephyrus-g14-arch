# Accept pacman's default answers automatically; pass --confirm to be asked.
function pacman --wraps pacman --description 'pacman: --noconfirm by default (--confirm to opt out)'
    if __pkg_noconfirm_needed pacman $argv
        command pacman --noconfirm $argv
    else
        command pacman $argv
    end
end
