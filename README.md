# ATtiny85 Command-Line Programming with an Arduino Uno

Compile, set clock fuses, and program bare ATtiny85 microcontrollers from the terminal using an Arduino Uno as an ISP programmer. An optional relay sketch also forwards ATtiny85 software serial output to the terminal through the same Uno.

The instructions below target macOS. The 1 MHz blink workflow and 8 MHz serial telemetry workflow were confirmed working on the project author's hardware. The scripts also offer a 16 MHz clock option; this walkthrough does not establish hardware validation for that option.

## Contents

1. [Project motivation and features](#1-project-motivation-and-features)
2. [Download the project and install the toolchain](#2-download-the-project-and-install-the-toolchain)
3. [Wire and program the blink example](#3-wire-and-program-the-blink-example)
4. [Add serial telemetry](#4-add-serial-telemetry)
5. [Fuse reference](#5-fuse-reference)
6. [Troubleshooting](#6-troubleshooting)

## 1. Project motivation and features

Repeatedly configuring a GUI and compiling the same sketch for each chip adds work during lab programming. This project brings compilation, fuse selection, and flashing into one command, with an interactive batch loop that reuses the compiled firmware.

- Compile an Arduino sketch or program an existing Intel HEX file.
- Select 1, 8, or 16 MHz clock settings with `-c`.
- Program one chip with `-s`, or use the batch loop.
- Use ArduinoISP status LEDs for programming and error feedback.
- Forward 9600-baud ATtiny85 telemetry through the Uno to a 19200-baud terminal monitor.

| File | Purpose |
| --- | --- |
| [burn_basic.sh](burn_basic.sh) | Compile, set fuses, and flash; single-chip or batch mode. |
| [burn.sh](burn.sh) | Run `burn_basic.sh`, optionally opening the monitor after a successful single-chip burn. |
| [ArduinoISP_Relay/ArduinoISP_Relay.ino](ArduinoISP_Relay/ArduinoISP_Relay.ino) | ArduinoISP with software serial forwarding on Uno digital pin 4. |
| [test_blink/test_blink.ino](test_blink/test_blink.ino) | Seven startup flashes, followed by 1.5 seconds on and 1.5 seconds off. |
| [serial_demo/serial_demo.ino](serial_demo/serial_demo.ino) | LED and serial telemetry example, used here at 8 MHz. |

The files in the repository are the source of truth. Download them rather than copying complete scripts from formatted text.

## 2. Download the project and install the toolchain

### 2.1 Download all required files

Run this in your terminal. It creates the sketch folders and downloads both scripts and all examples. Existing files with these names will be overwritten; use a new folder if you have local edits to preserve.

```bash
(
set -e
mkdir -p ATtiny85_CLI_Project
cd ATtiny85_CLI_Project
mkdir -p ArduinoISP_Relay test_blink serial_demo

BASE_URL="https://raw.githubusercontent.com/Baah134/attiny85-cli-burn-script/main"
for FILE in burn_basic.sh burn.sh ArduinoISP_Relay/ArduinoISP_Relay.ino test_blink/test_blink.ino serial_demo/serial_demo.ino; do
    curl -fL "$BASE_URL/$FILE" -o "$FILE"
done

chmod +x burn_basic.sh burn.sh
bash -n burn_basic.sh
bash -n burn.sh
)
cd ATtiny85_CLI_Project
```

Alternatively, clone the repository and work from its root directory:

```bash
git clone https://github.com/Baah134/attiny85-cli-burn-script.git
cd attiny85-cli-burn-script
chmod +x burn_basic.sh burn.sh
```

Use one download method. Run the remaining commands from the project directory. Paths containing spaces must be quoted.

### 2.2 Install standalone Arduino CLI

If `./arduino-cli` is already present and works, skip this step. Otherwise, download the official installer and install the CLI into this project directory:

```bash
(
set -e
curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh -o /tmp/attiny85-install-cli.sh
BINDIR="$PWD" sh /tmp/attiny85-install-cli.sh
./arduino-cli version
)
```

The examples below use `./arduino-cli`. If you use an existing installation on your PATH, substitute `arduino-cli` for `./arduino-cli`.

### 2.3 Install the board cores

For a first-time CLI setup, initialize configuration:

```bash
./arduino-cli config init
```

If configuration already exists, keep it. Do not overwrite it just to run this project.

```bash
(
set -e
./arduino-cli config add board_manager.additional_urls https://raw.githubusercontent.com/damellis/attiny/ide-1.6.x-boards-manager/package_damellis_attiny_index.json
./arduino-cli core update-index
./arduino-cli core install arduino:avr
./arduino-cli core install attiny:avr
./arduino-cli core list
)
```

`burn_basic.sh` searches the standard Arduino15 directories for AVRDUDE versions `8.0-arduino.1` and `6.3.0-arduino17`. Other versions or custom data directories require adjusting its `AVRDUDE_BIN` and `AVRDUDE_CONF` discovery. Keep the executable and configuration from the same installation. Do not delete or replace installed tool directories to work around an incompatible executable.

## 3. Wire and program the blink example

### 3.1 Hardware wiring

Use an Arduino Uno, a bare ATtiny85 in an 8-pin DIP package, a breadboard, jumper wires, an LED with a 220-ohm series resistor, and a 10 µF capacitor for Uno reset suppression. Identify the ATtiny85 notch/dot before wiring. Disconnect power when wiring or replacing chips.

| Arduino Uno connection | ATtiny85 physical pin | Function |
| --- | --- | --- |
| 5V | 8 | VCC |
| GND | 4 | Common ground |
| Digital 10 | 1 (PB5 / RESET) | Target reset |
| Digital 11 | 5 (PB0 / MOSI) | MOSI; also the example LED output |
| Digital 12 | 6 (PB1 / MISO) | MISO |
| Digital 13 | 7 (PB2 / SCK) | SCK |

Connect ATtiny85 pin 5 through a 220-ohm resistor and LED to ground, with the LED oriented to conduct when PB0 is high. Place a 100 nF decoupling capacitor across ATtiny85 VCC and GND close to the chip.

Optional Uno status LEDs each need a series resistor: digital 7 for programming, digital 8 for errors, and digital 9 for the standard ArduinoISP heartbeat. The relay firmware changes idle heartbeat behavior, so a missing idle pulse alone does not establish failure.

**The 10 µF capacitor goes across RESET and GND on the Uno, not the ATtiny85.** Its positive lead goes to Uno RESET and its negative lead to GND. Disconnect one leg when uploading a sketch to the Uno; reconnect it before using the Uno to program the ATtiny85.

### 3.2 Upload the programmer firmware to the Uno

Use the included `ArduinoISP_Relay` sketch for both blink programming and the later telemetry example. This avoids searching for a separately installed `ArduinoISP.ino` or modifying it with Python.

Disconnect one leg of the Uno reset capacitor, connect the Uno by USB, then run:

```bash
(
set -e
./arduino-cli compile --fqbn arduino:avr:uno ArduinoISP_Relay
./arduino-cli board list
printf '\nEnter your Uno port exactly as shown above: '
read -r PORT
if [ -z "$PORT" ]; then
    echo "No port entered. Stopping."
    exit 1
fi
./arduino-cli upload -p "$PORT" --fqbn arduino:avr:uno ArduinoISP_Relay
)
```

After a successful upload, reconnect the 10 µF reset capacitor. The Uno now contains the programmer firmware; do not upload the ATtiny sketch to the Uno.

### 3.3 Program one ATtiny85

List the ports:

```bash
./arduino-cli board list
```

Replace `/dev/cu.usbmodemXXXX` below with the Uno port shown on your machine:

```bash
bash ./burn_basic.sh -s -c 1 -p /dev/cu.usbmodemXXXX -f test_blink/test_blink.ino
```

The script compiles for 1 MHz, sets fuses, and programs flash. Check that AVRDUDE finishes without errors. The LED gives seven rapid startup flashes, then stays on for 1.5 seconds and off for 1.5 seconds.

### 3.4 Batch programming and HEX input

Omit `-s` to compile once and enter the programming loop:

```bash
bash ./burn_basic.sh -c 8 -p /dev/cu.usbmodemXXXX -f test_blink/test_blink.ino
```

Press Enter for each programming attempt and type `q` to finish. Disconnect target power before replacing a chip, then reconnect it before pressing Enter. This breadboard setup does not control target power automatically.

To program an existing HEX file:

```bash
bash ./burn_basic.sh -s -c 8 -p /dev/cu.usbmodemXXXX -f firmware.hex
```

For precompiled HEX input, ensure the firmware was built for the selected clock. The script cannot infer its compilation clock from the HEX file.

## 4. Add serial telemetry

### 4.1 Add the telemetry wire

Keep the ISP wiring and common ground. Add:

**ATtiny85 physical pin 2 (PB3 / TX) → Uno digital pin 4 (software RX).**

Do not confuse ATtiny85 physical pin 4 (GND) with Uno digital pin 4 (telemetry input).

| Serial link | Baud rate |
| --- | --- |
| ATtiny85 software TX → Uno software RX | 9600 |
| Uno hardware serial → terminal monitor | 19200 |

These rates are intentionally different. The Uno receives bytes at 9600 and forwards them at 19200. Use 8 MHz for this telemetry walkthrough.

### 4.2 Combined flash and monitor command

If you completed Section 3.2, the Uno already has the relay firmware. Keep its reset capacitor connected and run:

```bash
(
set -e
./arduino-cli board list
printf '\nEnter your Uno port exactly as shown above: '
read -r PORT
if [ -z "$PORT" ]; then
    echo "No port entered. Stopping."
    exit 1
fi
bash ./burn.sh -s -c 8 -p "$PORT" -f serial_demo/serial_demo.ino -m
)
```

`burn.sh` delegates programming to `burn_basic.sh` and opens the monitor only if programming succeeds. With `-m`, supply both `-s` and an explicit `-p` so the monitor uses the same port. Press Ctrl+C to leave the monitor; close it before another programming attempt.

### 4.3 Separate commands used during troubleshooting

The same workflow can be run explicitly as two steps:

```bash
(
set -e
./arduino-cli board list
printf '\nEnter your Uno port exactly as shown above: '
read -r PORT
if [ -z "$PORT" ]; then
    echo "No port entered. Stopping."
    exit 1
fi
bash ./burn_basic.sh -s -c 8 -p "$PORT" -f serial_demo/serial_demo.ino
./arduino-cli monitor -p "$PORT" -c baudrate=19200
)
```

Expected output includes readable lines such as:

```text
[ATtiny85] Packet #0 | Uptime: 0.5s | LED: ON
[ATtiny85] Packet #1 | Uptime: 1.5s | LED: ON
```

The startup banner can be missed while the monitor connects. Printed uptime values are illustrative; serial transmission adds time to each loop.

## 5. Fuse reference

| Clock option | Low fuse | High fuse | Extended fuse | Clock source |
| --- | --- | --- | --- | --- |
| `-c 1` | `0x62` | `0xDF` | `0xFF` | Internal 8 MHz oscillator divided by 8. |
| `-c 8` | `0xE2` | `0xDF` | `0xFF` | Internal 8 MHz oscillator without the divide-by-8 setting. |
| `-c 16` | `0xF1` | `0xDF` | `0xFF` | Internal PLL clock option. |

The scripts write all three fuse bytes on every burn. They do not preserve custom brown-out, EEPROM-preservation, or other fuse settings. Review them before using a chip configured for another application. The tutorial programs application flash directly over ISP; it does not install an ATtiny bootloader.

## 6. Troubleshooting

| Symptom | Check or fix |
| --- | --- |
| Syntax error containing a literal `\vert{}\vert{}` | A formatted copy replaced Bash `||`. Download the actual script and run `bash -n burn_basic.sh`. |
| `cp: : No such file or directory` while finding ArduinoISP | The source search returned an empty path. Use the included relay sketch as in Section 3.2. |
| Missing `ArduinoISP_Relay.ino` | Complete the project download before compiling. |
| `./burn.sh: no such file or directory` | Check `pwd` and `ls`. Download both scripts, or use Section 4.3 with `burn_basic.sh`. |
| Missing `serial_demo/serial_demo.ino` | Download the sketch along with its folder in Section 2.1. |
| `curl: (22)` with HTTP 404 | The requested file or branch is absent. Check the repository filename and path; the download block stops on errors. |
| Uno upload fails | Disconnect one leg of the Uno reset capacitor, close any monitor, and select the correct port. |
| ATtiny programming fails | Reconnect the Uno reset capacitor; check chip orientation, power, ground, ISP wiring, and the selected port. |
| Garbled telemetry | Keep the monitor at 19200 and both software serial endpoints at 9600. Check PB3 / physical pin 2 → Uno digital 4, common ground, and compilation at 8 MHz. |
| No startup banner but later packets appear | The monitor connected after the banner was sent. Later readable packets confirm forwarding. |
| `bad CPU type in executable` | Check the architecture and compatibility of the installed AVR tools. Update/select a compatible installation and its matching configuration. |

Use `"$HOME/Library/Arduino15"` for a quoted home-directory path. Do not escape a leading tilde as `\~`, and do not add backslashes before `<` in C++ includes. Copy commands from code blocks.

**Known limitations:** `burn_basic.sh` selects the first discovered port when `-p` is omitted, so these examples always pass a port explicitly. Its batch loop does not stop on closed standard input; run it interactively and exit with `q`. The relay forwards telemetry while outside programming mode, including before a programmer handshake. If a transmitting application interferes with synchronization, disconnect the telemetry wire during programming and reconnect it before monitoring. This is a diagnostic workaround, not an automatic mode switch.
