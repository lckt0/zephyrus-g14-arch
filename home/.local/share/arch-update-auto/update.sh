#!/bin/bash

# Sourced in place of cachy-update's update.sh (set up by arch-update-tray).
# Once the update has been confirmed and the news read, no further questions
# are asked: each one is printed and answered with its default. The functions
# defined here stay in effect for every library sourced afterwards.

# Prompts: an empty answer is the same as pressing Enter.
# [Y/n] -> yes (cache cleanup), [y/N] -> no (orphans, reboot),
# service list -> nothing is restarted.
ask_msg() {
	# shellcheck disable=SC2154
	echo -e "${blue}->${color_off}${bold} ${1}${color_off} ${green}[default]${color_off}"
	# shellcheck disable=SC2034
	answer=""
}

ask_msg_array() {
	echo -e "${blue}->${color_off}${bold} ${1}${color_off} ${green}[default]${color_off}"
	# shellcheck disable=SC2034
	answer_array=()
}

# pacman -Syu, the AUR helper and flatpak accept their own prompts by default.
eval "${su_cmd}() {
	if [ \"\${1}\" == \"pacman\" ]; then
		command ${su_cmd} \"\$@\" --noconfirm
	else
		command ${su_cmd} \"\$@\"
	fi
}"

if [ -n "${aur_helper}" ]; then
	eval "${aur_helper}() { command ${aur_helper} \"\$@\" --noconfirm; }"
fi

flatpak() {
	if [ "${1}" == "update" ]; then
		command flatpak "$@" --assumeyes
	else
		command flatpak "$@"
	fi
}

# shellcheck source=/dev/null
source "/usr/share/arch-update/lib/update.sh"
