#!/usr/bin/env bash
set -euo pipefail
MPV_CONF="$(dirname $(readlink -f "$0"))/mpv.conf"
MEDIA_SYMLINK="/tmp/HDRmediasymlink"
SOCKET="/tmp/HDRsocket"
declare -a DEFAULT_PATHS=("$HOME/Videos")

function helptext {
	printf "$(cat <<DELIM
Usage: wallpaper.sh [COMMAND]? or [options] [mediapath1 mediapath2 ...]
Play media file(s) as desktop wallpapers.\e[033m
==|=======================================================================|==
\e[0mPlaintext Commands
These commands are used to show information or possibly
modify the current instance instead of creating a new one.

	help, h     Display me then exit
	quit, q     Force close mpv and script, throws if not found
	skip, s     End the current media file and play the next one
	              as per --repeat then --sort
	repeat, r   Loop the current media file once once it ends;
	              throws if file is set to loop forever
	osd, o      Toggle OSD, or more specifically the ability
	              for the window to receive pointer events.
	              Will also capture exclusively mpv shortcuts!
	audio, a    Permanently enable audio for current instance.
	              Toggle volume with the normal mute option!
==|=======================================================================|==
\e[0mBoolean Flags [ -m --mode ] ?= false
These options are used on initialization of a new instance;
if no directories are passed, defaults are used with any flags.

	-l, --loop          Loop media indefinitely until SKIP is called.
	-n, --no-config     Alias for mpv option, do not use personal config.

Arguments with values [ -k v --key v --key=v ] ?= default

	-s, --sort ?= weighted
	  control the order in which valid media paths are played
	    =weighted       Pick media such that they would approach
	                      on average being on screen equally often.
	                      Falls back to random if --loop is set!
	    =random         Pick all media in paths with uniform distribution
	    =randarg        Pick a random top level mediapath then file each time
	    =alphabetical   Play in order based on basename of all media files
	    =newest         Play files in order of the date last moved
	    =none           Play in whatever order supplied by you or find
	-i, --image-display-duration ?= 300
	  control how long images stay up, videos are not affected
	    UNLESS they are animated
	-e, --exclude ?= none
	  exclude file types found in media paths passed before they are sorted
	    ={none|images|videos}\e[035m
==|=======================================================================|==
\e[0mIndividual Arguments
Pass unique options for each media file
based on its filename or directory!

	name[\$start:\$end].videoextension
	  \$start<seconds> seconds after the start of the video
	  \$end<seconds> seconds before the end of the video
	    ex:
	     intro-outro[10:30].mp4  start ten seconds in, end thirty early
	     watermarked[:5].mkv     end five seconds early
	animated/name.videoextension
	  treat file as an animated wallpaper, meaning it repeats
	  and will loop for floor(video duration/image duration)

Repository page: <https://gitlab.com/andrewkirchner/HDRpaper>
DELIM
)"
}

function throw {
	notify-send "$1" "$2" -a "HDRpaper error"
	printf "\e[31m%s\e[0m %s\n" "[$1]" "$2" >&2
	exit 1
}

function waitsocket {
	local path="$1"
	local -i slumber=1
	while [[ ! -S "$path" ]]; do
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
#|fun learning exercise :)
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

	if grep -Pq -- " (-+[a-z-]+).*\1" <<< "$SHORTLONG"; then
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
	done < <(grep -Po -- " -+[a-z-]+(?: X+)?" <<< "$SHORTLONG")

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

SHORTOPTIONS="hlns:i:e:"
LONGOPTIONS=\
"help,loop,no-config,sort:,image-display-duration:,exclude:"
parseoptions "$(getopt -o "$SHORTOPTIONS" -l "$LONGOPTIONS" -- "$@")"

if [[ ! -v POSITIONALS ]]; then
	POSITIONALS=("${DEFAULT_PATHS[@]}")
elif grep -Pq "^[a-zA-Z ]+$" <<< "${POSITIONALS[@]}"; then
	readonly CONCATENATION="${POSITIONALS[@]}"
	readonly COMMAND="${CONCATENATION// /}"
	case "${COMMAND,,}" in
		help|h)
			tty --quiet || throw \
			"Environment error" "Run HELP from a terminal!"
			helptext
		;;
		quit|q|kill|k|pkill)
			if pkill -f "mpv --title=wallpaper-mpv"; then
				rm -f "$SOCKET"
				rm -f "$MEDIA_SYMLINK"
				exit 0
			fi
			throw "Error Quitting Script" \
			"mpv window was not found!"
		;;
		skip|s)
			socat - "$SOCKET" <<< \
			'{command=["show-text","skipping...\n",1000]}'
			socat - "$SOCKET" <<< \
			'{command=["playlist-next","force"]}'
		;;
		repeat|r)
			socat - "$SOCKET" <<< \
			'{command=["show-text","file will repeat...\n",2000]}'
			# goes away automatically after file ends
			socat - "$SOCKET" <<< \
			'{command=["set_property","loop",1]}'
		;;
		osd|o)
			socat - "$SOCKET" <<< \
			'{command=["cycle-values","input-cursor-passthrough","yes","no"]}'
			socat - "$SOCKET" <<< \
			'{command=["cycle-values","osc","yes","no"]}'
		;;
		audio|a)
			socat - "$SOCKET" <<< \
			'{command=["set_property","audio","yes"]}'
		;;
		*) throw "Argument error" "Invalid command $COMMAND";;
	esac
	exit 0
fi
function flagpresent {
	local flag="$1"
	[[ "${FLAGS["-${flag:0:1}"]:-}" || "${FLAGS["--$flag"]:-}" ]]
}
if flagpresent "help"; then
	helptext
	exit 0
fi
declare mpv_args=""
flagpresent "loop" && mpv_args+=" --loop=inf --image-display-duration=inf"
flagpresent "no-config" && mpv_args+=" --no-config"
IMAGE_DURATION=\
"${OPTARGMAP["-i"]:-"${OPTARGMAP["--image-display-duration"]:-}"}"
if [[ -n "$IMAGE_DURATION" ]];  then
	grep -Pq "^(?:[0-9.]+|inf)$" <<< "$IMAGE_DURATION" || throw \
	"Argument error" "Invalid --image-display-duration! $IMAGE_DURATION"
	mpv_args+=" --image-display-duration=$IMAGE_DURATION"
fi

declare -a WALLPAPER_PATHS
declare -A IMAGES
declare -A VIDEOS
declare total_duration="0.0"
function searchdirectory {
	declare -a video_paths
	local mime_type
	while read -r -d $'\0' path; do
		mime_type="$(file -b --mime-type "$path")"
		case "$mime_type" in
			image/*)
				WALLPAPER_PATHS+=("$path")
				IMAGES["$path"]=300
			;;
			video/*)
				video_paths+=("$path")
			;;
		esac
	done < <(find "${POSITIONALS[@]}" -type f -print0 )
	if [[ ! -v video_paths ]]; then
		# no videos were found, thats fine play videos
		return 0
	fi
	coproc RELAY {
		while read line; do
			printf "%s\n" "$line"
		done
	}
	exec 3>&"${RELAY[1]}" # keeps relay open
	local path
	for path in "${video_paths[@]}"; do
		probevideo "$path" &
	done

	local -i videos_remaining="${#video_paths[@]}"
	local duration
	while read -t 5 response <&"${RELAY[0]}"; do
		duration="$(grep -Po "[\d.]+$" <<< "$response")"
		path="${response% $duration}"
		VIDEOS["$path"]="$duration"
		WALLPAPER_PATHS+=("$path")
		total_duration="$(awk "BEGIN{printf $total_duration+$duration}")"
		if (( --videos_remaining == 0 )); then
			local SUCCESS=0
			break
		fi
	done
	if [[ ! -v SUCCESS ]]; then
		for path in "${video_paths[@]}"; do
			if [[ -z ${VIDEOS["$path"]:-} ]]; then
				throw "Timeout error" "$path failed ffprobe!"
			fi
		done
	fi
	kill $RELAY_PID
}
function probevideo {
	local video="$1"
	local duration="$(ffprobe -v error \
		-show_entries format=duration \
		-of csv="p=0" \
		"$video"
	)"
	printf "%s %s\n" "$video" "$duration" >&3
}

searchdirectory
if [[ ! -v WALLPAPER_PATHS ]]; then
	throw "Argument Error" "No media paths supplied!"
fi

function cleanup {
	rm -f "$MEDIA_SYMLINK"
	rm -f "$SOCKET"
	pkill -f "mpv --title=wallpaper-mpv" || true
	# make cursor visible after mpv messes with it
	tput cnorm
	printf "\e[1;34m%s\e[0m\n" "Script and MPV closed!"
	exit 0
}; trap cleanup EXIT
if pkill -f "mpv --title=wallpaper-mpv"; then
	printf "Closed previous instance of this script!\n"
	sleep 1
fi

mpv --title="wallpaper-mpv" --input-ipc-server="$SOCKET"\
$mpv_args --include="$MPV_CONF" -- &

if ! waitsocket "$SOCKET"; then
	throw "Socket error" "MPV's socket failed to open!"
fi

#|open one socat instance that sends and receives
#|messages with its own file descriptors; compare to
#|socat pty,raw,echo=0,link="$SOCAT_PTY" UNIX-CONNECT:"$SOCKET" &
#|waitpath... exec 3<>"$SOCAT_PTY"
coproc IPC { socat UNIX-CONNECT:"$SOCKET" - ; }

#|Causes two messages to fire on file change.
echo '{command=["observe_property",1,"playlist-pos"]}' >&${IPC[1]}
#| {"data":{"playlist_entry_id":N},"request_id":0,"error":"success"}
#| {"event":"property-change","id":1,"name":"playlist-pos","data":N}
#| The playlist pos will reliably fire as "data":-1 when a file
#| ends with nothing else looping or in the playlist.
#| This is caught with *playlist-pos*-1* to avoid
#| dependencies for parsing JSON.

# https://mpv.io/manual/master/#list-of-input-commands
# https://mpv.io/manual/master/#json-ipc
function plaympv {
	local wallpaper="$1"
	# use symlink to avoid json parsing/jq dependency
	rm -f "$MEDIA_SYMLINK"
	ln -sr "$wallpaper" "$MEDIA_SYMLINK"
	printf "\e[36m%s\e[0m\n" "MPV is playing ${wallpaper/#"$HOME"/"~"}"
	echo "{command=[\"loadfile\",\"$MEDIA_SYMLINK\"]}" >&${IPC[1]}
}

declare -ir RANGE=(${#WALLPAPER_PATHS[@]}-1)
declare -i random
while read -r event <&"${IPC[0]}"; do
	case "$event" in
		*'"reason":"error"'*)
			#| generic errors, misses nonfatal errors
			#| like ffmpeg or seeking
			#| should probably never actually fire
			throw "Fatal Error" "$event"
		;;
		*playlist-pos*-1*)
			#| Fires when mpv is created or there are no
			#| more files to play. It is more
			#| robust than end-file as it accounts for
			#| playlist files; it does not depend on the
			#| idle or tick events either, which are deprecated.
		;;
		*) continue;;
	esac
	random=$(shuf -n 1 -i 0-$RANGE)
	plaympv "${WALLPAPER_PATHS[$random]}"
done
stty echo
