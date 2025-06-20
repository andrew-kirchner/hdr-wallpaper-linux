#!/usr/bin/env bash
set -uo pipefail
cd $(dirname "$0")
MPV_CONF="$(pwd)/mpv.conf"
FILE_OR_DIRECTORY="${1:-"$HOME/Videos"}"

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
	if [[ "$GETOPT" == *$'\n'* ]]; then
		throw "Newlines not allowed in options!"
	fi

	#|replace all quoted text with arbitrary text of the
	#|same length in order to further simplify regex
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
		#|use substring indices to replace crosses from
		#|earlier with the option
		uptokey=${sanitized%%"$option"*}
		keyvalueindex=(${#uptokey}+${#key}+2)
		value="${GETOPT:$keyvalueindex:(${#option}-${#key}-3)}"
		value="${value//"'\\''"/"'"}"
		OPTARGMAP["$key"]="$value"
	done < <(grep -Po -- "-+[a-z]+(?: X+)?" <<< "$SHORTLONG")

	local argument
	local -i positional_index
	local -i positional_length
	local value
	while read -r argument; do
		positional_index="${argument%%:*}"
		argument="${argument##*:}"
		positional_length="${#argument}"
		value="${GETOPT:$positional_index+1:$positional_length-2}"
		echo "$value"
		value="${value//"'\\''"/"'"}"
		POSITIONALS+=("$value")
	done < <(grep -Pob -- "X+(?!.*? --(?:$| ))" <<< "$sanitized")
}

# parseoptions "$(getopt -o abcx:y:z: -l long,sort: -- "$@")"
# echo "${FLAGS[@]}"
# echo "----"
# echo "keys:${!OPTARGMAP[@]}|values:${OPTARGMAP[@]}"
# echo "----"
# echo "${POSITIONALS[@]}"

function playsinglefile {
	local media_file="$1"
	if ! [[ $(file -b --mime-type "$media_file") =~ ^(image|video) ]]; then
		throw "$media_file is not an image or video!"
	fi
	if pkill -f "mpv*.--title=wallpaper-mpv"; then
		echo "Closed previous instance of this script for single file"
	fi
	#TODO: using loop and start/end parameters seems to not
	#be supported for some reason
	mpv --title=wallpaper-mpv --include="$MPV_CONF" --profile=hdr \
		--loop=inf \
		--image-display-duration=inf \
		"$media_file"
}

function timempv {
	local media_file="$1"
	# enum "image" or "video"
	local filetype=$(file -b --mime-type $media_file | cut -d / -f 1)

	if [[ "$filetype"=="image" ]]; then
		echo ""
	fi
	# adjust when a video starts or ends based on its filename
	# ex: 10video20.mp4 will start 10 seconds into the video and end 20 seconds in
	local filename=$(basename $media_file)
	local parameters=""
	local start_time
	local end_time
	if start_time=$(grep -Po '^\d{1,6}' <<< "$filename"); then
		parameters+="--start=$start_time "
	fi
	if end_time=$(grep -Po '\d{1,6}(?=\.[^.]+$)' <<< "$filename");  then
		parameters+="--end=$end_time "
	fi
	echo "$parameters"
}

if [[ -f $FILE_OR_DIRECTORY ]]; then
	playsinglefile $FILE_OR_DIRECTORY
	exit 0
fi
if [[ ! -d $FILE_OR_DIRECTORY ]]; then
	throw "$FILE_OR_DIRECTORY is not a file or directory!"
fi

if pkill -f "mpv*.--title=wallpaper-mpv"; then
	echo "Closed previous instance of this script"
fi


declare -a wallpapers
# split by null byte to account for spaces/emojis/newlines
mapfile -d '' wallpapers < <(find $FILE_OR_DIRECTORY -type f -print0)
# remove non media files
for fileindex in "${!wallpapers[@]}"; do
	if [[ $(file -b --mime-type "${wallpapers[$fileindex]}") =~ ^(image|video) ]];
		then continue;
	fi
	unset "wallpapers[$fileindex]"
done

declare -ir RANGE=(${#wallpapers[@]}-1)
declare -i last_index=-1
declare -i random
while true; do
	random=$(shuf -i 0-$RANGE -n 1)
	if [[ $random -eq $last_index ]]; then
		continue
	fi
	last_index=$random

	media_file="${wallpapers[$random]}"
	filename_parameters="$(timempv "$media_file")"
	echo "MPV is playing $media_file"
	mpv --title=wallpaper-mpv --include="$(pwd)/mpv.conf" --profile=hdr $filename_parameters"$media_file"
	if [[ $? == 4 ]]; then
		echo "MPV has been pkilled, exiting"
		exit 0
	fi
	# prevent crash after a few hours of buildup
	sleep 1
done
