#include <SPI.h>
#include <LoRa.h>

#include <ESP8266WiFi.h>
#include <WebSocketsServer.h>

// =====================================================
// WIFI ACCESS POINT
// =====================================================

const char* ssid = "ESP8266_Control";
const char* password = "12345678";

WebSocketsServer webSocket = WebSocketsServer(81);


// =====================================================
// LORA PINS
// =====================================================

#define LORA_SS    15   // D8
#define LORA_RST   16   // D0
#define LORA_DIO0   4   // D2


// =====================================================
// BASE STATION
// =====================================================

const char* BASE_STATION_ID = "BASE01";

const int BATTERY_PIN = A0;

const float R1 = 10000.0;
const float R2 = 10000.0;

float baseStationBattery = 0;


// =====================================================
// ANIMAL DATA
// =====================================================

String deviceID = "";

float nodeBattery = 0;

float latitude = 0;
float longitude = 0;
float altitude = 0;

int satellites = 0;

float speed = 0;

int animalMoving = 0;

String gpsTimestamp = "";


// =====================================================
// LORA INFORMATION
// =====================================================

int lastRSSI = 0;
float lastSNR = 0;
int lastPacketSize = 0;

unsigned long lastPacketTime = 0;


// =====================================================
// TIMING
// =====================================================

unsigned long lastBatteryRead = 0;

const unsigned long BATTERY_INTERVAL = 5000;
unsigned long lastBaseStationSend = 0;
const unsigned long BASE_STATION_INTERVAL = 5000;


// =====================================================
// READ BASE STATION BATTERY
// =====================================================

void ReadBaseStationBattery()
{
  int adcValue = analogRead(BATTERY_PIN);

  float voltageA0 =
    adcValue * (3.2 / 1023.0);

  baseStationBattery =
    voltageA0 * ((R1 + R2) / R2);
}


// =====================================================
// READ LORA PACKET
// =====================================================

String ReadPacket()
{
  String packet = "";

  while (LoRa.available())
  {
    packet += (char)LoRa.read();
  }

  return packet;
}


// =====================================================
// PARSE LORA PACKET
//
// DEVICE_ID,
// BATTERY,
// LATITUDE,
// LONGITUDE,
// ALTITUDE,
// SATELLITES,
// SPEED,
// MOVEMENT,
// TIMESTAMP
// =====================================================

bool ParsePacket(String packet)
{
  packet.trim();

  String value[9];

  int index = 0;

  while (packet.length() > 0 && index < 9)
  {
    int commaIndex =
      packet.indexOf(',');

    if (commaIndex == -1)
    {
      value[index] = packet;

      index++;

      break;
    }

    value[index] =
      packet.substring(
        0,
        commaIndex
      );

    packet =
      packet.substring(
        commaIndex + 1
      );

    index++;
  }


  // Must have exactly 9 fields

  if (index != 9)
  {
    Serial.println(
      "ERROR: Invalid LoRa packet"
    );

    return false;
  }


  // =================================================
  // Store data
  // =================================================

  deviceID = value[0];

  nodeBattery =
    value[1].toFloat();

  latitude =
    value[2].toFloat();

  longitude =
    value[3].toFloat();

  altitude =
    value[4].toFloat();

  satellites =
    value[5].toInt();

  speed =
    value[6].toFloat();

  animalMoving =
    value[7].toInt();

  gpsTimestamp =
    value[8];


  return true;
}


// =====================================================
// CREATE ANIMAL JSON
// =====================================================

String CreateAnimalJSON()
{
  String json = "{";


  json += "\"type\":\"animal\"";


  // Device ID

  json += ",\"device_id\":\"";
  json += deviceID;
  json += "\"";


  // Battery

  json += ",\"battery\":";
  json += String(
    nodeBattery,
    2
  );


  // Latitude

  json += ",\"latitude\":";
  json += String(
    latitude,
    5
  );


  // Longitude

  json += ",\"longitude\":";
  json += String(
    longitude,
    5
  );


  // Altitude

  json += ",\"altitude\":";
  json += String(
    altitude,
    1
  );


  // Satellites

  json += ",\"satellites\":";
  json += satellites;


  // Speed

  json += ",\"speed\":";
  json += String(
    speed,
    2
  );


  // Movement

  json += ",\"movement\":";
  json += animalMoving;


  // GPS timestamp

  json += ",\"timestamp\":\"";
  json += gpsTimestamp;
  json += "\"";


  // LoRa RSSI

  json += ",\"rssi\":";
  json += lastRSSI;


  // LoRa SNR

  json += ",\"snr\":";
  json += String(
    lastSNR,
    2
  );


  json += "}";

  return json;
}


// =====================================================
// CREATE BASE STATION JSON
// =====================================================

String CreateBaseStationJSON()
{
  String json = "{";


  json += "\"type\":\"base_station\"";


  // Base station ID

  json += ",\"device_id\":\"";
  json += BASE_STATION_ID;
  json += "\"";


  // Battery

  json += ",\"battery\":";
  json += String(
    baseStationBattery,
    2
  );


  // Uptime

  json += ",\"uptime\":";
  json += millis();


  json += "}";


  return json;
}


// =====================================================
// SEND ANIMAL DATA
// =====================================================

void SendAnimalData()
{
  String json =
    CreateAnimalJSON();

  webSocket.broadcastTXT(json);


  Serial.println(
    "Data sent to WebSocket clients"
  );
}


// =====================================================
// SEND BASE STATION STATUS
// =====================================================

void SendBaseStationData()
{
  String json =
    CreateBaseStationJSON();

  webSocket.broadcastTXT(json);


  Serial.println(
    "Base station status sent"
  );
}


// =====================================================
// CHECK LORA
// =====================================================

void CheckLoRa()
{
  int packetSize =
    LoRa.parsePacket();


  if (!packetSize)
  {
    return;
  }


  // Read packet

  String receivedPacket =
    ReadPacket();


  Serial.println();
  Serial.println(
    "================================"
  );

  Serial.println(
    "LoRa Packet Received"
  );

  Serial.print(
    "Raw Packet: "
  );

  Serial.println(
    receivedPacket
  );


  // Parse

  if (ParsePacket(receivedPacket))
  {
    // LoRa information

    lastRSSI =
      LoRa.packetRssi();

    lastSNR =
      LoRa.packetSnr();

    lastPacketSize =
      packetSize;

    lastPacketTime =
      millis();


    Serial.println(
      "Packet parsed successfully"
    );


    Serial.print(
      "Device ID: "
    );

    Serial.println(
      deviceID
    );


    Serial.print(
      "Battery: "
    );

    Serial.print(
      nodeBattery,
      2
    );

    Serial.println(
      " V"
    );


    Serial.print(
      "Latitude: "
    );

    Serial.println(
      latitude,
      5
    );


    Serial.print(
      "Longitude: "
    );

    Serial.println(
      longitude,
      5
    );


    Serial.print(
      "Movement: "
    );

    if (animalMoving)
    {
      Serial.println(
        "MOVING"
      );
    }
    else
    {
      Serial.println(
        "STATIONARY"
      );
    }


    Serial.print(
      "Timestamp: "
    );

    Serial.println(
      gpsTimestamp
    );


    Serial.print(
      "RSSI: "
    );

    Serial.println(
      lastRSSI
    );


    Serial.print(
      "SNR: "
    );

    Serial.println(
      lastSNR,
      2
    );


    // Send immediately to Flutter

    SendAnimalData();
  }


  Serial.println(
    "================================"
  );
}


// =====================================================
// WEBSOCKET EVENT
// =====================================================

void webSocketEvent(
  uint8_t num,
  WStype_t type,
  uint8_t *payload,
  size_t length
)
{
  switch (type)
  {

    // ================================================
    // CLIENT CONNECTED
    // ================================================

    case WStype_CONNECTED:
    {
      Serial.print(
        "WebSocket client connected: "
      );

      Serial.println(
        num
      );


      // Send current base station status

      String json =
        CreateBaseStationJSON();

      webSocket.sendTXT(
        num,
        json
      );


      break;
    }


    // ================================================
    // CLIENT DISCONNECTED
    // ================================================

    case WStype_DISCONNECTED:
    {
      Serial.print(
        "WebSocket client disconnected: "
      );

      Serial.println(
        num
      );

      break;
    }


    // ================================================
    // TEXT MESSAGE
    // ================================================

    case WStype_TEXT:
    {
      Serial.print(
        "WebSocket message received: "
      );

      Serial.println(
        (char*)payload
      );

      break;
    }


    default:
      break;
  }
}


// =====================================================
// SETUP
// =====================================================

void setup()
{
  Serial.begin(115200);


  // ===================================================
  // LED
  // ===================================================

  pinMode(
    LED_BUILTIN,
    OUTPUT
  );

  digitalWrite(
    LED_BUILTIN,
    HIGH
  );


  // ===================================================
  // WIFI AP
  // ===================================================

  WiFi.mode(
    WIFI_AP
  );

  WiFi.softAP(
    ssid,
    password
  );


  Serial.println();

  Serial.println(
    "================================"
  );

  Serial.println(
    "ESP8266 LIVESTOCK BASE STATION"
  );

  Serial.println(
    "================================"
  );


  Serial.print(
    "SSID: "
  );

  Serial.println(
    ssid
  );


  Serial.print(
    "IP Address: "
  );

  Serial.println(
    WiFi.softAPIP()
  );


  // ===================================================
  // LORA
  // ===================================================

  SPI.begin();


  LoRa.setPins(
    LORA_SS,
    LORA_RST,
    LORA_DIO0
  );


  Serial.println();

  Serial.println(
    "Initializing LoRa..."
  );


  if (!LoRa.begin(433E6))
  {
    Serial.println(
      "LoRa initialization FAILED!"
    );


    while (true)
    {
      delay(1000);
    }
  }


  LoRa.setFrequency(
    433E6
  );

  LoRa.setSpreadingFactor(
    7
  );

  LoRa.setSignalBandwidth(
    125E3
  );

  LoRa.setCodingRate4(
    5
  );


  Serial.println(
    "LoRa initialization SUCCESS!"
  );


  // ===================================================
  // BATTERY
  // ===================================================

  ReadBaseStationBattery();


  // ===================================================
  // WEBSOCKET
  // ===================================================

  webSocket.begin();

  webSocket.onEvent(
    webSocketEvent
  );


  Serial.println();

  Serial.println(
    "WebSocket Server Started"
  );

  Serial.println(
    "WebSocket: ws://192.168.4.1:81/"
  );


  Serial.println();

  Serial.println(
    "Base Station Ready!"
  );

  Serial.println(
    "================================"
  );
}


// =====================================================
// LOOP
// =====================================================

void loop()
{
  // ===================================================
  // WebSocket
  // ===================================================

  webSocket.loop();


  // ===================================================
  // LoRa
  // ===================================================

  CheckLoRa();


  // ===================================================
  // Base station battery + status
  // ===================================================

  if (
    millis() - lastBaseStationSend >=
    BASE_STATION_INTERVAL
  )
  {
    lastBaseStationSend = millis();

    // Read latest base station battery
    ReadBaseStationBattery();

    // Send base station status to Flutter
    SendBaseStationData();
  }
}