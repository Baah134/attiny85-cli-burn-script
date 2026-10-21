#!/usr/bin/env bash
# Compile and program through burn_basic.sh; optionally monitor a single burn.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1
BURN_ARGS=()
OPEN_MONITOR=false
SINGLE_SHOT=false
PORT=""

show_help() {
    echo "Usage: bash ./burn.sh [-f <sketch|folder|hex>] [-c 1|8|16] [-p <port>] [-s] [-m]"
    echo "  -m  Open the 19200-baud monitor after a successful burn; requires -s and -p."
    echo "Other options are passed to burn_basic.sh. Run bash ./burn_basic.sh -h for details."
}

while getopts "f:c:p:smh" opt; do
    case "$opt" in
        f|c) BURN_ARGS+=("-$opt" "$OPTARG") ;;
        p) PORT="$OPTARG"; BURN_ARGS+=(-p "$PORT") ;;
        s) SINGLE_SHOT=true; BURN_ARGS+=(-s) ;;
        m) OPEN_MONITOR=true ;;
        h) show_help; exit 0 ;;
        *) show_help >&2; exit 1 ;;
    esac
done
shift "$((OPTIND - 1))"
if [ "$#" -ne 0 ]; then
    echo "Error: Unexpected positional arguments." >&2
    show_help >&2
    exit 1
fi

if [ "$OPEN_MONITOR" = true ]; then
    if [ "$SINGLE_SHOT" != true ] || [ -z "$PORT" ]; then
        echo "Error: -m requires -s and an explicit -p <port>." >&2
        exit 1
    fi
    if command -v arduino-cli >/dev/null 2>&1; then
        ARDUINO_CLI=$(command -v arduino-cli)
    elif [ -x ./arduino-cli ]; then
        ARDUINO_CLI=./arduino-cli
    else
        echo "Error: arduino-cli is required for the serial monitor." >&2
        exit 1
    fi
fi

bash "$SCRIPT_DIR/burn_basic.sh" "${BURN_ARGS[@]}" || exit $?

if [ "$OPEN_MONITOR" = true ]; then
    echo "Monitoring $PORT at 19200 baud. Press Ctrl+C to exit."
    exec "$ARDUINO_CLI" monitor -p "$PORT" -c baudrate=19200
fi
exit 0
