#!/usr/bin/env bash
# ==============================================================================
# CMPE 3990: ATtiny85 Single-Command Compile, Fuse, Flash & Serial Monitor Script
# ==============================================================================

# --- Default Configuration ---
DEFAULT_TARGET="test_blink/test_blink.ino"
INPUT_TARGET="$DEFAULT_TARGET"
CLOCK_SPEED="1"
PORT=""
SINGLE_SHOT=false
OPEN_MONITOR=false

MCU="attiny85"
PROGRAMMER="stk500v1"
BAUD="19200"

# Default Fuse Bits (1 MHz Internal Oscillator)
LFUSE="0x62"
HFUSE="0xDF"
EFUSE="0xFF"
ARDUINO_CLOCK="internal1"

# --- Help Menu Function ---
show_help() {
    echo "Usage: ./burn.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f <path>   Path to .ino sketch, sketch folder, or .hex file"
    echo "  -c <speed>  Internal clock speed in MHz: 1, 8, or 16 (default: 1)"
    echo "  -p <port>   Serial port override"
    echo "  -s          Single-shot mode (burn one chip immediately and exit)"
    echo "  -m          Open live CLI Serial Monitor after burning (requires Uno Pin 4 -> ATtiny Pin 2)"
    echo "  -h          Show this help message and exit"
}

# --- Parse Command-Line Flags (Added 'm') ---
while getopts "f:c:p:smh" opt; do
    case "$opt" in
        f) INPUT_TARGET="$OPTARG" ;;
        c) CLOCK_SPEED="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        s) SINGLE_SHOT=true ;;
        m) OPEN_MONITOR=true ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# --- Map Clock Speed to Fuses & Arduino FQBN Clock Menu ---
case "$CLOCK_SPEED" in
    1)  LFUSE="0x62"; ARDUINO_CLOCK="internal1" ;;
    8)  LFUSE="0xE2"; ARDUINO_CLOCK="internal8" ;;
    16) LFUSE="0xF1"; ARDUINO_CLOCK="internal16" ;;
    *)
        echo "❌ Error: Unsupported clock speed '$CLOCK_SPEED'. Choose 1, 8, or 16."
        exit 1
        ;;
esac

# --- Step 1: Handle .ino Compilation vs Direct .hex Input ---
if [[ -d "$INPUT_TARGET" ]] || [[ "$INPUT_TARGET" == *.ino ]]; then
    echo "🔨 Sketch detected ('$INPUT_TARGET'). Compiling .ino to .hex for ATtiny85 @ ${CLOCK_SPEED} MHz..."
    
    if command -v arduino-cli &> /dev/null; then
        ARDUINO_CLI="arduino-cli"
    elif [ -f "./arduino-cli" ]; then
        ARDUINO_CLI="./arduino-cli"
    else
        echo "❌ Error: 'arduino-cli' not found."
        exit 1
    fi

    if [[ -d "$INPUT_TARGET" ]]; then
        SKETCH_DIR="${INPUT_TARGET%/}"
    else
        SKETCH_DIR=$(dirname "$INPUT_TARGET")
    fi
    BUILD_DIR="$SKETCH_DIR/build/cli_${CLOCK_SPEED}MHz"

    FQBN="attiny:avr:ATtinyX5:cpu=attiny85,clock=${ARDUINO_CLOCK}"
    "$ARDUINO_CLI" compile --fqbn "$FQBN" --build-path "$BUILD_DIR" "$SKETCH_DIR"
    
    if [ $? -ne 0 ]; then
        echo "❌ Error: Compilation failed!"
        exit 1
    fi

    HEX_FILE=$(find "$BUILD_DIR" -name "*.ino.hex" -o -name "*.hex" | head -n 1)
    echo "✅ Compilation complete: $HEX_FILE"

elif [[ "$INPUT_TARGET" == *.hex ]]; then
    HEX_FILE="$INPUT_TARGET"
else
    echo "❌ Error: '$INPUT_TARGET' is not a valid .ino file, sketch directory, or .hex file."
    exit 1
fi

if [ -z "$HEX_FILE" ] || [ ! -f "$HEX_FILE" ]; then
    echo "❌ Error: Compiled Hex file could not be located!"
    exit 1
fi

# --- Auto-Locate avrdude ---
AVRDUDE_BIN=$(find "$HOME/Library/Arduino15" "$HOME/.arduino15" -path "*/8.0-arduino.1/bin/avrdude" -o -path "*/6.3.0-arduino17/bin/avrdude" 2>/dev/null | head -n 1)
AVRDUDE_CONF=$(find "$HOME/Library/Arduino15" "$HOME/.arduino15" -path "*/8.0-arduino.1/etc/avrdude.conf" -o -path "*/6.3.0-arduino17/etc/avrdude.conf" 2>/dev/null | head -n 1)

if [ -z "$AVRDUDE_BIN" ]; then
    echo "❌ Error: Could not find avrdude inside Arduino15 folder."
    exit 1
fi

# --- Auto-Detect Serial Port ---
if [ -z "$PORT" ]; then
    PORT=$(ls /dev/cu.usb* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | head -n 1)
    if [ -z "$PORT" ]; then
        echo "❌ Error: No Arduino Uno detected on USB!"
        exit 1
    fi
fi

# --- Core Flash Function ---
burn_chip() {
    echo "⏳ Setting fuses (${CLOCK_SPEED} MHz -> lfuse:$LFUSE) and flashing firmware..."
    "$AVRDUDE_BIN" -C "$AVRDUDE_CONF" \
        -p "$MCU" -c "$PROGRAMMER" -P "$PORT" -b "$BAUD" \
        -U efuse:w:"$EFUSE":m \
        -U hfuse:w:"$HFUSE":m \
        -U lfuse:w:"$LFUSE":m \
        -U flash:w:"$HEX_FILE":i
}

# --- Serial Monitor Function ---
start_monitor() {
    echo ""
    echo "========================================================"
    echo " 📡 Live ATtiny85 Serial Monitor ($PORT @ $BAUD baud)"
    echo "    Wire: ATtiny DIP Pin 2 (PB3) ---> Arduino Uno Pin 4"
    echo "    Press [Ctrl + C] to exit monitor"
    echo "========================================================"
    if [ -f "./arduino-cli" ]; then
        ./arduino-cli monitor -p "$PORT" -c baudrate="$BAUD"
    elif command -v arduino-cli &> /dev/null; then
        arduino-cli monitor -p "$PORT" -c baudrate="$BAUD"
    else
        stty -f "$PORT" "$BAUD" raw -echo && cat "$PORT"
    fi
}

echo ""
echo "========================================================"
echo " 🔥 ATtiny85 Burn Script"
echo "========================================================"
echo " Target MCU : $MCU ($CLOCK_SPEED MHz Internal Clock)"
echo " Programmer : $PROGRAMMER @ $BAUD baud ($PORT)"
echo " Fuses      : lfuse=$LFUSE | hfuse=$HFUSE | efuse=$EFUSE"
echo " Firmware   : $HEX_FILE"
echo "========================================================"

# --- Execute Single-Shot or Batch Mode ---
if [ "$SINGLE_SHOT" = true ]; then
    burn_chip
    if [ $? -eq 0 ]; then
        echo "✅ SUCCESS! Chip programmed in single-shot mode."
        if [ "$OPEN_MONITOR" = true ]; then
            start_monitor
        fi
        exit 0
    else
        echo "❌ FAILED! Check chip orientation and wiring."
        exit 1
    fi
fi

COUNT=0
while true; do
    echo ""
    read -p "👉 Insert ATtiny85 and press [ENTER] to burn (or 'q' to quit): " choice
    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        echo "Finished! Total ATtiny85 chips programmed: $COUNT"
        break
    fi

    burn_chip
    if [ $? -eq 0 ]; then
        ((COUNT++))
        echo "✅ SUCCESS! Chip #$COUNT programmed and verified. Safe to remove!"
        if [ "$OPEN_MONITOR" = true ]; then
            start_monitor
        fi
    else
        echo "❌ FAILED! Check chip orientation and breadboard wires."
    fi
done
