#!/usr/bin/env bash
# set -x # to see everything
set -euo pipefail
shopt -s extglob

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
source "$SCRIPT_DIR/applykdewindowrule.sh"
source "$SCRIPT_DIR/parseoptions.sh"
readonly MPV_CONF="$SCRIPT_DIR/mpv.conf"
readonly ITM_CONF="$SCRIPT_DIR/inversetonemapping.conf"
readonly WALLPAPER_KWINRULE="$SCRIPT_DIR/wallpaper.kwinrule"


declare -a DEFAULT_PATHS=("$(xdg-user-dir PICTURES)" "$(xdg-user-dir VIDEOS)")
readonly INSTALL_NAME="hdr" # what to type in terminal
readonly INSTALL_DIR="$HOME/.local/bin" # somewhere in $PATH
readonly SOCKET="/tmp/wpmpvsocket"
if ! command -v mpv >/dev/null; then
	printf "The program \e[1mmpv\e[0m was not found in \$PATH!
If it is installed as a flatpak, you need
to either reinstall it or make an alias to
\e[1mflatpak run io.mpv.Mpv\e[0m in your terminal.\n"
	exit 1
fi
if ! command -v socat >/dev/null; then
	printf "The program \e[1msocat\e[0m is not installed!
Install it with your package manager, if you are using
an immutable distribution like NixOS or Bazzite this should
probably be installed anyways but you must circumvent this\n"
	exit 1
fi
if [[ ! -s "$INSTALL_DIR/$INSTALL_NAME" ]]; then
	mkdir -p "$INSTALL_DIR"
	ln -sr "$SCRIPT_PATH" "$INSTALL_DIR/$INSTALL_NAME"
	chmod +x "$INSTALL_DIR/$INSTALL_NAME"
	printf "Script can now be called with name $INSTALL_NAME from \$PATH!\n"
fi

function helptext {
	printf \
"Usage: wallpaper.sh [subcommand]? or [options] [mediapath1 mediapath2 ...]
Play media file(s) as desktop wallpapers.\e[033m
==|==========================================================================|==
\e[0mSubcommands (e.g. git pull, git commit)
These one word subcommands are used to show information or possibly
modify the current instance instead of creating a new one.

    HELP    Display me then exit
    QUIT    Force close mpv and script, throws if not found
    SKIP    End the current media file and play the next one
              as per REPEAT then --sort
    REPEAT  Loop the current media file once once it ends;
              throws if file is set to loop forever
    OSD     Toggle OSD, or more specifically the ability
              for the window to receive pointer events.
              Will also capture exclusively mpv shortcuts!
    AUDIO   Enable audio for the current instance. Audio
              is not just muted but disabled by default!
    ITM     Toggle inverse tone mapping for SDR media.
              Test the differnece for both images and videos!\e[035m
==|==========================================================================|==
\e[0mBoolean Flags [ -m --mode ] ?= false
These options are used only on initialization of a new instance.

    -l, --loop      Loop media indefinitely until SKIP is called.
    -t, --toast     Show a short toast of the filename in the background.
    --no-config     Alias for mpv option, do not use personal config.
    --only-images   Ignore videos when looking for media files.
    --only-videos   Ignore images when looking for media files.

Arguments with values [ -k value --key value --key=value ] ?= default
These options require a value and are only passed on a new instance.

    -s, --sort ?= proportional
    Control the order in which any media
    files that are found are played.
      =proportional     Pick media inversely proportional to its respective
                          duration, such that each file would approach being
                          on screen the same amount of time. Images are given
                          the duration of the average of all videos! Falls
                          back to random if no videos are supplied.
      =random           Pick all media in paths with uniform distribution
      =randarg          Pick a random top level mediapath then file each time
      =alphabetical     Play in order based on basename of all media files
      =newest           Play files in order of the date last moved
      =none             Play in whatever order supplied by the find command
    --itm ?= all
    Choose what type of SDR media inverse tone mapping upto HDR is applied to.
      =all             Use bt.2446a for images and videos. Set target-peak!
      =only-images     Use bt.2446a for images only. Videos unchanged
      =only-videos     Use bt.2446a for videos only. Images unchanged
      =none            Disable itm always, displaying SDR in SDR or P3
\e[34m
==|==========================================================================|==
\e[0m
Repository page: <https://gitlab.com/andrewkirchner/HDRpaper>\n"
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
function rand {
	od -An -N2 -i /dev/urandom | awk "{print (\$1 % 65536)/65535 }"
}

applykdewindowrule "$WALLPAPER_KWINRULE"

# BEGIN command line arguments
SUBCOMMANDS="HELP,H,QUIT,Q,SKIP,S,REPEAT,R,OSD,O,AUDIO,A,ITM,I,DEBUG,D"
unset subcommand
if [[ -v 1 ]]; then
	if [[ ",$SUBCOMMANDS," == *",${1^^},"* ]]; then
		subcommand="${1,,}"
		shift
	fi
fi

readonly SHORTOPTIONS="hlts:"
readonly LONGOPTIONS=\
"help,loop,toast,no-config,only-images,only-videos,sort:,itm:"
raw_getopt="$(getopt -o "$SHORTOPTIONS" -l "$LONGOPTIONS" -- "$@")"
if [[ $? != 0 ]] && ! tty --quiet; then
	throw "getopt Error!" "Invalid parameters, run in terminal!"
fi
parseoptions "$raw_getopt"
# declare -p FLAGS
# declare -p OPTARG_MAP
# declare -p POSITIONALS

if isflagpresent help h; then
	helptext
	exit 0
fi

declare -a preset_options=()
unset FORCE_LOOP DO_TOAST ONLY_IMAGES ONLY_VIDEOS sort_method itm
if [[ -v subcommand ]]; then
	case "$subcommand" in
		help|h)
			helptext
		;;
		quit|q)
			if pkill -f "mpv --title=wallpaper-mpv"; then
				rm -f "$SOCKET"
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
			'{command=["set_property","audio","auto"]}'
		;;
		itm|i)
			noimage="$(socat - "$SOCKET" <<< \
				'{command=["get_property","user-data/noimage"]}'
			)"
			novideo="$(socat - "$SOCKET" <<< \
				'{command=["get_property","user-data/novideo"]}'
			)"
			invert=$([[ "$noimage" == *true* ]] || printf true)
			noimage=${invert:-false}
			invert=$([[ "$novideo" == *true* ]] || printf true)
			novideo=${invert:-false}
			socat - "$SOCKET" <<< \
			"{command=[\"set_property\",\"user-data/noimage\",$noimage]}"
			socat - "$SOCKET" <<< \
			"{command=[\"set_property\",\"user-data/novideo\",$novideo]}"
		;;
		debug|d)
			socat - "$SOCKET" <<< \
			'{command=["script-binding","stats/display-stats-toggle"]}'
		;;
	esac
	exit 0
fi

if [[ ${#FLAGS[@]} -ne 0 ]]; then
	if isflagpresent loop l; then
		preset_options+=("--loop=inf --image-display-duration=inf")
		readonly FORCE_LOOP=0
	fi
	if isflagpresent toast t; then
		readonly DO_TOAST=0
	fi
	if isflagpresent no-config; then
		preset_options+=("--no-config")
	fi
	if isflagpresent only-images; then
		readonly ONLY_IMAGES=0
	fi
	if isflagpresent only-videos; then
		readonly ONLY_VIDEOS=0
	fi
fi
sort_method="$(
	getOPTARG sort "proportional|random|randarg|alphabetical|newest|none" s
)"
sort_method="${sort_method:-proportional}"
itm="$(getOPTARG itm "all|image|video|none")"
if [[ ! -v POSITIONALS ]]; then
	POSITIONALS=("${DEFAULT_PATHS[@]}")
fi
# END

# BEGIN find media files
# put all media in one array regardless of relative location
declare -a WALLPAPER_PATHS=()
declare -A IMAGE_MAP=()
declare -A VIDEO_MAP=()
while read -r -d $'\0' path; do
	mime_type="$(file -b --mime-type "$path")"
	if [[ "$path" == *@($'\n'|$'\r'|$'\b'|$'\f')* &&
		( "$mime_type" == image/* || "$mime_type" == video/*)
	]]; then
		#|would mess up coproc IPC because it's newline delimited
		#|also just weird and useless
		throw "Newline/Escape Character Error" "$path"
	fi
	case "$mime_type" in
		image/*)
			if [[ -v ONLY_VIDEOS ]]; then continue; fi
			WALLPAPER_PATHS+=("$path")
			IMAGE_MAP["$path"]=1
		;;
		video/*)
			if [[ -v ONLY_IMAGES ]]; then continue; fi
			WALLPAPER_PATHS+=("$path")
			VIDEO_MAP["$path"]=0
		;;
	esac
done < <(find "${POSITIONALS[@]}" -type f -print0)
unset path
unset mime_type


if [[ ! -v WALLPAPER_PATHS ]]; then
	throw "Argument Error" "No valid media paths supplied!"
fi
if [[ -v FORCE_LOOP ]]; then
	printf "\e[34m%s\e[0m\n" \
"${#IMAGE_MAP[@]} images and ${#VIDEO_MAP[@]} videos will play
indefinitely until SKIP is called!"
fi
# END

unset AVERAGE_DURATION TOTAL_DURATION
#|complex, asynchronously calls and aggregates
#|ffprobe on every video
function probepositionals {
	coproc RELAY {
		while read line; do
			printf "%s\n" "$line"
		done
	}
	exec 3>&"${RELAY[1]}" # keeps relay open
	local path
	for path in "${!VIDEO_MAP[@]}"; do
		probevideo "$path" &
	done

	local -i videos_remaining="${#VIDEO_MAP[@]}"
	local response
	local duration
	local -i path_index
	local total_duration="0.0"
	while read -t 5 response <&"${RELAY[0]}"; do
		# coproc sends in format "index duration"
		duration="$(grep -Po "[\d.]+$" <<< "$response")"
		path_index="$(grep -Po "^\d+" <<< "$response")"
		path="${WALLPAPER_PATHS[$path_index]}"
		VIDEO_MAP["$path"]="$duration"
		total_duration="$(
			awk "BEGIN{print $total_duration+$duration}"
		)"
		if (( --videos_remaining == 0 )); then
			local SUCCESS=0
			break
		fi
	done
	if [[ ! -v SUCCESS ]]; then
		throw "Timeout error" "ffprobe failed! check terminal or try --sort=random"
	fi
	declare -g TOTAL_DURATION="$total_duration"
	declare -g AVERAGE_DURATION="$(
		awk "BEGIN{print $total_duration/${#VIDEO_MAP[@]}}"
	)"
	kill $RELAY_PID
}
function probevideo {
	local video="$1"
	local duration="$(ffprobe -v error \
		-show_entries format=duration \
		-of csv="p=0" \
		"$video"
	)"
	#|inefficient but simple way to
	#|pack the path without escaping filename
	local -i index=-1
	for path in "${WALLPAPER_PATHS[@]}"; do
		index="$((index + 1))"
 		#((index++)) is buggy
		if [[ "$path" == "$video" ]]; then
			break
		fi
	done
	printf "$index $duration\n" >&3
}

function weighvideos {
	local duration
	local awk_durations=""
	#|abstract weird path string away
	#|from awk so there can be just 1 awk call
	declare -a ordered_videos=()
	for video in "${!VIDEO_MAP[@]}"; do
		ordered_videos+=("$video")
		duration="${VIDEO_MAP["$video"]}"
		awk_durations+=$duration+$'\n'
	done
	local normalized_weights="$(awk '
		BEGIN { total = 0.0; }
		{
			#|NR starts at 1 but awk arrays
			#|are associative so whatever
			inverse_durations[NR] = 1 / $1;
			total += inverse_durations[NR];
		}
		END {
			for (i = 1; i <= NR; i++) {
				normalized = inverse_durations[i] / total;
				printf "%.10f\n", normalized
			}
		}
	' <<< "${awk_durations%$'\n'}")"
	local -i index=0
	while read normalized; do
		VIDEO_MAP["${ordered_videos[$index]}"]="$normalized"
		index=$((index + 1))
	done <<< "$normalized_weights"
}



function pickpickcarrotmethod {
	case "$sort_method" in
		proportional) echo "$(pickproportional)";;
		random) echo "$(pickrandom)";;
	esac
}
#|uses average duration
#|or user set -i
function pickproportional {
	#|by assuming image weight
	#|is just the average you dont actually
	#|need to do math with their duration at all
	if awk "BEGIN{
		IMAGE_TOTAL = ${#IMAGE_MAP[@]}
		if (${#IMAGE_MAP[@]} == 0) exit 1;
		MEDIA_TOTAL = IMAGE_TOTAL + ${#VIDEO_MAP[@]}
		exit( IMAGE_TOTAL/MEDIA_TOTAL > $(rand) )
	}"; then
		#|consider the duration weight of all images
		#|at once and then just pick a random one
		local -i random_image=$(shuf -n 1 -i 1-${#IMAGE_MAP[@]})
		local -i key_index=0
		for path in "${!IMAGE_MAP[@]}"; do
			if (( ++key_index == $random_image )); then
				echo "$path"
				return 0
			fi
		done
		throw "impossible" "uh oh"
	fi
	local random="$(rand)"
	local probability_sum="0.0"
	for path in "${!VIDEO_MAP[@]}"; do
		probability_sum="$(
			awk "BEGIN{print $probability_sum+${VIDEO_MAP["$path"]}}"
		)"
		if ! awk "BEGIN{exit($probability_sum >= $random)}"; then
			echo "$path"
			return 0
		fi
	done
	throw "impossible" "uh oh"
}

function pickrandom {
	local -i random=$(shuf -n 1 -i 0-$((${#WALLPAPER_PATHS[@]}-1)))
	echo "${WALLPAPER_PATHS[$random]}"
}

if [[ "$sort_method" == proportional && ${#VIDEO_MAP[@]} -eq 0 ]]; then
	#|if there are no videos then there is
	#|no point in finding relative duration
	sort_method=random
fi
case "$sort_method" in
	proportional)
		probepositionals
		weighvideos
		if [[ ! -v FORCE_LOOP && ${#IMAGE_MAP[@]} -ne 0 ]]; then
			preset_options+=("--image-display-duration=$AVERAGE_DURATION")
			printf "\e[34m%s\e[0m\n" \
"Wallpapers from ${#IMAGE_MAP[@]} static image files will play for
$AVERAGE_DURATION seconds on average, the mean of ${#VIDEO_MAP[@]} videos passed."
		fi
	;;
	random)
		printf "\e[34m%s\e[0m\n" \
"Wallpapers will be randomly played from ${#IMAGE_MAP[@]} images and ${#VIDEO_MAP[@]} videos passed."
		declare -ir RANGE=(${#WALLPAPER_PATHS[@]}-1)
		declare -i last_index=-1
		declare -i random #shuf -n 1 -i 0-$RANGE
	;;
	*) throw "unimplemented --sort" "$sort_method";;
esac

# BEGIN run mpv
function cleanup {
	rm -f "$SOCKET"
	pkill -f "mpv --title=wallpaper-mpv" || true
	exit 0
}; trap cleanup EXIT
if pkill -f "mpv --title=wallpaper-mpv"; then
	printf "Closed previous instance of this script!\n"
	sleep 1
fi
mpv --title=wallpaper-mpv --input-ipc-server="$SOCKET" \
	--include="$MPV_CONF" ${preset_options[@]} -- &
if ! waitsocket "$SOCKET"; then
	throw "Socket error" "MPV's socket failed to open!"
fi
#|open one socat instance that sends and receives
#|messages with its own file descriptors; compare to
#|socat pty,raw,echo=0,link="$SOCAT_PTY" UNIX-CONNECT:"$SOCKET" &
#|waitpath... exec 3<>"$SOCAT_PTY"
coproc IPC { socat UNIX-CONNECT:"$SOCKET" - ; }
#|use to detect no more media files to play
#|accounts for when more files are queued like
#|with REPEAT, LOOP, or --drag-and-drop=append
echo '{command=["observe_property",1,"playlist-pos"]}' >&${IPC[1]}

case "$itm" in
	all);; # dont disable anything
	*image*|*none*)
		socat - "$SOCKET" <<< \
		'{command=["set_property","user-data/novideo",true]}'
	;;&
	*video*|*none*)
		socat - "$SOCKET" <<< \
		'{command=["set_property","user-data/noimage",true]}'
	;;
esac
# END

function escapejson {
	#|avoids jq dependency, completely valid here
	#|for file paths where \n\r\b\f are banned
	local arbitrary="$1"
	arbitrary="${arbitrary//\\/\\\\}" # backslashes
	arbitrary="${arbitrary//\"/\\\"}"
	echo "$arbitrary"
}
# https://mpv.io/manual/master/#list-of-input-commands
# https://mpv.io/manual/master/#json-ipc
declare -ir TOAST_TIME=5000
function plaympv {
	local wallpaper="$1"
	local escaped="$(escapejson "$wallpaper")"
	echo "{command=[\"loadfile\",\"$escaped\"]}" >&${IPC[1]}
	printf "\e[36m%s\e[0m\n" "MPV is playing ${wallpaper/#"$HOME"/"~"}"
	if [[ -v DO_TOAST ]]; then
		echo "{command=[\"show-text\"\
		,\"${escaped/#"$HOME"/"~"}\",$TOAST_TIME]}">&${IPC[1]}
	fi
}
declare -a path_history=()
declare -ir HISTORY_LENGTH=6
while read -r event <&${IPC[0]}; do
	# use simple matching to avoid jq dependency
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

	if (( ${#WALLPAPER_PATHS[@]} <= HISTORY_LENGTH )); then
		plaympv "$(pickpickcarrotmethod)"
		continue
	fi
	next_file=""
	while grep -Fq "$next_file" <<< "${path_history[@]}"; do
		next_file="$(pickpickcarrotmethod)"
	done
	path_history+=("$next_file")
	if (( ${#path_history[@]} > HISTORY_LENGTH )); then
		path_history=("${path_history[@]:1}")
	fi
	plaympv "$next_file"
done
