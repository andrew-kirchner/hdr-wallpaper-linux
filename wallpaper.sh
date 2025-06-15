#!/usr/bin/env bash
set -euo pipefail
cd $(dirname "$0")
MPV_CONF="$(pwd)/mpv.conf"
FILE_OR_DIRECTORY=${1:-"$HOME/Videos"}

function throw {
	local error_message="$1"
	notify-send "Error:" "$1" -a "HDRpaper error"
	echo "$1" >&2
	exit 1
}

function playsinglefile {
	local media_file="$1"
	if ! [[ $(file -b --mime-type "$media_file") =~ ^(image|video) ]]; then
		throw "$media_file is not an image or video!"
	fi
	if pkill -f "mpv*.--title=wallpaper-mpv"; then
		echo "Closed previous instance of this script for single file"
	fi
	#TODO: using loop and start/end parameters seems to not
	# be supported for some reason
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
	filename_parameters=$(timempv "$media_file")
	echo "MPV is playing $media_file"
	mpv --title=wallpaper-mpv --include="$(pwd)/mpv.conf" --profile=hdr $filename_parameters"$media_file"
done
