#!/usr/bin/env bash
set -euo pipefail
declare -a DEFAULT_PATHS=("$HOME/Videos" "$HOME/Pictures/pikmin")
readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly MPV_CONF="$SCRIPT_DIR/mpv.conf"
readonly ITM_CONF="$SCRIPT_DIR/inversetonemapping.conf"
readonly WALLPAPER_KWINRULE="$SCRIPT_DIR/wallpaper.kwinrule"
readonly INSTALL_NAME="hdr"
readonly INSTALL_DIR="$HOME/.local/bin"
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
	ln -s "$SCRIPT_PATH" "$INSTALL_DIR/$INSTALL_NAME"
	chmod +x "$INSTALL_DIR/$INSTALL_NAME"
	printf "Script can now be called with name $INSTALL_NAME from \$PATH!\n"
fi

readonly MEDIA_SYMLINK="/tmp/HDRpaper"
readonly SOCKET="/tmp/HDRsocket"

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
    -i, --itm ?= all
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


#|system level rules:
#|/etc/xdg/kwinrulesrc
#|personal rules
#|~/.config/kwinrulesrc
function applykdewindowrule {
	local FILE_KWINRULE="$1"
	local RULE_NAME="$(grep -Po "(?<=\[).+?(?=\])" "$FILE_KWINRULE")"
	if [[ "$RULE_NAME" == *$'\n'* ]]; then
		throw "config error" "$FILE_KWINRULE has multiple groups!"
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
			--key rules "${SYSTEM_LEVEL_RULES:+$SYSTEM_LEVEL_RULES,}HDRpaper"
		if ! command -v qdbus >/dev/null; then
			throw "kwin error" "qdbus is missing! go apply window rule manually"
		fi
		qdbus org.kde.KWin /KWin reconfigure
		return 0
	fi
	local WINDOW_RULES="$(
		kreadconfig6 --file kwinrulesrc --group General --key rules
	)"
	if [[ "$WINDOW_RULES" =~ (^|,)HDRpaper(,|$) ]]; then
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
		--key rules "${WINDOW_RULES:+$WINDOW_RULES,}HDRpaper"
	qdbus org.kde.KWin /KWin reconfigure
}

if ! command -v kwriteconfig6 >/dev/null; then
	printf "kwriteconfig6 not found! It seems you are not on Plasma,
the script itself will run normally but you must (for now)
add your own window rule equivalent in settings or a plugin
to put mpv in the background and prevent user input\n"
else
	applykdewindowrule "$WALLPAPER_KWINRULE"
fi

SUBCOMMANDS="HELP,H,QUIT,Q,SKIP,S,REPEAT,R,OSD,O,AUDIO,A,ITM,I"
unset subcommand
if [[ -v 1 ]]; then
	if [[ ",$SUBCOMMANDS," == *",${1^^},"* ]]; then
		subcommand="${1,,}"
		shift
	fi
fi

#|modular option parser
#|fun learning exercise :)
#|would be in a separate file if this was a larger script
#|try to break it i dare you
declare -A FLAGS=()
declare -A OPTARG_MAP=()
declare -a POSITIONALS=()
function parseoptions {
	# quit if getopt throws an error with nowhere to log it
	[[ "$?" != 0  ]] && ! tty --quiet && throw "Argument error!" \
	"Invalid argument was supplied without a terminal!"

	local GETOPT="$1"
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

	local SHORTLONG=$(grep -Po -- "^.*?(?= --(?:$| X))" <<< "$sanitized")

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
		OPTARG_MAP["$key"]="$value"
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

readonly SHORTOPTIONS="hls:i:"
readonly LONGOPTIONS=\
"help,loop,no-config,only-images,only-videos,sort:,itm:"
parseoptions "$(getopt -o "$SHORTOPTIONS" -l "$LONGOPTIONS" -- "$@")"
# declare -p FLAGS
# declare -p OPTARG_MAP
# declare -p POSITIONALS
function isflagpresent {
	local longhand="$1"
	local shorthand="${2:-}"
	[[ -v FLAGS["--$longhand"] || -v FLAGS["-$shorthand"] ]]
}
if isflagpresent help h; then
	helptext
	exit 0
fi

if [[ -v subcommand ]]; then
	case "$subcommand" in
		help|h)
			helptext
		;;
		quit|q)
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
			'{command=["set_property","audio","auto"]}'
		;;
		itm|i)
			#|the user-data property cant be used because
			#|the profile-restore functionality just breaks
			#|for target-prim you can try bt.709
			#|instead of auto which is maybe oversaturated p3
			socat - "$SOCKET" <<< \
			'{command=["cycle-values","target-prim","auto","bt.2020"]}'
			socat - "$SOCKET" <<< \
			'{command=["cycle-values","target-trc","auto","pq"]}'
			socat - "$SOCKET" <<< \
			'{command=["cycle-values","inverse-tone-mapping","yes","no"]}'
		;;
	esac
	exit 0
fi

declare -a preset_options=()
unset FORCE_LOOP ONLY_IMAGES ONLY_VIDEOS
if isflagpresent loop l; then
	preset_options+=("--loop=inf --image-display-duration=inf")
	readonly FORCE_LOOP=0
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

if [[ ! -v POSITIONALS ]]; then
	POSITIONALS=("${DEFAULT_PATHS[@]}")
fi

function getOPTARG {
	local longhand="$1"
	local regex="$2"
	local shorthand="${3:-}"
	local optvalue="${OPTARG_MAP["--$longhand"]:-}"
	if [[ -z "$optvalue" && -n "$shorthand" ]]; then
		optvalue="${OPTARG_MAP["-$shorthand"]:-}"
	fi
	if [[ -z "$optvalue" ]]; then
		echo ""
		return 0
	fi
	optvalue="${optvalue,,}"
	if ! grep -Pq "$regex" <<< "$optvalue"; then
		throw "Argument error!" \
		"Invalid --$longhand! $optvalue"
	fi
	echo "$optvalue"
}
SORT_METHOD="$(
	getOPTARG sort "proportional|random|randarg|alphabetical|newest|none" s
)"
SORT_METHOD="${SORT_METHOD:-proportional}"

declare -a WALLPAPER_PATHS=()
declare -A IMAGE_MAP=()
declare -A VIDEO_MAP=()
while read -r -d $'\0' path; do
	mime_type="$(file -b --mime-type "$path")"
	if [[ "$path" == *$'\n'* &&
		( "$mime_type" == image/* || "$mime_type" == video/*)
	]]; then
		# would mess up coproc IPC because it's newline delimited
		throw "Newline Error" "$path"
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

unset AVERAGE_DURATION
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
	local total_duration="0.0"
	local inverse_weight
	local total_weight="0.0"
	while read -t 5 response <&"${RELAY[0]}"; do
		duration="$(grep -Po "[\d.]+$" <<< "$response")"
		total_duration="$(
			awk "BEGIN{print $total_duration+$duration}"
		)"
		inverse_weight="$(
			awk "BEGIN{print 1/$duration}"
		)"
		total_weight="$(
			awk "BEGIN{print $total_weight+$inverse_weight}"
		)"

		path="${response% $duration}"
		WALLPAPER_PATHS+=("$path")
		VIDEO_MAP["$path"]="$inverse_weight"
		if (( --videos_remaining == 0 )); then
			local SUCCESS=0
			break
		fi
	done
	if [[ ! -v SUCCESS ]]; then
		throw "Timeout error" "ffprobe failed! check terminal or try --sort=random"
	fi
	local probability
	for path in "${!VIDEO_MAP[@]}"; do
		inverse_weight="${VIDEO_MAP["$path"]}"
		probability="$(
			awk "BEGIN{print $inverse_weight/$total_weight}"
		)"
		VIDEO_MAP["$path"]="$probability"
	done
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
	printf "%s %s\n" "$video" "$duration" >&3
}

function pickpickcarrotmethod {
	case "$SORT_METHOD" in
		proportional) echo "$(pickproportional)";;
		random) echo "$(pickrandom)";;
	esac
}
function pickproportional {
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
	local -i random=$(shuf -n 1 -i 0-$RANGE)
	echo "${WALLPAPER_PATHS[$random]}"
}

if [[ "$SORT_METHOD" == proportional && ${#VIDEO_MAP[@]} -eq 0 ]]; then
	# no videos so dont worry about probing them
	SORT_METHOD=random
fi
case "$SORT_METHOD" in
	proportional)
		probepositionals
		if [[ ${#IMAGE_MAP[@]} -ne 0 && ! -v FORCE_LOOP ]]; then
			preset_options+=("--image-display-duration=$AVERAGE_DURATION")
			printf "\e[34m%s\e[0m\n" \
"Wallpapers from ${#IMAGE_MAP[@]} static image files will play for
$AVERAGE_DURATION seconds on average, the mean of ${#VIDEO_MAP[@]} videos passed."
		fi
	;;
	random)
		declare -ir RANGE=(${#WALLPAPER_PATHS[@]}-1)
		declare -i last_index=-1
		declare -i random #shuf -n 1 -i 0-$RANGE
	;;
	*) throw "unimplemented" "$SORT_METHOD";;
esac
if [[ -v FORCE_LOOP ]]; then
	printf "\e[34m%s\e[0m\n" \
"${#IMAGE_MAP[@]} images and ${#VIDEO_MAP[@]} videos will play
indefinitely until SKIP is called!"
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

mpv --title=wallpaper-mpv --input-ipc-server="$SOCKET" \
	--include="$MPV_CONF" ${preset_options[@]} -- &
if ! waitsocket "$SOCKET"; then
	throw "Socket error" "MPV's socket failed to open!"
fi
case "$(getOPTARG itm "all|image|video|none" i)" in
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

#|open one socat instance that sends and receives
#|messages with its own file descriptors; compare to
#|socat pty,raw,echo=0,link="$SOCAT_PTY" UNIX-CONNECT:"$SOCKET" &
#|waitpath... exec 3<>"$SOCAT_PTY"
coproc IPC { socat UNIX-CONNECT:"$SOCKET" - ; }

#|use to detect no more media files to play
#|accounts for when more files are queued like
#|with REPEAT, LOOP, or --drag-and-drop=append
echo '{command=["observe_property",1,"playlist-pos"]}' >&${IPC[1]}

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

declare -a path_history=()
declare -i HISTORY_LENGTH=4

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
stty echo
