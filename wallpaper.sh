#!/usr/bin/env bash
set -euo pipefail
cd $(dirname "$0")

FILE_OR_DIRECTORY=${1:-"$HOME/Videos"}

function throw {
	local error_message="$1"
	notify-send "Error:" "$1" -a "HDRpaper error"
	echo "$1" >&2
	exit 1
}

function fromfile {
	local media_file="$1"
	if ! [[ $(file -b --mime-type "$media_file") =~ ^(image|video) ]]; then
		throw "$media_file is not an image or video!"
	fi
	echo "$media_file"
}

function fromdirectory {
	local media_directory="$1"
	declare -a wallpapers

	# array of all filenames, including emojis/spaces/newlines
	mapfile -d '' wallpapers < <(find $media_directory -type f -print0)

	# remove non media files
	for fileindex in "${!wallpapers[@]}"; do
		if [[ $(file -b --mime-type "${wallpapers[$fileindex]}") =~ ^(image|video) ]];
			then continue;
		fi
		unset "wallpapers[$fileindex]"
	done
	# remove empty array indices just made
	wallpapers=("${wallpapers[@]}")

	if [[ ${#wallpapers[@]} -eq 0 ]]; then
		throw "there are no images or videos in $media_directory!"
	fi
	# return random wallpaper
	echo "${wallpapers[$(shuf -i "0-$((${#wallpapers[@]}-1))" -n 1)]}"
}

if [[ -f $FILE_OR_DIRECTORY ]]; then
	OUTPUT_WALLPAPER=$(fromfile "$FILE_OR_DIRECTORY")
elif [[ -d $FILE_OR_DIRECTORY ]]; then
	OUTPUT_WALLPAPER=$(fromdirectory "$FILE_OR_DIRECTORY")
else
	throw "$FILE_OR_DIRECTORY is not a file or directory!"
fi

if pkill -f "mpv*.--title=wallpaper-mpv"; then
	echo "Closed previous instance of this script"
fi

# enum "image" or "video"
filetype=$(file -b --mime-type $OUTPUT_WALLPAPER | cut -d / -f 1)

# adjust when a video starts or ends based on its filename
# ex: 10video20.mp4 will start 10 seconds into the video and end 20 seconds in
filename=$(basename $OUTPUT_WALLPAPER)
if starttime=$(grep -Po '^\d{1,6}' <<< "$filename"); then
	starttime="--start=$starttime "
fi
if endtime=$(grep -Po '\d{1,6}(?=\.[^.]+$)' <<< "$filename");  then
	endtime="--end=$endtime "
fi

echo "Playing file $OUTPUT_WALLPAPER"
mpv --title=wallpaper-mpv --include="$(pwd)/mpv.conf" --profile=hdr $starttime$endtime"$OUTPUT_WALLPAPER"
echo "mpv ended naturally without being terminated"
# todo: make it loop forever between files or not as per command line options
