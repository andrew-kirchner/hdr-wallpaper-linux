#!/usr/bin/env bash
set -euo pipefail
#|just point to script directory instead of changing
#|the pwd so relative paths can be used for media
swd=$(dirname $(readlink -f "$0"))
MPV_CONF="$swd/mpv.conf"
MEDIA_SYMLINK="/tmp/HDRmediasymlink"
SOCKET="/tmp/HDRsocket"
SOCAT_PTY="/tmp/HDRpty"
declare -a DEFAULT_PATHS=("$HOME/Videos")

function throw {
	notify-send "$1" "$2" -a "HDRpaper error"
	printf "\e[31m%s\e[0m %s\n" "[$1]" "$2" >&2
	exit 1
}

function waitpath {
	local path="$1"
	local -i slumber=1
	# works the same for socket -S
	while [[ ! -w "$path" ]]; do
		sleep ".$(((slumber++)))"
		# 2 seconds
		if [[ $slumber -eq 4 ]]; then
			printf "Waiting on %s...\n" "$path"
			sleep 0.5
		fi
		# 0.5 + 4.5 seconds
		if [[ $slumber -eq 10 ]];  then
			return 1
		fi
	done
	return 0
}

#|modular option parser
#|fun learning excercise :)
#|would be in a separate file if this was a larger script
#|try to break it i dare you
declare -A FLAGS
declare -A OPTARGMAP
declare -a POSITIONALS
function parseoptions {
	local -r GETOPT="$1"
	#|I have not found a practical use for new lines here,
	#|so for now it is cleaner and more secure to ban them
	#|you can still put newlines inbetween your flags and
	#|stuff to format them as getopt cleans it
	if [[ "$GETOPT" == *$'\n'* ]]; then
		throw "Parsing error" "Newlines are not allowed in options!"
	fi

	#|replace all quoted text with arbitrary text (crosses)
	#|of the same length in order to further simplify regex
	local sanitized="$GETOPT"
	local redaction
	local quote
	while read -r quote; do
		redaction=$(printf "X%.0s" $(seq 1 ${#quote}))
		sanitized="${sanitized/"$quote"/"$redaction"}"
	done < <(grep -Po "'.*?'(?!\\\'')" <<< "$GETOPT")

	local -r SHORTLONG=$(grep -Po -- "^.*?(?= --(?:$| X))" <<< "$sanitized")
	if grep -Pq -- "(-+[a-z]+).*\1" <<< "$SHORTLONG"; then
		throw "Parsing error" "No duplicate options!"
	fi

	#|iterate through both boolean flags and key value
	#|options and assign them to their respective array/map
	local option
	local uptokey
	local -i keyvalueindex
	local key
	local value
	while read -r option; do
		# I am a boolean flag
		if [[ "$option" != *" "* ]]; then
			FLAGS["$option"]=1
			continue
		fi
		# I am an option with an argument
		key="${option%% *}"
		#|use substring indices to replenish crosses from
		#|earlier with the user's option value
		uptokey=${sanitized%%"$option"*}
		keyvalueindex=(${#uptokey}+${#key}+2)
		# replenish sanitizing and shave off quotes
		value="${GETOPT:$keyvalueindex:(${#option}-${#key}-3)}"
		value="${value//"'\\''"/"'"}"
		OPTARGMAP["$key"]="$value"
	done < <(grep -Po -- "-+[a-z]+(?: X+)?" <<< "$SHORTLONG")

	# do much of the same tricks for positional arguments
	local argument
	local -i positional_index
	local -i positional_length
	local value
	while read -r argument; do
		#|grep outputs a number for where the match is in the string
		#|and then the match of the crosses delimited by a colon
		positional_index="${argument%%:*}"
		argument="${argument##*:}"
		positional_length="${#argument}"
		value="${GETOPT:$positional_index+1:$positional_length-2}"
		value="${value//"'\\''"/"'"}"
		POSITIONALS+=("$value")
	done < <(grep -Pob -- "X+(?!.*? --(?:$| ))" <<< "$sanitized")
}

SHORTOPTIONS="hqrsp:i:"
LONGOPTIONS=\
"help,quit,repeat,skip,playlist:,image-display-duration:"
parseoptions "$(getopt -o "$SHORTOPTIONS" -l "$LONGOPTIONS" -- "$@")"

function flagpresent {
	local flag="$1"
	[[ "${FLAGS["-${flag:0:1}"]:-}" || "${FLAGS["--$flag"]:-}" ]]
}
if flagpresent "help"; then
	cat <<DELIM
Usage: wallpaper.sh [options] [mediapath1 mediapath2 ...]
Play media file(s) as desktop wallpapers.

    -h, --help          Display me then exit

Repository page: <https://gitlab.com/andrewkirchner/HDRpaper>
DELIM
	exit 0
fi
if flagpresent "quit"; then
	if pkill -f "mpv --title=wallpaper-mpv"; then
		rm -f "$SOCKET"
		rm -f "$MEDIA_SYMLINK"
		exit 0
	fi
	exit 1
fi
if flagpresent "skip"; then
	socat - "$SOCKET" <<< \
	'{"command":["show-text","skipping...\n",1000]}'
	socat - "$SOCKET" <<< \
	'{"command":["playlist-next","force"]}'
	exit 0
fi
if flagpresent "repeat"; then
	socat - "$SOCKET" <<< \
	'{"command":["show-text","file will repeat...\n",2000]}'
	socat - "$SOCKET" <<< \
	"{\"command\":[\"loadfile\",\"$MEDIA_SYMLINK\",\"append\"]}"
	exit 0
fi
#=====

# Parse media files from positional arguments
if [[ ! "${POSITIONALS[@]}" ]]; then
	POSITIONALS=("${DEFAULT_PATHS[@]}")
fi
declare -a WALLPAPERS
for media_path in "${POSITIONALS[@]}"; do
	if [[ ! -r "$media_path" ]]; then
		throw "Parsing error" "\"$media_path\" is not a file or directory!"
	fi
	if [[ -d "$media_path" ]]; then
		while IFS= read -r -d $'\0' item; do
			if [[ $(file -ib "$item") =~ ^(image|video) ]]; then
				WALLPAPERS+=("$item")
			fi
		done < <(find "$media_path" -type f -print0)
		continue
	fi
	if [[ $(file -ib "$media_path") =~ ^(image|video) ]]; then
		WALLPAPERS+=("$media_path")
	fi
done
if [[ ${#WALLPAPERS[@]} == 0 ]]; then
	throw "Parsing error" "No wallpapers supplied from paths!"
fi

function cleanup {
	rm -f "$MEDIA_SYMLINK"
	rm -f "$SOCKET"
	pkill -f "mpv --title=wallpaper-mpv" || true
	# make cursor visible after mpv messes with it
	tput cnorm
	printf "\n\e[1;34m%s\e[0m\n" "Script and MPV closed!"
	exit 0
}; trap cleanup EXIT
if pkill -f "mpv --title=wallpaper-mpv"; then
	printf "Closed previous instance of this script!\n"
fi

mpv --title=wallpaper-mpv --input-ipc-server="$SOCKET" --include="$MPV_CONF" &
if ! waitpath "$SOCKET"; then
	throw "Socket error" "MPV's socket failed to open!"
fi
#|Create a pseudo terminal with its own stdin and out
#|for socat to use, allowing the script to be executed
#|from limited environments like kRunner and shortcuts
socat pty,raw,echo=0,link="$SOCAT_PTY" UNIX-CONNECT:"$SOCKET" &
if ! waitpath "$SOCAT_PTY"; then
	throw "PTY error" "socat terminal failed to open!"
fi
exec 3<>"$SOCAT_PTY"

# https://mpv.io/manual/master/#list-of-input-commands
# https://mpv.io/manual/master/#json-ipc
function plaympv {
	local wallpaper="$1"
	# use symlink to avoid json parsing/jq dependency
	rm -f "$MEDIA_SYMLINK"
	ln -sr "$wallpaper" "$MEDIA_SYMLINK"
	printf "\e[36m%s\e[0m\n" "MPV is playing $wallpaper"
	echo "{\"command\":[\"loadfile\",\"$MEDIA_SYMLINK\"]}" >&3
}

# plaympv "/home/reggie/Videos/daylight.ts"
declare -ir RANGE=${#WALLPAPERS[@]}
declare -i random=$(shuf -n 1 -i 0-$RANGE)
plaympv "${WALLPAPERS[$random]}"
while read -u 3 event; do
	case "$event" in
		*'"reason":"error"'*)
			throw "Fatal Error" "$event"
		;;
		*"idle"*)
			#|mpv finished playing the last
			#|file and cleaned up
		;;
		*)
			# irrelevant event like seeking
			continue
		;;
	esac
	#|ignore events except for idle, which indicates
	#|that a file has finished playing and cleaned up
	random=$(shuf -n 1 -i 0-$RANGE)
	plaympv "${WALLPAPERS[$random]}"
done
stty echo
