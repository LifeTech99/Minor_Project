#include <SPI.h>
#include <LoRa.h>
#include <Wire.h>
#include <TinyGPS++.h>
#include <SoftwareSerial.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <math.h>

// ============================================================
// DEVICE
// ============================================================

const char DEVICE_ID[] = "A01";

// ============================================================
// GPS
// GPS TX -> Nano D4
// GPS RX -> Nano D3
// ============================================================

SoftwareSerial gpsSerial(4, 3);
TinyGPSPlus gps;

// ============================================================
// MPU6050
// ============================================================

Adafruit_MPU6050 mpu;

// ============================================================
// BATTERY
// ============================================================

const int BATTERY_PIN = A0;

const float R1 = 10000.0;
const float R2 = 10000.0;

float batteryVoltage = 0.0;

// ============================================================
// LORA
// ============================================================

const long LORA_FREQUENCY = 433E6;

// ============================================================
// TRANSMISSION
// ============================================================

unsigned long lastSendTime = 0;

const unsigned long SEND_INTERVAL = 5000;

// ============================================================
// MPU DATA
// ============================================================

float ax = 0.0;
float ay = 0.0;
float az = 0.0;

float gx = 0.0;
float gy = 0.0;
float gz = 0.0;

float accelerationMagnitude = 0.0;

float filteredAcceleration = 9.81;
float previousAcceleration = 9.81;

float accelerationChange = 0.0;
float gyroMagnitude = 0.0;

// ============================================================
// MOVEMENT STATE
// ============================================================

bool animalMoving = false;

// ============================================================
// MOVEMENT THRESHOLDS
// ============================================================

const float ACCEL_MOVEMENT_THRESHOLD = 0.35;
const float GYRO_MOVEMENT_THRESHOLD  = 0.15;

// ============================================================
// FILTER
// ============================================================

const float FILTER_ALPHA = 0.20;

// ============================================================
// MOVEMENT CONFIRMATION
// ============================================================

int movementCount = 0;
int stationaryCount = 0;

const int MOVEMENT_CONFIRM_COUNT = 5;
const int STATIONARY_CONFIRM_COUNT = 15;


// ============================================================
// SETUP
// ============================================================

void setup()
{
  Serial.begin(9600);

  gpsSerial.begin(9600);

  Wire.begin();

  Serial.println();
  Serial.println(F("================================"));
  Serial.println(F("GPS + MPU6050 + LoRa Sender"));
  Serial.println(F("================================"));

  Serial.print(F("Device ID: "));
  Serial.println(DEVICE_ID);

  // ----------------------------------------------------------
  // LORA
  // ----------------------------------------------------------

  Serial.println(F("Initializing LoRa..."));

  if (!LoRa.begin(LORA_FREQUENCY))
  {
    Serial.println(F("Starting LoRa failed!"));

    while (1)
    {
      delay(1000);
    }
  }

  LoRa.setSpreadingFactor(7);
  LoRa.setSignalBandwidth(125E3);
  LoRa.setCodingRate4(5);

  Serial.println(F("LoRa OK"));

  // ----------------------------------------------------------
  // MPU6050
  // ----------------------------------------------------------

  Serial.println(F("Initializing MPU6050..."));

  if (!mpu.begin())
  {
    Serial.println(F("MPU6050 not found!"));

    while (1)
    {
      delay(1000);
    }
  }

  Serial.println(F("MPU6050 OK"));

  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);

  mpu.setGyroRange(MPU6050_RANGE_500_DEG);

  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  // ----------------------------------------------------------
  // GPS
  // ----------------------------------------------------------

  Serial.println(F("GPS initialized"));
  Serial.println(F("Waiting for GPS..."));
  Serial.println();

  delay(1000);
}


// ============================================================
// BATTERY
// ============================================================

void ReadBattery()
{
  int adcValue = analogRead(BATTERY_PIN);

  float voltageA0 =
    adcValue * (5.0 / 1023.0);

  float rawVoltage =
    voltageA0 * ((R1 + R2) / R2);

  batteryVoltage =
    round(rawVoltage * 100.0) / 100.0;
}


// ============================================================
// GPS
// ============================================================

void ReadGPS()
{
  while (gpsSerial.available())
  {
    gps.encode(gpsSerial.read());
  }
}


// ============================================================
// PRINT GPS TIMESTAMP DIRECTLY TO LORA
//
// Format:
// YYMMDDHHMMSS
//
// Example:
// 260815052325
// ============================================================

void PrintGPSTimestampToLoRa()
{
  if (!gps.date.isValid() || !gps.time.isValid())
  {
    LoRa.print(F("000000000000"));
    return;
  }

  char timestamp[13];

  sprintf(
    timestamp,
    "%02d%02d%02d%02d%02d%02d",
    gps.date.year() % 100,
    gps.date.month(),
    gps.date.day(),
    gps.time.hour(),
    gps.time.minute(),
    gps.time.second()
  );

  LoRa.print(timestamp);
}


// ============================================================
// MPU6050
// ============================================================

void ReadMPU()
{
  sensors_event_t a;
  sensors_event_t g;
  sensors_event_t temp;

  mpu.getEvent(
    &a,
    &g,
    &temp
  );

  // ----------------------------------------------------------
  // Accelerometer
  // ----------------------------------------------------------

  ax = a.acceleration.x;
  ay = a.acceleration.y;
  az = a.acceleration.z;

  // ----------------------------------------------------------
  // Gyroscope
  // ----------------------------------------------------------

  gx = g.gyro.x;
  gy = g.gyro.y;
  gz = g.gyro.z;

  // ----------------------------------------------------------
  // Acceleration magnitude
  // ----------------------------------------------------------

  accelerationMagnitude =
    sqrt(
      ax * ax +
      ay * ay +
      az * az
    );

  // ----------------------------------------------------------
  // Low-pass filter
  // ----------------------------------------------------------

  filteredAcceleration =
    FILTER_ALPHA * accelerationMagnitude +
    (1.0 - FILTER_ALPHA) * filteredAcceleration;

  // ----------------------------------------------------------
  // Acceleration change
  // ----------------------------------------------------------

  accelerationChange =
    fabs(
      filteredAcceleration -
      previousAcceleration
    );

  previousAcceleration =
    filteredAcceleration;

  // ----------------------------------------------------------
  // Gyroscope magnitude
  // ----------------------------------------------------------

  gyroMagnitude =
    sqrt(
      gx * gx +
      gy * gy +
      gz * gz
    );

  // ----------------------------------------------------------
  // Movement detection
  // ----------------------------------------------------------

  bool accelerationMovement =
    accelerationChange >
    ACCEL_MOVEMENT_THRESHOLD;

  bool gyroMovement =
    gyroMagnitude >
    GYRO_MOVEMENT_THRESHOLD;

  bool movementDetected =
    accelerationMovement ||
    gyroMovement;

  // ----------------------------------------------------------
  // STATE MACHINE
  // ----------------------------------------------------------

  if (movementDetected)
  {
    movementCount++;

    stationaryCount = 0;

    if (movementCount >= MOVEMENT_CONFIRM_COUNT)
    {
      animalMoving = true;

      movementCount =
        MOVEMENT_CONFIRM_COUNT;
    }
  }
  else
  {
    stationaryCount++;

    movementCount = 0;

    if (stationaryCount >= STATIONARY_CONFIRM_COUNT)
    {
      animalMoving = false;

      stationaryCount =
        STATIONARY_CONFIRM_COUNT;
    }
  }
}


// ============================================================
// DEBUG INFORMATION
// ============================================================

void PrintDebug()
{
  Serial.println();
  Serial.println(F("================================"));
  Serial.println(F("SENSOR STATUS"));
  Serial.println(F("================================"));

  // ----------------------------------------------------------
  // Battery
  // ----------------------------------------------------------

  Serial.print(F("Battery       : "));
  Serial.print(batteryVoltage, 2);
  Serial.println(F(" V"));

  // ----------------------------------------------------------
  // GPS
  // ----------------------------------------------------------

  Serial.println();
  Serial.println(F("------ GPS ------"));

  if (gps.location.isValid())
  {
    Serial.print(F("Latitude      : "));
    Serial.println(gps.location.lat(), 5);

    Serial.print(F("Longitude     : "));
    Serial.println(gps.location.lng(), 5);

    Serial.print(F("Altitude      : "));
    Serial.print(gps.altitude.meters(), 1);
    Serial.println(F(" m"));

    Serial.print(F("Satellites    : "));
    Serial.println(gps.satellites.value());

    Serial.print(F("GPS Speed     : "));
    Serial.print(gps.speed.kmph(), 2);
    Serial.println(F(" km/h"));
  }
  else
  {
    Serial.println(F("GPS: No valid fix"));
  }

  // ----------------------------------------------------------
  // GPS Date
  // ----------------------------------------------------------

  Serial.print(F("GPS Date      : "));

  if (gps.date.isValid())
  {
    Serial.print(gps.date.year());
    Serial.print('-');
    Serial.print(gps.date.month());
    Serial.print('-');
    Serial.println(gps.date.day());
  }
  else
  {
    Serial.println(F("INVALID"));
  }

  // ----------------------------------------------------------
  // GPS Time
  // ----------------------------------------------------------

  Serial.print(F("GPS Time      : "));

  if (gps.time.isValid())
  {
    Serial.print(gps.time.hour());
    Serial.print(':');
    Serial.print(gps.time.minute());
    Serial.print(':');
    Serial.println(gps.time.second());
  }
  else
  {
    Serial.println(F("INVALID"));
  }

  // ----------------------------------------------------------
  // MPU6050
  // ----------------------------------------------------------

  Serial.println();
  Serial.println(F("------ MPU6050 ------"));

  Serial.print(F("Acceleration  : "));
  Serial.print(accelerationMagnitude, 2);
  Serial.println(F(" m/s2"));

  Serial.print(F("Accel Change  : "));
  Serial.print(accelerationChange, 3);
  Serial.println(F(" m/s2"));

  Serial.print(F("Gyro Magnitude: "));
  Serial.print(gyroMagnitude, 3);
  Serial.println(F(" rad/s"));

  Serial.print(F("Animal Status : "));

  if (animalMoving)
  {
    Serial.println(F("MOVING"));
  }
  else
  {
    Serial.println(F("STATIONARY"));
  }
}


// ============================================================
// SEND LORA PACKET
//
// Packet format:
//
// A01,3.72,27.68687,85.29550,1291.0,6,1.17,0,260815052325
//
// Fields:
//
// 1. Device ID
// 2. Battery
// 3. Latitude
// 4. Longitude
// 5. Altitude
// 6. Satellites
// 7. Speed
// 8. Movement
// 9. GPS Timestamp
//
// ============================================================

void SendLoRaPacket()
{
  LoRa.beginPacket();

  // ----------------------------------------------------------
  // 1. Device ID
  // ----------------------------------------------------------

  LoRa.print(DEVICE_ID);
  LoRa.print(',');

  // ----------------------------------------------------------
  // 2. Battery
  // ----------------------------------------------------------

  LoRa.print(batteryVoltage, 2);
  LoRa.print(',');

  // ----------------------------------------------------------
  // 3. Latitude
  // ----------------------------------------------------------

  if (gps.location.isValid())
  {
    LoRa.print(gps.location.lat(), 5);
  }
  else
  {
    LoRa.print(0);
  }

  LoRa.print(',');

  // ----------------------------------------------------------
  // 4. Longitude
  // ----------------------------------------------------------

  if (gps.location.isValid())
  {
    LoRa.print(gps.location.lng(), 5);
  }
  else
  {
    LoRa.print(0);
  }

  LoRa.print(',');

  // ----------------------------------------------------------
  // 5. Altitude
  // ----------------------------------------------------------

  if (gps.altitude.isValid())
  {
    LoRa.print(gps.altitude.meters(), 1);
  }
  else
  {
    LoRa.print(0);
  }

  LoRa.print(',');

  // ----------------------------------------------------------
  // 6. Satellites
  // ----------------------------------------------------------

  if (gps.satellites.isValid())
  {
    LoRa.print(gps.satellites.value());
  }
  else
  {
    LoRa.print(0);
  }

  LoRa.print(',');

  // ----------------------------------------------------------
  // 7. Speed
  // ----------------------------------------------------------

  if (gps.speed.isValid())
  {
    LoRa.print(gps.speed.kmph(), 2);
  }
  else
  {
    LoRa.print(0);
  }

  LoRa.print(',');

  // ----------------------------------------------------------
  // 8. Movement
  // ----------------------------------------------------------

  LoRa.print(animalMoving ? 1 : 0);

  LoRa.print(',');

  // ----------------------------------------------------------
  // 9. GPS Timestamp
  // ----------------------------------------------------------

  PrintGPSTimestampToLoRa();

  // ----------------------------------------------------------
  // TRANSMIT
  // ----------------------------------------------------------

  LoRa.endPacket();

  // ----------------------------------------------------------
  // DEBUG
  // ----------------------------------------------------------

  Serial.println();
  Serial.println(F("================================"));
  Serial.println(F("LoRa Packet Sent"));
  Serial.println(F("================================"));

  Serial.print(F("Device ID: "));
  Serial.println(DEVICE_ID);

  Serial.print(F("Battery: "));
  Serial.print(batteryVoltage, 2);
  Serial.println(F(" V"));

  Serial.print(F("Latitude: "));

  if (gps.location.isValid())
  {
    Serial.println(gps.location.lat(), 5);
  }
  else
  {
    Serial.println(F("0"));
  }

  Serial.print(F("Longitude: "));

  if (gps.location.isValid())
  {
    Serial.println(gps.location.lng(), 5);
  }
  else
  {
    Serial.println(F("0"));
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

  Serial.println(F("================================"));
}


// ============================================================
// MAIN LOOP
// ============================================================

void loop()
{
  // Continuously process GPS
  ReadGPS();

  // Continuously process MPU
  ReadMPU();

  // ----------------------------------------------------------
  // Send every 5 seconds
  // ----------------------------------------------------------

  if (millis() - lastSendTime >= SEND_INTERVAL)
  {
    lastSendTime = millis();

    ReadBattery();

    PrintDebug();

    SendLoRaPacket();
  }
}