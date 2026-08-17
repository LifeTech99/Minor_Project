#include <SPI.h>
#include <LoRa.h>
#include <Wire.h>
#include <TinyGPS++.h>
#include <SoftwareSerial.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <math.h>

// CONFIGURATION
//#define ANIMAL_ID "A01"
#define ANIMAL_ID "A02"
#define LORA_FREQUENCY 433E6
#define GPS_RX 4
#define GPS_TX 3
#define BATTERY_PIN A0
#define MAX_FENCE_POINTS 4
#define LIVE_INTERVAL 5000UL

// HARDWARE OBJECTS
SoftwareSerial gpsSerial(GPS_RX, GPS_TX);
TinyGPSPlus gps;
Adafruit_MPU6050 mpu;

// BATTERY
float batteryVoltage = 0.0;

// LIVE MODE
bool liveMode = false;
unsigned long lastLiveSend = 0;

bool pollRequested = false;

// MOVEMENT
float filteredAcceleration = 9.81;
float previousAcceleration = 9.81;
float accelerationChange = 0.0;
float gyroMagnitude = 0.0;
bool animalMoving = false;
byte movementCount = 0;
byte stationaryCount = 0;

// MOVEMENT SETTINGS
#define ACCEL_THRESHOLD 0.35
#define GYRO_THRESHOLD 0.15
#define MOVEMENT_CONFIRM 5
#define STATIONARY_CONFIRM 15
#define FILTER_ALPHA 0.20

// GEOFENCE
struct FencePoint
{
  float lat;
  float lon;
};
FencePoint fence[MAX_FENCE_POINTS];
byte fenceCount = 0;

// GEOFENCE STATE
bool fenceStateKnown = false;
bool animalInside = false;

// DEBUG
#define DEBUG 1

// DEBUG PRINT HELPERS
#if DEBUG
void debugText(const __FlashStringHelper *text)
{
  Serial.println(text);
}
#endif

// LOAD TEST FENCE
// Temporary fence.
// Later ESP8266 will send this.
void loadTestFence()
{
  fenceCount = 4;
  fence[0].lat = 27.68600;
  fence[0].lon = 85.29500;

  fence[1].lat = 27.68800;
  fence[1].lon = 85.29500;

  fence[2].lat = 27.68800;
  fence[2].lon = 85.29800;

  fence[3].lat = 27.68600;
  fence[3].lon = 85.29800;

#if DEBUG
  Serial.print(F("Fence points: "));
  Serial.println(fenceCount);
#endif
}

// POINT IN POLYGON
bool insideFence(float lat, float lon)
{
  if (fenceCount < 3)
  {
    return false;
  }

  bool inside = false;
  byte j = fenceCount - 1;

  for (byte i = 0; i < fenceCount; i++)
  {
    float latI = fence[i].lat;
    float lonI = fence[i].lon;

    float latJ = fence[j].lat;
    float lonJ = fence[j].lon;

    if (
      ((lonI > lon) != (lonJ > lon)) &&
      (
        lat <
        (
          (latJ - latI) *
          (lon - lonI) /
          (lonJ - lonI) +
          latI
        )
      )
    )
    {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}

// SEND GEOFENCE ALERT
void sendAlert(bool exitAlert)
{
  LoRa.beginPacket();

  LoRa.print(F("ALERT,"));
  LoRa.print(F(ANIMAL_ID));
  LoRa.print(',');

  if (exitAlert)
  {
    LoRa.print(F("EXIT"));
  }
  else
  {
    LoRa.print(F("RETURN"));
  }

  LoRa.print(',');

  if (gps.location.isValid())
  {
    LoRa.print(gps.location.lat(), 5);
    LoRa.print(',');

    LoRa.print(gps.location.lng(), 5);
    LoRa.print(',');

    LoRa.print(gps.altitude.meters(), 1);
  }
  else
  {
    LoRa.print(F("0,0,0"));
  }

  LoRa.endPacket();

#if DEBUG
  Serial.println();
  Serial.println(F("GEOFENCE ALERT"));
  Serial.print(F("Animal: "));
  Serial.println(F(ANIMAL_ID));

  if (exitAlert)
  {
    Serial.println(F("Type: EXIT"));
  }
  else
  {
    Serial.println(F("Type: RETURN"));
  }

#endif
}

// CHECK GEOFENCE
void checkGeofence()
{
  if (!gps.location.isValid())
  {
    return;
  }

  float lat = gps.location.lat();
  float lon = gps.location.lng();

  bool inside = insideFence(lat, lon);

  // First valid position
  if (!fenceStateKnown)
  {
    fenceStateKnown = true;
    animalInside = inside;

#if DEBUG

    Serial.println();
    Serial.println(F("INITIAL GEOFENCE"));
    if (inside)
    {
      Serial.println(F("Animal INSIDE"));
    }
    else
    {
      Serial.println(F("Animal OUTSIDE"));
      sendAlert(true);
    }

#endif

    return;
  }

  // State changed
  if (inside != animalInside)
  {
    animalInside = inside;
    if (inside)
    {
      sendAlert(false);
    }
    else
    {
      sendAlert(true);
    }
  }
}

// ============================================================
// RECEIVE POLL COMMAND
//
// Expected:
// POLL,A01
// POLL,A02
// POLL,A03
// ============================================================

void receivePollCommand(String packet)
{
  String expected = "POLL," + String(ANIMAL_ID);

  if (packet != expected)
  {
    return;
  }

#if DEBUG
  Serial.println();
  Serial.println(F("POLL RECEIVED"));
  Serial.print(F("Animal: "));
  Serial.println(F(ANIMAL_ID));
#endif

  // Only transmit if LIVE mode is enabled
  if (liveMode)
  {
    sendTelemetry();
  }
}

// SEND LIVE TELEMETRY
void sendTelemetry()
{
  LoRa.beginPacket();

  LoRa.print(F("DATA,"));
  LoRa.print(F(ANIMAL_ID));
  LoRa.print(',');
  LoRa.print(batteryVoltage, 2);
  LoRa.print(',');

  // GPS
  if (gps.location.isValid())
  {
    LoRa.print(gps.location.lat(), 5);
    LoRa.print(',');

    LoRa.print(gps.location.lng(), 5);
    LoRa.print(',');

    LoRa.print(gps.altitude.meters(), 1);
    LoRa.print(',');

    LoRa.print(gps.satellites.value());
    LoRa.print(',');

    LoRa.print(gps.speed.kmph(), 2);
    LoRa.print(',');
  }
  else
  {
    LoRa.print(F("0,0,0,0,0,"));
  }

  // Movement
  if (animalMoving)
  {
    LoRa.print('1');
  }
  else
  {
    LoRa.print('0');
  }

  LoRa.endPacket();

#if DEBUG
  Serial.println(F("Telemetry sent"));
#endif
}

// ============================================================
// SEND COMMAND ACK
//
// Example:
// ACK,A02,LIVE,OFF
// ACK,A02,FENCE
// ============================================================
void sendCommandAck(const char *command, const char *value = "")
{
  LoRa.beginPacket();

  LoRa.print(F("ACK,"));
  LoRa.print(F(ANIMAL_ID));
  LoRa.print(',');

  LoRa.print(command);

  if (value[0] != '\0')
  {
    LoRa.print(',');
    LoRa.print(value);
  }

  LoRa.endPacket();

#if DEBUG
  Serial.print(F("ACK sent: "));
  Serial.print(ANIMAL_ID);
  Serial.print(F(","));
  Serial.print(command);

  if (value[0] != '\0')
  {
    Serial.print(F(","));
    Serial.print(value);
  }

  Serial.println();
#endif
}

// ============================================================
// PROCESS LIVE COMMAND
//
// Expected:
// LIVE,A01,ON
// LIVE,A01,OFF
// ============================================================
void processLiveCommand(String packet)
{
  if (!isForThisAnimal(packet))
  {
#if DEBUG
    Serial.println(F("LIVE command for another animal"));
#endif
    return;
  }

  int secondComma = packet.indexOf(',', 5);

  if (secondComma < 0)
  {
    return;
  }

  String state = packet.substring(secondComma + 1);
  state.trim();

  // ----------------------------------------------------------
  // LIVE ON
  // ----------------------------------------------------------

  if (state == "ON")
  {
    liveMode = true;

    // Send telemetry immediately
    lastLiveSend = millis() - LIVE_INTERVAL;

    // Tell base that command was received
    sendCommandAck("LIVE", "ON");

#if DEBUG
    Serial.println();
    Serial.println(F("================================"));
    Serial.println(F("LIVE ON"));
    Serial.print(F("Animal: "));
    Serial.println(ANIMAL_ID);
    Serial.println(F("================================"));
#endif
  }

  // ----------------------------------------------------------
  // LIVE OFF
  // ----------------------------------------------------------

  else if (state == "OFF")
  {
    // IMPORTANT:
    // Stop live transmission immediately.
    liveMode = false;

    // Tell base that OFF was received
    sendCommandAck("LIVE", "OFF");

#if DEBUG
    Serial.println();
    Serial.println(F("================================"));
    Serial.println(F("LIVE OFF"));
    Serial.print(F("Animal: "));
    Serial.println(ANIMAL_ID);
    Serial.println(F("================================"));
#endif
  }
}
// ============================================================
// PROCESS FENCE COMMAND
//
// Expected:
//
// FENCE,A02,4,
// 27.68600,85.29500,
// 27.68800,85.29500,
// 27.68800,85.29800,
// 27.68600,85.29800
// ============================================================
void processFenceCommand(String packet)
{
  if (!isForThisAnimal(packet))
  {
#if DEBUG
    Serial.println(F("FENCE command for another animal"));
#endif
    return;
  }

  // ----------------------------------------------------------
  // Find ID and point count
  // ----------------------------------------------------------

  int comma1 = packet.indexOf(',');
  int comma2 = packet.indexOf(',', comma1 + 1);
  int comma3 = packet.indexOf(',', comma2 + 1);

  if (
    comma1 < 0 ||
    comma2 < 0 ||
    comma3 < 0
  )
  {
#if DEBUG
    Serial.println(F("Invalid FENCE command"));
#endif
    return;
  }

  String countText = packet.substring(
    comma2 + 1,
    comma3
  );

  int newCount = countText.toInt();

  // ----------------------------------------------------------
  // Validate point count
  // ----------------------------------------------------------

  if (
    newCount < 3 ||
    newCount > MAX_FENCE_POINTS
  )
  {
#if DEBUG
    Serial.println(F("Invalid fence point count"));
#endif
    return;
  }

  // ----------------------------------------------------------
  // Parse fence points
  //
  // Packet format:
  //
  // FENCE,A02,4,
  // lat,lon,
  // lat,lon,
  // lat,lon,
  // lat,lon
  // ----------------------------------------------------------

  int position = comma3 + 1;

  for (byte i = 0; i < newCount; i++)
  {
    // Latitude start
    int commaLat = packet.indexOf(',', position);

    if (commaLat < 0)
    {
#if DEBUG
      Serial.println(F("Invalid latitude"));
#endif
      return;
    }

    String latText = packet.substring(
      position,
      commaLat
    );

    position = commaLat + 1;

    // Longitude start
    int commaLon = packet.indexOf(',', position);

    String lonText;

    if (commaLon >= 0)
    {
      lonText = packet.substring(
        position,
        commaLon
      );

      position = commaLon + 1;
    }
    else
    {
      // Last longitude
      lonText = packet.substring(position);
      lonText.trim();
      position = packet.length();
    }

    fence[i].lat = latText.toFloat();
    fence[i].lon = lonText.toFloat();
  }

  // ----------------------------------------------------------
  // Activate new fence
  // ----------------------------------------------------------

  fenceCount = newCount;

  // Force geofence state recalculation
  fenceStateKnown = false;
  // Tell base that fence was received
  sendCommandAck("FENCE", "OK");

#if DEBUG
  Serial.println();
  Serial.println(F("================================"));
  Serial.println(F("FENCE UPDATED"));

  Serial.print(F("Animal: "));
  Serial.println(ANIMAL_ID);

  Serial.print(F("Points: "));
  Serial.println(fenceCount);

  for (byte i = 0; i < fenceCount; i++)
  {
    Serial.print(i);
    Serial.print(F(": "));

    Serial.print(fence[i].lat, 5);
    Serial.print(F(", "));

    Serial.println(fence[i].lon, 5);
  }

  Serial.println(F("================================"));
#endif
}
// ============================================================
// READ COMPLETE LORA PACKET
// ============================================================
String readLoRaPacket()
{
  String packet = "";

  while (LoRa.available())
  {
    packet += (char)LoRa.read();
  }

  return packet;
}


// ============================================================
// CHECK WHETHER COMMAND IS FOR THIS ANIMAL
// Example:
// LIVE,A02,ON
//
// For A02:
// returns true
//
// For A01:
// returns false
// ============================================================
bool isForThisAnimal(String packet)
{
  int firstComma = packet.indexOf(',');

  if (firstComma < 0)
  {
    return false;
  }

  int secondComma = packet.indexOf(',', firstComma + 1);

  if (secondComma < 0)
  {
    return false;
  }

  String targetID = packet.substring(
    firstComma + 1,
    secondComma
  );

  targetID.trim();

  return targetID == ANIMAL_ID;
}

// ============================================================
// RECEIVE LORA COMMAND
// ============================================================

void receiveCommand()
{
  int packetSize = LoRa.parsePacket();

  if (packetSize <= 0)
  {
    return;
  }

  String packet = "";

  while (LoRa.available())
  {
    packet += (char)LoRa.read();
  }

  packet.trim();

#if DEBUG
  Serial.println();
  Serial.println(F("LoRa command received:"));
  Serial.println(packet);
#endif

  // ----------------------------------------------------------
  // POLL
  // ----------------------------------------------------------

  if (packet.startsWith("POLL,"))
  {
    receivePollCommand(packet);
    return;
  }

  // ----------------------------------------------------------
  // LIVE
  // ----------------------------------------------------------

  if (packet.startsWith("LIVE,"))
  {
    processLiveCommand(packet);
    return;
  }

  // ----------------------------------------------------------
  // FENCE
  // ----------------------------------------------------------

  if (packet.startsWith("FENCE,"))
  {
    processFenceCommand(packet);
    return;
  }

#if DEBUG
  Serial.println(F("Unknown LoRa command"));
#endif
}

// PRINT BASIC STATUS
#if DEBUG
void printStatus()
{
  Serial.println();
  Serial.println(F("-------------------------"));
  Serial.print(F("Battery: "));
  Serial.print(batteryVoltage, 2);
  Serial.println(F(" V"));
  if (gps.location.isValid())
  {
    Serial.print(F("Lat: "));
    Serial.println(gps.location.lat(), 5);

    Serial.print(F("Lon: "));
    Serial.println(gps.location.lng(), 5);

    Serial.print(F("Alt: "));
    Serial.println(gps.altitude.meters(), 1);

    Serial.print(F("Sat: "));
    Serial.println(gps.satellites.value());

    Serial.print(F("Speed: "));
    Serial.println(gps.speed.kmph(), 2);
  }
  Serial.print(F("Movement: "));

  if (animalMoving)
  {
    Serial.println(F("MOVING"));
  }
  else
  {
    Serial.println(F("STATIONARY"));
  }
  Serial.print(F("Fence: "));
  if (animalInside)
  {
    Serial.println(F("INSIDE"));
  }
  else
  {
    Serial.println(F("OUTSIDE"));
  }

  Serial.print(F("Live: "));
  if (liveMode)
  {
    Serial.println(F("ON"));
  }
  else
  {
    Serial.println(F("OFF"));
  }
  Serial.println(F("-------------------------"));
}
#endif

// FREE RAM
int freeRam()
{
  extern int __heap_start;
  extern int *__brkval;
  int v;
  return (int)&v -
         (
           __brkval == 0
           ? (int)&__heap_start
           : (int)__brkval
         );
}

// SETUP
void setup()
{
  Serial.begin(9600);

  gpsSerial.begin(9600);

  Wire.begin();

  // Startup
  Serial.println();
  Serial.println(F("LIVESTOCK ANIMAL NODE"));
  Serial.print(F("Animal: "));
  Serial.println(F(ANIMAL_ID));

  // LoRa
  Serial.println(F("Starting LoRa..."));
  if (!LoRa.begin(LORA_FREQUENCY))
  {
    Serial.println(F("LoRa FAILED"));
    while (1);
  }
 /*
  LoRa.setSpreadingFactor(7);
  LoRa.setSignalBandwidth(125E3);
  LoRa.setCodingRate4(5);
  Serial.println(F("LoRa OK"));
  */
  // LONG RANGE SETTINGS
  LoRa.setTxPower(18);
  LoRa.setSpreadingFactor(12);
  LoRa.setSignalBandwidth(125E3);
  LoRa.setCodingRate4(8);
  LoRa.setPreambleLength(12);

Serial.println(F("LoRa OK"));
Serial.println(F("TX Power: 18 dBm"));
Serial.println(F("SF: 12"));
Serial.println(F("BW: 125 kHz"));
Serial.println(F("CR: 4/8"));

  // MPU
  Serial.println(F("Starting MPU6050..."));
  if (!mpu.begin())
  {
    Serial.println(F("MPU FAILED"));
    while (1);
  }

  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  Serial.println(F("MPU OK"));

  // Fence
  loadTestFence();

  // Battery
  readBattery();

  // Ready
  Serial.println(F("GPS ready"));
  Serial.println(F("Animal node ready"));
  Serial.print(F("Free RAM: "));
  Serial.println(freeRam());
}

void loop()
{
  // GPS
  readGPS();

  // MPU
  readMPU();

  // LoRa commands
  receiveCommand();

  // Geofence
  checkGeofence();
}

// READ GPS
void readGPS()
{
  while (gpsSerial.available())
  {
    gps.encode(gpsSerial.read());
  }
}

// READ MPU6050
void readMPU()
{
  sensors_event_t a;
  sensors_event_t g;
  sensors_event_t temp;
  mpu.getEvent(&a, &g, &temp);

  // Acceleration magnitude
  float acceleration = sqrt(a.acceleration.x * a.acceleration.x + a.acceleration.y * a.acceleration.y + a.acceleration.z * a.acceleration.z);

  // Low pass filter
  filteredAcceleration = FILTER_ALPHA * acceleration +(1.0 - FILTER_ALPHA) * filteredAcceleration;

  // Acceleration change
  accelerationChange = fabs(filteredAcceleration - previousAcceleration);
  previousAcceleration = filteredAcceleration;

  // Gyroscope magnitude
  gyroMagnitude = sqrt( g.gyro.x * g.gyro.x + g.gyro.y * g.gyro.y + g.gyro.z * g.gyro.z);

  // Movement detection
  bool movementDetected = accelerationChange > ACCEL_THRESHOLD || gyroMagnitude > GYRO_THRESHOLD;

  // State machine
  if (movementDetected)
  {
    movementCount++;
    stationaryCount = 0;

    if (movementCount >= MOVEMENT_CONFIRM)
    {
      animalMoving = true;
      movementCount = MOVEMENT_CONFIRM;
    }
  }
  else
  {
    stationaryCount++;
    movementCount = 0;

    if (stationaryCount >= STATIONARY_CONFIRM)
    {
      animalMoving = false;
      stationaryCount = STATIONARY_CONFIRM;
    }
  }
}

// READ BATTERY
void readBattery()
{
  int adc = analogRead(BATTERY_PIN);
  float voltage = adc * (5.0 / 1023.0);
  batteryVoltage = voltage * 2;
  //batteryVoltage = voltage * 1;

}