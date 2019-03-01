#/bin/bash

DEFAULT_DEV="/dev/dvd"
ENCODING_OPTIONS="-e x264 -q 22 B 64 -X 480 -O"
# AUDIO_SUBS="--all-audio --all-subtitles"
AUDIO_SUBS="--audio-lang-list deu,eng --all-subtitles"

function print_help {
    cat <<USAGE
usage: ${0} [OPTIONS]

Options:
    -d,--device DEV     The dvd device
    -t,--title WORD     The title, which is used for the exported files.
    -l,--location PATH  A directory where the files are being saved. It is created
                        if it does not already exist.

Return-Values:
    1                   Parameter-Error: unknown or additional parameter
    2                   Source-Error: unknown or wrong source
    3                   Name-Error: no output name was specified
    4                   Location-Error: no save location was specified
    5                   Zenity-Error: zenity is not installed
    6                   HandBrakeCLI-Error: HandBrakeCLI is not installed or has the wrong version

Examples:
    ${0} -d ${DEFAULT_DEV}
    ${0} -d ${DEFAULT_DEV} -t "Stargate s01 Disk2"
    ${0} -d ${DEFAULT_DEV} -t "Stargate s01 Disk2" -l "${HOME}/Videos/Stargate/Season 1/"
USAGE
}

function check_installed_sw {
    check_handbrake_version
    if [ -z $(which zenity) ]; then
        error "Zenity is not installed. It is used to at least choose the titles to extract."
        exit 5
    fi
    if [ -z $(which HandBrakeCLI) ]; then
        error "HandBrakeCLI is not installed. It is used to extract the content of the DVD"
        exit 6
    fi
}

function check_handbrake_version {
    version=$(HandBrakeCLI --version 2>&1 | grep HandBrake | grep -v has | awk '{print $2}')
    version_arr=($(echo ${version} | sed 's/\./ /g'))

    if [ $(printf '%d\n' ${version_arr[0]}) -lt 1 ]; then
        version_error $version
    else
        if [ $(printf '%d\n' ${version_arr[1]}) -le 0 ]; then
            if [ $(printf '%d\n' ${version_arr[2]}) -lt 4 ]; then
                version_error $version
            fi
        fi
    fi
}

function version_error {
    error "The version of HandBrakeCLI is not >= 1.0.4. It is ${1}"
    exit 6
}

function parse_options {
    check_installed_sw
    while (( $# > 0 )); do
		case "$1" in
			-d|--device)
				SRC="$2"
				shift 2
				;;
			-t|--title)
                TITLE="$2"
				shift 2
				;;
            -l|--location)
                SAVE_LOCATION="$2"
                shift 2
                ;;
			-h|--help)
				print_help
				exit
				;;
            -*)
				error "unknown option $1"
				exit 1
				;;
			*)
				if [[ -n "$title" ]]; then
					error "additional argument $1"
					exit 1
				fi

				title="$1"
				shift
				;;
		esac
	done

	if [ -z ${SRC} -o ! -e ${SRC} ]; then
        get_source
	fi

    if [[ -z "$SAVE_LOCATION" ]]; then
        set_save_location
    fi

    if [[ -z "$TITLE" ]]; then
        set_output_name
    fi
}

function error()
{
	if [[ -t 1 ]]; then
		echo -e "\x1b[1m\x1b[31m!!!\x1b[0m \x1b[1m$1 \x1b[1m\x1b[31m!!!\x1b[0m" >&2
	else
		echo "!!! $1 !!!" >&2
	fi
}

# get the DVD-source
function get_source {
    SRC="$(zenity --file-selection --title 'Choose source' --filename=${DEFAULT_DEV} 2> /dev/null)"

    if [[ -z ${SRC} ]]; then
        error "You did not specify a source. Exiting..."
        exit 2
    fi
}

function set_output_name {
    TITLE="$(zenity --entry --title 'Choose title. Used for the filenames.' 2> /dev/null)"

    if [[ ${TITLE} == "" ]]; then
        error "You did not specify a title. Exiting..."
        exit 3
    fi
}

function set_save_location {
    default_save_location="${HOME}/Videos/"
    SAVE_LOCATION="$(zenity --file-selection --title 'Choose save location' --filename=${default_save_location} --directory 2> /dev/null)"

    if [[ ${SAVE_LOCATION} == "" ]]; then
        error "You did not specify a location to save. Exiting..."
        exit 4
    fi

    # Maybe for further use
    FILE_LIST=$(ls "${SAVE_LOCATION}")
}

function get_title_list {
    if [[ -z "$SRC" ]]; then
        error ""
    fi

    TITLE_INDECES=($(HandBrakeCLI --input ${SRC} -t 0 --scan 2>&1 | grep "+ title " | awk '{print $3}' | sed s/://))

    # To may implement progress bar
    # STEPS=$(expr 100 / ${#TITLE_INDECES[@]})

    DURATION=()

    for i in ${TITLE_INDECES[@]}
    do
        DURATION+=(${i})
        DURATION+=($(HandBrakeCLI --input /dev/sr0 -t ${i} --scan 2>&1 | grep "+ duration: " | awk '{print $3}'))
    done
}

function choose_titles {
    if [[ -z "$TITLE_INDECES" ]]; then
        get_title_list
    fi
    CHOSEN_TITLES=$(zenity --title "Choose title to extract" --list --multiple --column "verfügbare Titel" --column "Laufzeit" ${DURATION[@]} 2> /dev/null)

    if [[ ${CHOSEN_TITLES} == "" ]]; then
        error "You did not specify any title. Exiting..."
        exit 5
    fi
    USE_TITLES=($(echo "${CHOSEN_TITLES}" | sed 's/|/ /g'))
}

function start_ripping {
    if [ ! -d "$SAVE_LOCATION" ]; then
        echo creating folder "${SAVE_LOCATION}"
        mkdir -p "${SAVE_LOCATION}"
    fi
    if [[ -z $USE_TITLES ]]; then
        choose_titles
    fi
    for i in ${USE_TITLES[@]}
    do
        filename="${SAVE_LOCATION}/${TITLE}_${i}.mp4"
        echo Generating file: "${filename}"
        # HandBrakeCLI -2 -T --input ${SRC} --title ${i} --preset Normal --output "${filename}" ${AUDIO_SUBS}
        HandBrakeCLI -2 -T -i ${SRC} -o "${filename}" --title ${i} ${ENCODING_OPTIONS} ${AUDIO_SUBS}
    done
}

function eject_disc() {
    if zenity --question --title "Auswerfen?" --text "Eject DVD?"  2> /dev/null;
        then eject;
    fi
}

parse_options "$@"
start_ripping
eject_disc
