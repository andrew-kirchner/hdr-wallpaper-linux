#!/usr/bin/env bash
set -euo pipefail
cd $(dirname "$0")
MPV_CONF="$(pwd)/mpv.conf"
#TODO: multiple monitor support i.e. multiple sockets
SOCKET="/tmp/wallpapersocket"
declare -a DEFAULT_PATHS=("$HOME/Videos")

function throw {
	notify-send "Error:" "$1" -a "HDRpaper error"
	echo "$1" >&2
	exit 1
}

# modular option parser
# fun learning excercise :)
# would be in a separate file if this was a larger script
# try to break it i dare you
declare -a FLAGS
declare -A OPTARGMAP
declare -a POSITIONALS
function parseoptions {
	local -r GETOPT="$1"
	#|I have not found a practical use for new lines here,
	#|so for now it is cleaner and more secure to ban them
	#|you can still put newlines inbetween your flags and
	#|stuff to format them as getopt cleans it
	if [[ "$GETOPT" == *$'\n'* ]]; then
		throw "Newlines not allowed in options!"
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
		throw "No duplicate options!"
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
			FLAGS+=("$option")
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

function plaympv {
	local wallpaper="$1"
	# use symlink to avoid json parsing/jq dependency
	local socat_symlink=$(mktemp -u)
	ln -s "$wallpaper" "$socat_symlink"
	socat - "$SOCKET"\
	<<< "{ \"command\": [\"loadfile\", \"$socat_symlink\", \"replace\"] }"\
	>/dev/null
	unlink "$socat_symlink"
}

#TODO: add this back in
function timevideo {
	local videoname=$(basename "$1")
	local parameters=""
	local -i start_time
	local -i end_time
	if start_time=$(grep -Po '^\d{1,6}' <<< "$videoname"); then
		parameters+="--start=$start_time "
	fi
	if end_time=$(grep -Po '\d{1,6}(?=\.[^.]+$)' <<< "$videoname");  then
		parameters+="--end=$end_time "
	fi
	echo "$parameters"
}


SHORTOPTIONS="hvqrs:i:"
LONGOPTIONS="help,version,quit,replay,sort:,image-display-duration:"
parseoptions "$(getopt -o "$SHORTOPTIONS" -l "$LONGOPTIONS" -- "$@")"

if [[ ! "${POSITIONALS[@]}" ]]; then
	POSITIONALS=("${DEFAULT_PATHS[@]}")
fi

declare -a WALLPAPERS
for media_path in "${POSITIONALS[@]}"; do
	if [[ ! -r "$media_path" ]]; then
		throw "\"$media_path\" is not a file or directory!"
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
	throw "No wallpapers supplied from paths!"
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
# > /dev/null 2>&1
while [[ ! -S "$SOCKET" ]]; do
	sleep 1
done

declare -ir RANGE=(${#WALLPAPERS[@]}-1)
declare -i random=$(shuf -i 0-$RANGE -n 1)
declare -i last_index=$random
echo "MPV is playing ${WALLPAPERS[$random]}"
plaympv "${WALLPAPERS[$random]}"
while read -r event; do
	if [[ "$event" != *"idle"* ]]; then continue; fi
	random=last_index
	while [[ $random == $last_index ]]; do
		random=$(shuf -i 0-$RANGE -n 1)
	done
	echo "MPV is playing ${WALLPAPERS[$random]}"
	plaympv "${WALLPAPERS[$random]}"
done < <(socat - "$SOCKET")
echo "MPV and program have closed."
