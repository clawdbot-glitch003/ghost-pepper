#include <Arduino.h>
#include <ArduinoJson.h>
#include <BleKeyboard.h>

#ifndef BLE_DEVICE_NAME
#define BLE_DEVICE_NAME "GhostPepper-Keyboard"
#endif

#ifndef BLE_DEVICE_MANUFACTURER
#define BLE_DEVICE_MANUFACTURER "Ghost Pepper"
#endif

#ifndef DEFAULT_CHAR_DELAY_MS
#define DEFAULT_CHAR_DELAY_MS 8
#endif

namespace {
constexpr uint32_t kSerialBaud = 115200;
constexpr size_t kMaxLineLength = 2048;
constexpr uint16_t kMinCharDelayMs = 0;
constexpr uint16_t kMaxCharDelayMs = 250;

BleKeyboard bleKeyboard(BLE_DEVICE_NAME, BLE_DEVICE_MANUFACTURER, 100);
String inputLine;
uint32_t commandCount = 0;

uint16_t clampDelay(int requestedDelayMs) {
  if (requestedDelayMs < kMinCharDelayMs) {
    return kMinCharDelayMs;
  }
  if (requestedDelayMs > kMaxCharDelayMs) {
    return kMaxCharDelayMs;
  }
  return static_cast<uint16_t>(requestedDelayMs);
}

void logStatus(const __FlashStringHelper *message) {
  Serial.print(F("{\"status\":\""));
  Serial.print(message);
  Serial.println(F("\"}"));
}

void logError(const char *message) {
  Serial.print(F("{\"error\":\""));
  Serial.print(message);
  Serial.println(F("\"}"));
}

bool startsWithAt(const char *text, size_t index, const char *needle) {
  size_t offset = 0;
  while (needle[offset] != '\0') {
    if (text[index + offset] != needle[offset]) {
      return false;
    }
    offset++;
  }
  return true;
}

size_t appendAsciiReplacement(const char *text, size_t index, String &out) {
  // Normalize common UTF-8 punctuation emitted by macOS/dictation cleanup.
  if (startsWithAt(text, index, "\xE2\x80\x98") || startsWithAt(text, index, "\xE2\x80\x99")) {
    out += '\'';
    return 3;
  }
  if (startsWithAt(text, index, "\xE2\x80\x9C") || startsWithAt(text, index, "\xE2\x80\x9D")) {
    out += '"';
    return 3;
  }
  if (startsWithAt(text, index, "\xE2\x80\x93") || startsWithAt(text, index, "\xE2\x80\x94")) {
    out += '-';
    return 3;
  }
  if (startsWithAt(text, index, "\xE2\x80\xA6")) {
    out += "...";
    return 3;
  }
  if (startsWithAt(text, index, "\xC2\xA0")) {
    out += ' ';
    return 2;
  }
  return 0;
}

String normalizeForUsKeyboard(const char *text) {
  String normalized;
  normalized.reserve(strlen(text));

  for (size_t i = 0; text[i] != '\0';) {
    const uint8_t c = static_cast<uint8_t>(text[i]);
    if (c == '\n' || c == '\r' || c == '\t' || (c >= 0x20 && c <= 0x7E)) {
      normalized += static_cast<char>(c);
      i++;
      continue;
    }

    const size_t consumed = appendAsciiReplacement(text, i, normalized);
    if (consumed > 0) {
      i += consumed;
      continue;
    }

    // Skip unsupported UTF-8 code point bytes. Continuation bytes are skipped
    // one-by-one if the leading byte was malformed.
    if ((c & 0xE0) == 0xC0 && text[i + 1] != '\0') {
      i += 2;
    } else if ((c & 0xF0) == 0xE0 && text[i + 1] != '\0' && text[i + 2] != '\0') {
      i += 3;
    } else if ((c & 0xF8) == 0xF0 && text[i + 1] != '\0' && text[i + 2] != '\0' && text[i + 3] != '\0') {
      i += 4;
    } else {
      i++;
    }
  }

  return normalized;
}

void typeText(const String &text, uint16_t charDelayMs) {
  for (size_t i = 0; i < text.length(); i++) {
    const char c = text[i];
    if (c == '\n' || c == '\r') {
      bleKeyboard.write(KEY_RETURN);
    } else if (c == '\t') {
      bleKeyboard.write(KEY_TAB);
    } else {
      bleKeyboard.print(c);
    }

    if (charDelayMs > 0) {
      delay(charDelayMs);
    }
  }
}

void handleLine(const String &line) {
  if (line.length() == 0) {
    return;
  }

  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, line);
  if (error) {
    logError(error.c_str());
    return;
  }

  const char *type = doc["type"] | "";
  if (strcmp(type, "ping") == 0) {
    Serial.println(F("{\"ok\":true,\"type\":\"pong\"}"));
    return;
  }

  if (strcmp(type, "text") != 0) {
    logError("unsupported command type");
    return;
  }

  const char *text = doc["text"] | nullptr;
  if (text == nullptr) {
    logError("missing text");
    return;
  }

  if (!bleKeyboard.isConnected()) {
    logError("ble keyboard not connected");
    return;
  }

  const uint16_t charDelayMs = clampDelay(doc["delay_ms"] | DEFAULT_CHAR_DELAY_MS);
  const String normalized = normalizeForUsKeyboard(text);
  typeText(normalized, charDelayMs);

  commandCount++;
  Serial.print(F("{\"ok\":true,\"type\":\"text\",\"chars\":"));
  Serial.print(normalized.length());
  Serial.print(F(",\"commands\":"));
  Serial.print(commandCount);
  Serial.println(F("}"));
}

void pollSerial() {
  while (Serial.available() > 0) {
    const char c = static_cast<char>(Serial.read());
    if (c == '\n') {
      inputLine.trim();
      handleLine(inputLine);
      inputLine = "";
      continue;
    }

    if (c == '\r') {
      continue;
    }

    if (inputLine.length() >= kMaxLineLength) {
      inputLine = "";
      logError("line too long");
      continue;
    }

    inputLine += c;
  }
}
}  // namespace

void setup() {
  Serial.begin(kSerialBaud);
  inputLine.reserve(kMaxLineLength);
  delay(250);

  Serial.println(F("Ghost Pepper ESP32 BLE keyboard bridge starting."));
  Serial.print(F("BLE device name: "));
  Serial.println(BLE_DEVICE_NAME);
  Serial.println(F("Flash note: this firmware replaces Meshtastic until you reflash Meshtastic."));

  bleKeyboard.begin();
  logStatus(F("advertising"));
}

void loop() {
  static bool wasConnected = false;
  const bool connected = bleKeyboard.isConnected();
  if (connected != wasConnected) {
    wasConnected = connected;
    if (connected) {
      logStatus(F("ble keyboard connected"));
    } else {
      logStatus(F("advertising"));
    }
  }

  pollSerial();
  delay(1);
}
