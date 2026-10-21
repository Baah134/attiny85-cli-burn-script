// ATtiny85 Blink Test
// Software Pin 0 corresponds to Physical DIP Pin 5 on the ATtiny85
const byte pin_LED = 0;

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