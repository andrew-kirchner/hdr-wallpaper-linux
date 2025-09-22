#|system level rules:
#|/etc/xdg/kwinrulesrc
#|personal rules
#|~/.config/kwinrulesrc
function applykdewindowrule {
	local FILE_KWINRULE="$1"
	local RULE_NAME="$(grep -Po "(?<=\[).+?(?=\])" "$FILE_KWINRULE")"
	if [[ "$RULE_NAME" == *$'\n'* ]]; then
		printf "$FILE_KWINRULE cannot have multiple groups!\n">&2
		return 1
	fi
	if [[ ! -f "$HOME/.config/kwinrulesrc" ]]; then
		printf "\e[1mApplying KDE window rules!\e[0m
Check window rules in plasma settings\n"
		#|if the users config file doesnt exist,
		#|the system level rules won't be referenced there
		#|so we need to get them manually then add it back
		local -i SYSTEM_LEVEL_COUNT=$(
			kreadconfig6 --file /etc/xdg/kwinrulesrc --group General --key count
		)
		local SYSTEM_LEVEL_RULES="$( # comma separated list
			kreadconfig6 --file /etc/xdg/kwinrulesrc --group General --key rules
		)"
		cp "$FILE_KWINRULE" "$HOME/.config/kwinrulesrc"
		#|for some reason if you set a key that isnt there
		#|yet in the config to 1 it just doesnt work
		kwriteconfig6 --file kwinrulesrc --group General --key count bugplaceholder
		kwriteconfig6 --file kwinrulesrc --group General \
			--key count $((SYSTEM_LEVEL_COUNT + 1))
		kwriteconfig6 --file kwinrulesrc --group General \
			--key rules "${SYSTEM_LEVEL_RULES:+$SYSTEM_LEVEL_RULES,}$RULE_NAME"
		if ! command -v qdbus >/dev/null; then
			printf "qdbus missing! apply rule manually"
		else
			qdbus org.kde.KWin /KWin reconfigure
		fi
		return 0
	fi
	local WINDOW_RULES="$(
		kreadconfig6 --file kwinrulesrc --group General --key rules
	)"
	if [[ "$WINDOW_RULES" =~ (^|,)"$RULE_NAME"(,|$) ]]; then
		# wallpaper rule is already there
		return 0
	fi
	printf "\e[1mApplying new KDE window rule class \e[0m
on top of possible system level rules and personal rules!
You can see all types of rules in plasma settings.\n"
	local -i WINDOW_COUNT="$(
		kreadconfig6 --file kwinrulesrc --group General --key count
	)"
	echo >> "$HOME/.config/kwinrulesrc" # add newline
	cat "$WALLPAPER_KWINRULE" >> "$HOME/.config/kwinrulesrc"
	kwriteconfig6 --file kwinrulesrc --group General --key count bugplaceholder
	kwriteconfig6 --file kwinrulesrc --group General \
		--key count $((WINDOW_COUNT + 1))
	kwriteconfig6 --file kwinrulesrc --group General \
		--key rules "${WINDOW_RULES:+$WINDOW_RULES,}$RULE_NAME"
	qdbus org.kde.KWin /KWin reconfigure
}
if ! command -v kwriteconfig6 >/dev/null; then
	function applykdewindowrule {
		printf "kwriteconfig6 not found! It seems you are not on Plasma,
the script itself will run normally but you must (for now)
add your own window rule equivalent in settings or a plugin
to put mpv in the background and prevent user input\n" >&2
	}
fi
