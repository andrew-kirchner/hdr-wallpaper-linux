#!/usr/bin/env bash
set -euo pipefail
#|just point to script directory instead of changing
#|the pwd so relative paths can be used for media
swd=$(dirname $(readlink -f "$0"))
MPV_CONF="$swd/mpv.conf"
MEDIA_SYMLINK="$swd/currentmedialink"
SOCKET="$swd/mpvsocket"
#TODO: possibly put sockets and links in /tmp for multi screen support
declare -a DEFAULT_PATHS=("$HOME/Videos")

function throw {
	notify-send "$1" "$2" -a "HDRpaper error" -e
	echo "$1 $2" >&2
	exit 1
}

# modular option parser
# fun learning excercise :)
# would be in a separate file if this was a larger script
# try to break it i dare you
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
		throw "Parsing error!" "Newlines are not allowed in options!"
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
		throw "Parsing error!" "No duplicate options!"
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
function flagpresent {
	local flag="$1"
	[[ "${FLAGS["-${flag:0:1}"]:-}" || "${FLAGS["--$flag"]:-}" ]]
}

SHORTOPTIONS="hqfrnabs:i:"
LONGOPTIONS=\
"help,quit,forever,replay,next,audio,battery,sort:,image-display-duration:"
parseoptions "$(getopt -o "$SHORTOPTIONS" -l "$LONGOPTIONS" -- "$@")"

if flagpresent "help"; then
	cat <<DELIM
Usage: wallpaper.sh [options] [mediapath1 mediapath2 ...]
Play media file(s) as desktop wallpapers.

    -h, --help          Display me then exit
    -q, --quit            Quit the previous script and its mpv instance,
                        exit with code 1 if no instance was found.
    -f, --forever         Play the supplied or sorted and selected
                        media file forever, without an IPC socket.
    -r, --replay          Replay the current image/video again once it ends.
                        This and -n are used in reference to the
                        current MPV instance, unlike the others
                        which are used on initiation of a new instance.
    -n, --next            End the current file early and move on to the next
                        media file in normal order.
    -a, --audio           Enable audio playback for a new instance.
                        Pro tip: you can change the volume by setting
                        individual application volumes! It will be mpv
    -b  --battery         Select only images from files in order to save on
                        battery, energy, or performance... not that this
                        script is proficient in any of those.
    -s, --sort   {random|alphabetical|original}
        Change the order in which supplied files are played.
         Directories are expanded, with all the media being put in one
         array and then sorted.
    -i, --image-display-duration  {seconds|inf}
        Alias for the MPV option, does not affect videos.

Media paths can include anything except newlines. Your directories can
include anything and the script will simply sort for media files.
Creating a (successful) new wallpaper instance will implicitly
close the possible preexisting instance.
Use this or -n to shuffle until you get what you like!
This script should live in the same directory as its mpv.conf and kwinrules.
You can add a soft symlink to ~/bin for easy reference like a true application.
Under Plasma system settings you can add this symlink as a login script.
Repository page: <https://gitlab.com/andrewkirchner/HDRpaper>
DELIM
	exit 0
fi
if flagpresent "quit"; then
	if pkill -f "mpv --title=wallpaper-mpv"; then
		rm -f "$SOCKET"
		exit 0
	fi
	exit 1
fi
if flagpresent "next"; then
	socat - "$SOCKET" <<< '{ "command": ["stop"] }'
	exit 0
fi
if flagpresent "replay"; then
	CURRENT_FILE=$(socat - "$SOCKET" <<<\
	'{ "command": ["get_property", "path"] }'\
	| grep -Po "/[a-zA-z1-9./]+")
	echo "$CURRENT_FILE"
	socat - "$SOCKET" <<<\
	"{ \"command\": [\"loadfile\", \"$CURRENT_FILE\", \"append\"] }"
	exit 0
fi
if [[ ! -t 0 ]]; then
	throw "Script must be ran in interactive console!"\
	"Instead of using a direct shortcut use the .desktop entry" #TODO: lol
	exit 0
fi


function plaympv {
	local wallpaper="$1"
	# use symlink to avoid json parsing/jq dependency
	rm -f "$MEDIA_SYMLINK"
	ln -s "$wallpaper" "$MEDIA_SYMLINK"
	socat - "$SOCKET"\
	<<< "{ \"command\": [\"loadfile\", \"$MEDIA_SYMLINK\", \"replace\"] }"\
	>/dev/null
}

if [[ ! "${POSITIONALS[@]}" ]]; then
	POSITIONALS=("${DEFAULT_PATHS[@]}")
fi
declare -a WALLPAPERS
for media_path in "${POSITIONALS[@]}"; do
	if [[ ! -r "$media_path" ]]; then
		throw "Parsing error!" "\"$media_path\" is not a file or directory!"
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
	throw "Parsing error!" "No wallpapers supplied from paths!"
fi
if [[ ${#WALLPAPERS[@]} == 1 ]]; then
	echo "Playing single file forever..."
	mpv --title=wallpaper-mpv --include="$MPV_CONF" \
	--loop=inf --image-display-duration=inf \
	-- "${POSITIONALS[0]}"
	exit 1
fi


if pkill -f "mpv --title=wallpaper-mpv"; then
	echo "Closed previous instance of this script!"
fi
rm -f "$SOCKET"
mpv --title=wallpaper-mpv --input-ipc-server="$SOCKET" --include="$MPV_CONF" &
while [[ ! -S "$SOCKET" ]]; do
	sleep 1
done

declare -ir RANGE=(${#WALLPAPERS[@]}-1)
declare -i random=$(shuf -i 0-$RANGE -n 1)
declare -i last_index=$random
echo "MPV is playing ${WALLPAPERS[$random]}"
plaympv "${WALLPAPERS[$random]}"

#|prevents terminal window from breaking
#|when mpv is pkilled
function cleanup {
	stty echo
	pkill -f "mpv --title=wallpaper-mpv" || true
	exit 0
}
trap cleanup EXIT

while read -r event; do
	if [[ "$event" != *"idle"* ]]; then continue; fi
# 	sleep 1
	random=$last_index
	while [[ $random == $last_index ]]; do
		random=$(shuf -i 0-$RANGE -n 1)
	done
	last_index=$random
	echo "MPV is playing ${WALLPAPERS[$random]}"
	plaympv "${WALLPAPERS[$random]}"
done < <(socat - "$SOCKET")
echo "Script ended naturally :)"
