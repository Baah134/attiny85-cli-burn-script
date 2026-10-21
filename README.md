# ATtiny85 Command-Line-Only Programming Tutorial & Burn Script

A complete, step-by-step command-line tutorial and Bash automation suite ("burn script") for writing, compiling, setting hardware fuse bits (1 MHz / 8 MHz / 16 MHz), and batch-programming ATtiny85 microcontrollers using an Arduino Uno as an ISP programmer—without ever opening the Arduino IDE.

---

## Table of Contents
1. [Project Motivation & Features](#1-project-motivation--features)
2. [Prerequisites & CLI Toolchain Setup (macOS)](#2-prerequisites--cli-toolchain-setup-macos)
3. [Part 1: Core Hardware Wiring & Terminal Blink Workflow](#3-part-1-core-hardware-wiring--terminal-blink-workflow)
   - [3.1 ICSP Breadboard Wiring](#31-icsp-breadboard-wiring)
   - [3.2 Flash the Uno with Standard ArduinoISP via Terminal](#32-flash-the-uno-with-standard-arduinoisp-via-terminal)
   - [3.3 Create the Blink Sketch via Terminal](#33-create-the-blink-sketch-via-terminal)
   - [3.4 Script 1: The Core Fuse & Flash Burn Script (`burn_basic.sh`)](#34-script-1-the-core-fuse--flash-burn-script-burn_basicsh)
4. [Part 2: Pushing the ATtiny85 Limits — Bit-Banged Serial Telemetry](#4-part-2-pushing-the-attiny85-limits--bit-banged-serial-telemetry)
   - [4.1 Hardware Upgrade: Adding the UART Relay Wire](#41-hardware-upgrade-adding-the-uart-relay-wire)
   - [4.2 Flash the Uno with `ArduinoISP_Relay` via Terminal](#42-flash-the-uno-with-arduinoisp_relay-via-terminal)
   - [4.3 Create the 8 MHz Serial Telemetry Sketch via Terminal](#43-create-the-8-mhz-serial-telemetry-sketch-via-terminal)
   - [4.4 Script 2: Full Burn + Serial Monitor Script (`burn.sh`)](#44-script-2-full-burn--serial-monitor-script-burnsh)
5. [ATtiny85 Fuse Bit Reference](#5-attiny85-fuse-bit-reference)

---

## 1. Project Motivation & Features

When programming multiple bare ATtiny85 microcontrollers in a lab or production setting, the Arduino IDE GUI creates a major bottleneck: you must manually configure menus, click **Burn Bootloader** (to set fuse bits), wait for compilation, and click **Upload Using Programmer** for every single chip.

This project provides a **100% command-line workflow** arranged sequentially from basic flashing to advanced hardware telemetry:
* **Direct Terminal Code Creation & Compilation:** Write `.ino` sketches in the terminal and compile them into `.hex` binaries automatically using `arduino-cli`.
* **Single-Command Fuse Setting & Flashing:** Uses `avrdude` to program Extended (`efuse`), High (`hfuse`), and Low (`lfuse`) fuse bytes alongside flash memory in a single pass.
* **Dynamic Clock Selection (`-c 1|8|16`):** Automatically matches `F_CPU` compilation speed and hardware `lfuse` bits (`0x62` for 1 MHz, `0xE2` for 8 MHz, `0xF1` for 16 MHz).
* **Batch-Programming Loop & Single-Shot Modes:** Compile once and flash dozens of ATtiny85 chips sequentially by pressing `[ENTER]`, or pass `-s` for a single-command burn.
* **Hardware Status LEDs:** Uses `ArduinoISP` pins 7, 8, and 9 for visual breadboard feedback (*Programming*, *Error*, and *Heartbeat*).
* **Bit-Banged UART Serial Monitor (`-m`):** Overcomes the ATtiny85's lack of hardware UART (`Serial`) by transmitting 9600-baud software serial on `PB3` (DIP Pin 2) through the Arduino Uno programmer directly into the terminal.

---

## 2. Prerequisites & CLI Toolchain Setup (macOS)

Create a new project directory and navigate into it:
```bash
mkdir -p ATtiny85_CLI_Project && cd ATtiny85_CLI_Project
```

### 2.1 Install Standalone `arduino-cli`
Download the official `arduino-cli` binary directly into your project folder (no Homebrew required):
```bash
curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh
mv bin/arduino-cli . && rm -rf bin
```

### 2.2 Install AVR & ATtiny85 Board Cores via Terminal
Initialize the configuration and install both the `arduino:avr` core and the David A. Mellis `attiny` board package from the command line:
```bash
./arduino-cli config init --overwrite
./arduino-cli config add board_manager.additional_urls https://raw.githubusercontent.com/damellis/attiny/ide-1.6.x-boards-manager/package_damellis_attiny_index.json
./arduino-cli core update-index
./arduino-cli core install arduino:avr
./arduino-cli core install attiny:avr
```

### 2.3 Fix macOS Apple Silicon `bad CPU type in executable` Error (If Applicable)
If an older package installed a 32-bit `avrdude` (`6.3.0-arduino9`) that macOS blocks, symlink your 64-bit `6.3.0-arduino17` binary over it:
```bash
rm -rf ~/Library/Arduino15/packages/arduino/tools/avrdude/6.3.0-arduino9 && \
ln -s ~/Library/Arduino15/packages/arduino/tools/avrdude/6.3.0-arduino17 ~/Library/Arduino15/packages/arduino/tools/avrdude/6.3.0-arduino9
```

---

## 3. Part 1: Core Hardware Wiring & Terminal Blink Workflow

### 3.1 ICSP Breadboard Wiring
Locate the dot/notch on your ATtiny85 (Physical Pin 1) and wire it to your Arduino Uno:

```text
                  +---v---+
  (RESET) PB5  -> 1|•      |8 <- VCC (5V)
          PB3     2|       |7 <- PB2 (SCK)
          PB4     3|       |6 <- PB1 (MISO)
          GND  -> 4|       |5 <- PB0 (MOSI + Test LED)
                  +-------+
```

| Arduino Uno Pin | ATtiny85 Physical Pin | Function / Component |
| :--- | :--- | :--- |
| **5V** | **Pin 8** (`VCC`) | 5V Power Supply |
| **GND** | **Pin 4** (`GND`) | Common Ground |
| **Pin 10** | **Pin 1** (`PB5 / RESET`) | SPI Chip Select / Reset |
| **Pin 11** | **Pin 5** (`PB0 / MOSI`) | SPI MOSI + **220 Ω resistor -> LED (+) -> GND** |
| **Pin 12** | **Pin 6** (`PB1 / MISO`) | SPI MISO |
| **Pin 13** | **Pin 7** (`PB2 / SCK`) | SPI Clock |
| **Pin 9** | *(To LED -> GND)* | **Heartbeat LED** (+ 220 Ω resistor to GND) |
| **Pin 8** | *(To LED -> GND)* | **Error LED** (+ 220 Ω resistor to GND) |
| **Pin 7** | *(To LED -> GND)* | **Programming Activity LED** (+ 220 Ω resistor to GND) |
| **RESET to GND** | *(On Arduino Uno)* | **10 µF Electrolytic Capacitor** (Minus `-` stripe in `GND`). **Insert ONLY AFTER Step 3.2!** |

### 3.2 Flash the Uno with Standard `ArduinoISP` via Terminal
1. Ensure the **10 µF capacitor is removed** from the Arduino Uno's `RESET` pin.
2. Locate the built-in `ArduinoISP` example and upload it to your Arduino Uno via terminal:
```bash
ISP_SRC=$(find ~/Library/Arduino15 -name "ArduinoISP.ino" 2>/dev/null | head -n 1)
PORT=$(ls /dev/cu.usb* | head -n 1)
./arduino-cli compile --fqbn arduino:avr:uno "$ISP_SRC"
./arduino-cli upload -p "$PORT" --fqbn arduino:avr:uno "$ISP_SRC"
```
3. **Insert the 10 µF capacitor** between `RESET` and `GND` on the Arduino Uno (negative stripe to `GND`). Your Pin 9 Heartbeat LED will begin pulsing.

### 3.3 Create the Blink Sketch via Terminal
Run this command in your terminal to create `test_blink/test_blink.ino` without opening any GUI editor:
```bash
mkdir -p test_blink
cat << 'EOF' > test_blink/test_blink.ino
// ATtiny85 Blink Sketch (Software Pin 0 = Physical DIP Pin 5)
const byte pin_LED = 0;

void setup() {
  pinMode(pin_LED, OUTPUT);
  // Rapid 7-flash startup burst to confirm new firmware load
  for (int k = 0; k < 7; k++) {
    digitalWrite(pin_LED, HIGH);
    delay(50);
    digitalWrite(pin_LED, LOW);
    delay(50);
  }
}

void loop() {
  digitalWrite(pin_LED, HIGH);
  delay(500);
  digitalWrite(pin_LED, LOW);
  delay(500);
}
EOF
```

### 3.4 Script 1: The Core Fuse & Flash Burn Script (`burn_basic.sh`)
Create the core single-command/batch programming script by pasting this into your terminal:
```bash
cat << 'EOF' > burn_basic.sh
#!/usr/bin/env bash
# ==============================================================================
# Part 1 Script: ATtiny85 CLI Compile, Fuse & Batch-Flash Script
# ==============================================================================

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

# Compile .ino to .hex if sketch is provided
if [[ -d "$INPUT_TARGET" ]] \vert{}\vert{} [[ "$INPUT_TARGET" == *.ino ]]; then
    echo "Compiling '$INPUT_TARGET' for ATtiny85 @ ${CLOCK_SPEED} MHz..."
    ARDUINO_CLI=$(command -v arduino-cli || echo "./arduino-cli")
    SKETCH_DIR=$([[ -d "$INPUT_TARGET" ]] && echo "${INPUT_TARGET\%/}" \vert{}\vert{} dirname "$INPUT_TARGET")
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
    [[ "$choice" == "q" \vert{}\vert{} "$choice" == "Q" ]] && echo "Total programmed: $COUNT" && break
    burn_chip && ((COUNT++)) && echo "SUCCESS! Chip #$COUNT programmed."
done
EOF
chmod +x burn_basic.sh
```

**Run Part 1 (Single-Shot or Batch Mode):**
```bash
# Single-command compile, set 1 MHz fuses, and flash:
./burn_basic.sh -s -c 1 -f test_blink/test_blink.ino

# Batch mode (program multiple ATtiny85s in a row at 8 MHz):
./burn_basic.sh -c 8 -f test_blink/test_blink.ino
```

---

## 4. Part 2: Pushing the ATtiny85 Limits — Bit-Banged Serial Telemetry

Unlike the Arduino Uno (ATmega328P), the ATtiny85 has **no hardware UART** (`Serial`). To push the microcontroller's limits, we configure the ATtiny85 to run at **8 MHz** (`lfuse = 0xE2`) and bit-bang 9600-baud serial data out of **Physical Pin 2 (`PB3`)** into **Arduino Uno Pin 4**, using the Uno as both an ISP programmer and a transparent USB-Serial bridge.

### 4.1 Hardware Upgrade: Adding the UART Relay Wire
Add **one jumper wire** to your existing breadboard setup:
* **ATtiny85 Physical Pin 2 (`PB3`)** ---> **Arduino Uno Digital Pin 4**

### 4.2 Flash the Uno with `ArduinoISP_Relay` via Terminal
1. **Remove one leg of the 10 µF capacitor** from `GND` on the Arduino Uno.
2. Run this script in your terminal to inject non-blocking `SoftwareSerial` forwarding (on Uno Pin 4) into `ArduinoISP` and upload it to your Uno:
```bash
ISP_SRC=$(find ~/Library/Arduino15 -name "ArduinoISP.ino" 2>/dev/null | head -n 1)
mkdir -p ArduinoISP_Relay
cp "$ISP_SRC" ArduinoISP_Relay/ArduinoISP_Relay.ino

python3 -c '
with open("ArduinoISP_Relay/ArduinoISP_Relay.ino", "r") as f:
    code = f.read()

header = "#include <SoftwareSerial.h>\nSoftwareSerial tinySerial(4, 3);\n"
code = header + code.replace("SERIAL.begin(BAUDRATE);", "SERIAL.begin(BAUDRATE);\n  tinySerial.begin(9600);")

relay_hook = "if (!pmode) { while (tinySerial.available()) { SERIAL.write(tinySerial.read()); } } else { heartbeat(); }"
code = code.replace("heartbeat();", relay_hook)

with open("ArduinoISP_Relay/ArduinoISP_Relay.ino", "w") as f:
    f.write(code)
'

PORT=$(ls /dev/cu.usb* | head -n 1)
./arduino-cli compile --fqbn arduino:avr:uno ArduinoISP_Relay && \
./arduino-cli upload -p "$PORT" --fqbn arduino:avr:uno ArduinoISP_Relay
```
3. **Re-insert the 10 µF capacitor** between `RESET` and `GND` on the Arduino Uno.

### 4.3 Create the 8 MHz Serial Telemetry Sketch via Terminal
Run this command in your terminal to create `serial_demo/serial_demo.ino`:
```bash
mkdir -p serial_demo
cat << 'EOF' > serial_demo/serial_demo.ino
#include <SoftwareSerial.h>

// Software Pin 0 = Physical DIP Pin 5 (LED)
// Software Pin 3 = Physical DIP Pin 2 (UART TX -> Uno Pin 4)
// Software Pin 4 = Physical DIP Pin 3 (Unused RX)
const byte pin_LED = 0;
SoftwareSerial mySerial(4, 3);

unsigned long counter = 0;

void setup() {
  pinMode(pin_LED, OUTPUT);
  mySerial.begin(9600);

  for (int k = 0; k < 5; k++) {
    digitalWrite(pin_LED, HIGH);
    delay(50);
    digitalWrite(pin_LED, LOW);
    delay(50);
  }
  mySerial.println("\r\n=== ATtiny85 Bit-Banged UART Online (8 MHz) ===");
}

void loop() {
  digitalWrite(pin_LED, HIGH);
  mySerial.print("[ATtiny85] Packet #");
  mySerial.print(counter++);
  mySerial.print(" | Uptime: ");
  mySerial.print(millis() / 1000.0, 1);
  mySerial.println("s | LED: ON");
  delay(500);

  digitalWrite(pin_LED, LOW);
  delay(500);
}
EOF
```

### 4.4 Script 2: Full Burn + Serial Monitor Script (`burn.sh`)
This complete version of `burn.sh` includes everything from `burn_basic.sh` plus the **`-m` flag**, which opens a live `19200`-baud CLI serial monitor immediately after flashing the chip:
```bash
cat << 'EOF' > burn.sh
#!/usr/bin/env bash
# ==============================================================================
# Part 2 Master Script: ATtiny85 Compile, Fuse, Batch-Flash & Serial Monitor
# ==============================================================================

DEFAULT_TARGET="test_blink/test_blink.ino"
INPUT_TARGET="$DEFAULT_TARGET"
CLOCK_SPEED="1"
PORT=""
SINGLE_SHOT=false
OPEN_MONITOR=false

MCU="attiny85"
PROGRAMMER="stk500v1"
BAUD="19200"

LFUSE="0x62"
HFUSE="0xDF"
EFUSE="0xFF"
ARDUINO_CLOCK="internal1"

show_help() {
    echo "Usage: ./burn.sh [OPTIONS]"
    echo "  -f <path>   Path to .ino sketch, sketch folder, or .hex file"
    echo "  -c <speed>  Internal clock speed in MHz: 1, 8, or 16 (default: 1)"
    echo "  -p <port>   Serial port override"
    echo "  -s          Single-shot mode (burn one chip immediately and exit)"
    echo "  -m          Open live CLI Serial Monitor after burning (Uno Pin 4 <- ATtiny Pin 2)"
    echo "  -h          Show this help message and exit"
}

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

case "$CLOCK_SPEED" in
    1)  LFUSE="0x62"; ARDUINO_CLOCK="internal1" ;;
    8)  LFUSE="0xE2"; ARDUINO_CLOCK="internal8" ;;
    16) LFUSE="0xF1"; ARDUINO_CLOCK="internal16" ;;
    *)  echo "Error: Unsupported clock speed '$CLOCK_SPEED'. Choose 1, 8, or 16."; exit 1 ;;
esac

if [[ -d "$INPUT_TARGET" ]] \vert{}\vert{} [[ "$INPUT_TARGET" == *.ino ]]; then
    echo "🔨 Compiling '$INPUT_TARGET' for ATtiny85 @ ${CLOCK_SPEED} MHz..."
    ARDUINO_CLI=$(command -v arduino-cli || echo "./arduino-cli")
    SKETCH_DIR=$([[ -d "$INPUT_TARGET" ]] && echo "${INPUT_TARGET\%/}" \vert{}\vert{} dirname "$INPUT_TARGET")
    BUILD_DIR="$SKETCH_DIR/build/cli_${CLOCK_SPEED}MHz"

    "$ARDUINO_CLI" compile --fqbn "attiny:avr:ATtinyX5:cpu=attiny85,clock=${ARDUINO_CLOCK}" --build-path "$BUILD_DIR" "$SKETCH_DIR" || exit 1
    HEX_FILE=$(find "$BUILD_DIR" -name "*.ino.hex" -o -name "*.hex" | head -n 1)
elif [[ "$INPUT_TARGET" == *.hex ]]; then
    HEX_FILE="$INPUT_TARGET"
else
    echo "Error: Invalid input target '$INPUT_TARGET'."; exit 1
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

start_monitor() {
    echo "========================================================"
    echo " 📡 Live ATtiny85 Serial Monitor ($PORT @ $BAUD baud)"
    echo "    Press [Ctrl + C] to exit monitor"
    echo "========================================================"
    ARDUINO_CLI=$(command -v arduino-cli || echo "./arduino-cli")
    "$ARDUINO_CLI" monitor -p "$PORT" -c baudrate="$BAUD"
}

if [ "$SINGLE_SHOT" = true ]; then
    burn_chip && [ "$OPEN_MONITOR" = true ] && start_monitor
    exit $?
fi

COUNT=0
while true; do
    read -p "👉 Insert ATtiny85 and press [ENTER] to burn (or 'q' to quit): " choice
    [[ "$choice" == "q" \vert{}\vert{} "$choice" == "Q" ]] && echo "Total programmed: $COUNT" && break
    if burn_chip; then
        ((COUNT++))
        echo "✅ SUCCESS! Chip #$COUNT programmed."
        [ "$OPEN_MONITOR" = true ] && start_monitor
    fi
done
EOF
chmod +x burn.sh
```

**Run Part 2 (Compile for 8 MHz, Burn Fuses, Flash & Open Live Serial Monitor):**
```bash
./burn.sh -s -c 8 -f serial_demo/serial_demo.ino -m
```

Sample Output:
```text
=== ATtiny85 Bit-Banged UART Online (8 MHz) ===
[ATtiny85] Packet #0 | Uptime: 0.5s | LED: ON
[ATtiny85] Packet #1 | Uptime: 1.5s | LED: ON
[ATtiny85] Packet #2 | Uptime: 2.5s | LED: ON
```

---

## 5. ATtiny85 Fuse Bit Reference

| Clock Speed (`-c`) | Low Fuse (`lfuse`) | High Fuse (`hfuse`) | Extended Fuse (`efuse`) | Explanation |
| :--- | :--- | :--- | :--- | :--- |
| **1 MHz** (`-c 1`) | `0x62` | `0xDF` | `0xFF` | Factory default: 8 MHz internal oscillator divided by 8 (`CKDIV8 = 0`). |
| **8 MHz** (`-c 8`) | `0xE2` | `0xDF` | `0xFF` | Unprograms `CKDIV8` (`Bit 7 = 1`) for full 8 MHz speed (required for accurate 9600-baud `SoftwareSerial`). |
| **16 MHz** (`-c 16`) | `0xF1` | `0xDF` | `0xFF` | Enables internal High-Frequency PLL clock (`CKSEL = 0001`). |
