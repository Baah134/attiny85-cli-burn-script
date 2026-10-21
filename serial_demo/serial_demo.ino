#include <SoftwareSerial.h>

// ATtiny85 Pin Mapping:
// Software Pin 0 = Physical DIP Pin 5 (LED)
// Software Pin 3 = Physical DIP Pin 2 (Bit-Banged UART TX -> Uno Pin 4)
// Software Pin 4 = Physical DIP Pin 3 (Unused RX)
const byte pin_LED = 0;
SoftwareSerial mySerial(4, 3); // RX = PB4, TX = PB3 (DIP Pin 2)

unsigned long counter = 0;

void setup() {
  pinMode(pin_LED, OUTPUT);
  mySerial.begin(9600);

  // Startup burst
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
