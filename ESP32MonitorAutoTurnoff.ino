#include <WiFi.h>
#include <WiFiUdp.h>
#include "credentials.h"

WiFiUDP udp;

#define TRIG_PIN 5
#define ECHO_PIN 18

#define BROADCAST_PORT 4210
#define DATA_PORT 4211

IPAddress pcIP;
bool pcConnected = false;

long readDistanceCM() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  long duration = pulseIn(ECHO_PIN, HIGH, 30000);
  if (duration == 0) {
    return 0;
  }
  long distance = duration * 0.034 / 2;
  return distance;
}

void setup() {
  Serial.begin(115200);

  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);

  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nConnected!");
  Serial.print("ESP32 IP: ");
  Serial.println(WiFi.localIP());

  udp.begin(BROADCAST_PORT);
}

void loop() {

  // Check for PC broadcast (handshake)
  int packetSize = udp.parsePacket();
  if (packetSize) {
    char incoming[255];
    int len = udp.read(incoming, 255);
    if (len > 0) incoming[len] = 0;

    String msg = String(incoming);

    if (msg == "PC_ONLINE") {
      pcIP = udp.remoteIP();
      pcConnected = true;
      Serial.print("PC found at: ");
      Serial.println(pcIP);
    }
  }

  if (pcConnected) {
    long distance = readDistanceCM();

    char buffer[50];
    sprintf(buffer, "DIST:%ld", distance);

    udp.beginPacket(pcIP, DATA_PORT);
    udp.print(buffer);
    udp.endPacket();

    Serial.println(buffer);
  }

  delay(250);
}