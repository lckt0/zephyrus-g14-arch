# Make `sudo pacman ...` follow the same rule as the pacman wrapper.
# If the first argument is not exactly `pacman`, sudo is called unchanged.
function sudo --wraps sudo --description 'sudo: --noconfirm by default for `sudo pacman`'
    if test "$argv[1]" = pacman; and __pkg_noconfirm_needed pacman $argv[2..-1]
        command sudo pacman --noconfirm $argv[2..-1]
    else
        command sudo $argv
    end
end
