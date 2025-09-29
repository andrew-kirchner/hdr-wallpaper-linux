# pass the result of getopt to parseoptions
declare -A FLAGS=()
declare -A OPTARG_MAP=()
declare -a POSITIONALS=()
function parseoptions {
	local GETOPT="$1"
	#|I have not found a practical use for new lines here,
	#|so for now it is cleaner and more secure to ban them
	#|you can still put newlines inbetween your flags and
	#|stuff to format them as getopt cleans it
	if [[ "$GETOPT" == *$'\n'* ]]; then
		echo "No newlines in options!">&2
		return 1
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

	local SHORTLONG="$(grep -Po -- "^.*?(?= --(?:$| X))" <<< "$sanitized")"
	if grep -Pq -- " (-++[a-z-]+).*\1" <<< "$SHORTLONG"; then
		echo "Duplicate Options! $SHORTLONG">&2
		return 1
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
function isflagpresent {
	local longhand="$1"
	local shorthand="${2:-}"
	[[ -v FLAGS["--$longhand"] || -v FLAGS["-$shorthand"] ]]
}
function getOPTARG {
	local longhand="$1"
	local regex="$2"
	local shorthand="${3:-}"
	local optvalue="${OPTARG_MAP["--$longhand"]:-}"
	if [[ -z "$optvalue" && -n "$shorthand" ]]; then
		if (( ${#shorthand} == 1 )); then
			optvalue="${OPTARG_MAP["-$shorthand"]:-}"
		else
			optvalue="${OPTARG_MAP["--$shorthand"]:-}"
		fi
	fi
	if [[ -z "$optvalue" ]]; then
		echo ""
		return 0
	fi
	optvalue="${optvalue,,}"
	if ! grep -Pq "$regex" <<< "$optvalue"; then
		return 1
	fi
	echo "$optvalue"
}
