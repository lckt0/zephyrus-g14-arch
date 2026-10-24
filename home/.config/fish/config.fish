# ~/.config/fish/config.fish
# Interactive niceties (greeting, fastfetch) live in conf.d/interactive.fish.
# The pacman/yay/sudo wrappers live in functions/.

set -gx EDITOR micro

set -U fish_key_bindings fish_default_key_bindings

alias c="clear"
alias ff="fastfetch"
