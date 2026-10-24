# Accept yay's default answers automatically; pass --confirm to be asked.
# A bare `yay` means `yay -Syu`; `yay <term>` (the numbered search menu) is not affected.
function yay --wraps yay --description 'yay: --noconfirm by default (--confirm to opt out)'
    if not set -q argv[1]; and __pkg_noconfirm_needed yay
        command yay -Syu --noconfirm
    else if __pkg_noconfirm_needed yay $argv
        command yay --noconfirm $argv
    else
        command yay $argv
    end
end
