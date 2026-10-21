#include <Arduino.h>
#line 1 "/Users/princebaah-mensah/Documents/Microcontrollers II/Project/test_blink/test_blink.ino"
// ATtiny85 Blink Test
// Software Pin 0 corresponds to Physical DIP Pin 5 on the ATtiny85
const byte pin_LED = 0;

#line 5 "/Users/princebaah-mensah/Documents/Microcontrollers II/Project/test_blink/test_blink.ino"
void setup();
#line 17 "/Users/princebaah-mensah/Documents/Microcontrollers II/Project/test_blink/test_blink.ino"
void loop();
#line 5 "/Users/princebaah-mensah/Documents/Microcontrollers II/Project/test_blink/test_blink.ino"
void setup() {
  pinMode(pin_LED, OUTPUT);

  // Rapidly flash 7 times on startup so you immediately know it worked
  for (int k = 0; k < 7; k++) {
    digitalWrite(pin_LED, HIGH);
    delay(50);
    digitalWrite(pin_LED, LOW);
    delay(50);
  }
}

void loop() {
  // Steady 1-second blink
  digitalWrite(pin_LED, HIGH);
  delay(1500);
  digitalWrite(pin_LED, LOW);
  delay(1500);
}
