#!/usr/bin/env bash
DEFAULT_TARGET="test_blink/test_blink.ino"
INPUT_TARGET="$DEFAULT_TARGET"
CLOCK_SPEED="1"
PORT=""
SINGLE_SHOT=false

MCU="attiny85"
PROGRAMMER="stk500v1"
BAUD="19200"

LFUSE="0x62"
HFUSE="0xDF"
EFUSE="0xFF"
ARDUINO_CLOCK="internal1"

show_help() {
    echo "Usage: ./burn_basic.sh [OPTIONS]"
    echo "  -f <path>   Path to .ino sketch, sketch folder, or .hex file"
    echo "  -c <speed>  Internal clock speed in MHz: 1, 8, or 16 (default: 1)"
    echo "  -p <port>   Serial port override"
    echo "  -s          Single-shot mode (burn one chip and exit)"
    echo "  -h          Show help menu"
}

while getopts "f:c:p:sh" opt; do
    case "$opt" in
        f) INPUT_TARGET="$OPTARG" ;;
        c) CLOCK_SPEED="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        s) SINGLE_SHOT=true ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

case "$CLOCK_SPEED" in
    1)  LFUSE="0x62"; ARDUINO_CLOCK="internal1" ;;
    8)  LFUSE="0xE2"; ARDUINO_CLOCK="internal8" ;;
    16) LFUSE="0xF1"; ARDUINO_CLOCK="internal16" ;;
    *)  echo "Error: Choose clock speed 1, 8, or 16."; exit 1 ;;
esac

if [[ -d "$INPUT_TARGET" ]] || [[ "$INPUT_TARGET" == *.ino ]]; then
    echo "Compiling '$INPUT_TARGET' for ATtiny85 @ ${CLOCK_SPEED} MHz..."
    ARDUINO_CLI=$(command -v arduino-cli || echo "./arduino-cli")
    SKETCH_DIR=$([[ -d "$INPUT_TARGET" ]] && echo "${INPUT_TARGET%/}" || dirname "$INPUT_TARGET")
    BUILD_DIR="$SKETCH_DIR/build/cli_${CLOCK_SPEED}MHz"

    "$ARDUINO_CLI" compile --fqbn "attiny:avr:ATtinyX5:cpu=attiny85,clock=${ARDUINO_CLOCK}" --build-path "$BUILD_DIR" "$SKETCH_DIR" || exit 1
    HEX_FILE=$(find "$BUILD_DIR" -name "*.ino.hex" -o -name "*.hex" | head -n 1)
else
    HEX_FILE="$INPUT_TARGET"
fi

AVRDUDE_BIN=$(find "$HOME/Library/Arduino15" "$HOME/.arduino15" -path "*/8.0-arduino.1/bin/avrdude" -o -path "*/6.3.0-arduino17/bin/avrdude" 2>/dev/null | head -n 1)
AVRDUDE_CONF=$(find "$HOME/Library/Arduino15" "$HOME/.arduino15" -path "*/8.0-arduino.1/etc/avrdude.conf" -o -path "*/6.3.0-arduino17/etc/avrdude.conf" 2>/dev/null | head -n 1)
[ -z "$PORT" ] && PORT=$(ls /dev/cu.usb* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | head -n 1)

burn_chip() {
    "$AVRDUDE_BIN" -C "$AVRDUDE_CONF" \
        -p "$MCU" -c "$PROGRAMMER" -P "$PORT" -b "$BAUD" \
        -U efuse:w:"$EFUSE":m \
        -U hfuse:w:"$HFUSE":m \
        -U lfuse:w:"$LFUSE":m \
        -U flash:w:"$HEX_FILE":i
}

if [ "$SINGLE_SHOT" = true ]; then
    burn_chip
    exit $?
fi

COUNT=0
while true; do
    read -p "Insert ATtiny85 and press [ENTER] to burn (or 'q' to quit): " choice
    [[ "$choice" == "q" || "$choice" == "Q" ]] && echo "Total programmed: $COUNT" && break
    burn_chip && ((COUNT++)) && echo "SUCCESS! Chip #$COUNT programmed."
done
