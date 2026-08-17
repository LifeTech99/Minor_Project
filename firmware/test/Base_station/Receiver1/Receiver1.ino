#include <SPI.h>
#include <LoRa.h>
#include <ESP8266WiFi.h>
#include <WebSocketsServer.h>

// WIFI
#define WIFI_SSID     "BaseStation"
#define WIFI_PASSWORD "12345678"

// WEBSOCKET
#define WEBSOCKET_PORT 81
WebSocketsServer webSocket = WebSocketsServer(WEBSOCKET_PORT);

// LoRa Pins - ESP8266
#define LORA_SS     15   // D8
#define LORA_RST    16   // D0
#define LORA_DIO0    4   // D2

// LoRa
#define LORA_FREQUENCY 433E6

// =====================================================
// LORA COMMAND ACK / RETRY
// =====================================================

#define COMMAND_RETRY_INTERVAL 4000UL
#define COMMAND_MAX_RETRIES    3

bool commandPending = false;

String pendingCommand = "";
String pendingAnimalID = "";

unsigned long lastCommandSend = 0;
byte commandRetryCount = 0;

// BASE STATION BATTERY
const int BATTERY_PIN = A0;
const float R1 = 10000.0;
const float R2 = 10000.0;

// =====================================================
// MULTI-NODE POLLING
// =====================================================

#define MAX_ANIMAL_NODES 10

String animalIDs[MAX_ANIMAL_NODES] =
{
  "A01",
  "A02",
  "A03",
  "A04",
  "A05",
  "A06",
  "A07",
  "A08",
  "A09",
  "A10"
};

bool animalLive[MAX_ANIMAL_NODES] = {false};

byte pollIndex = 0;

bool pollPending = false;

unsigned long pollSendTime = 0;

// SF12 needs a reasonably long response window.
#define POLL_TIMEOUT 5000UL

// Small pause between completed nodes.
#define POLL_GAP 100UL

unsigned long lastPollAction = 0;

// WEBSOCKET EVENT
void webSocketEvent(uint8_t num,WStype_t type,uint8_t *payload,size_t length)
{
  // CLIENT CONNECTED
  if (type == WStype_CONNECTED)
  {
    IPAddress ip = webSocket.remoteIP(num);
    Serial.println();
    Serial.println("WebSocket client connected");
    Serial.print("Client IP: ");
    Serial.println(ip);
    // Send initial status
    webSocket.sendTXT(num,"STATUS,CONNECTED");
    return;
  }

  // CLIENT DISCONNECTED
  if (type == WStype_DISCONNECTED)
  {
    Serial.println();
    Serial.println("WebSocket client disconnected");
    return;
  }
  
  // TEXT MESSAGE
  if (type == WStype_TEXT)
  {
    String command = String((char *)payload);
    command.trim();
    Serial.println();
    Serial.println("WebSocket command:");
    Serial.println(command);

    // Ignore empty command
    if (command.length() == 0)
    {
      return;
    }

    // -----------------------------------------------------
    // POLL is handled separately from normal commands
    // -----------------------------------------------------

    if (command.startsWith("POLL,"))
    {
      sendPoll(command);
    }
    else
    {
      // LIVE / FENCE / other commands
      sendLoRaCommand(command);
    }

    // Tell Flutter command was sent
    String response = "COMMAND_SENT," + command;
    webSocket.sendTXT(num, response);
      }
}

// =====================================================
// EXTRACT ANIMAL ID
//
// Example:
// LIVE,A02,OFF
//
// Returns:
// A02
// =====================================================
// =====================================================
// EXTRACT ANIMAL ID
//
// Examples:
//
// LIVE,A01,ON
//       └── A01
//
// POLL,A01
//       └── A01
//
// FENCE,A01,4,...
//        └── A01
// =====================================================

String getAnimalID(String command)
{
  int firstComma = command.indexOf(',');

  if (firstComma < 0)
  {
    return "";
  }

  int secondComma = command.indexOf(',', firstComma + 1);

  String animalID;

  if (secondComma < 0)
  {
    // Command has only two fields
    // Example: POLL,A01

    animalID = command.substring(firstComma + 1);
  }
  else
  {
    // Example: LIVE,A01,OFF
    //          FENCE,A01,4,...

    animalID = command.substring(
      firstComma + 1,
      secondComma
    );
  }

  animalID.trim();

  return animalID;
}

// =====================================================
// FIND ANIMAL INDEX
// =====================================================

int getAnimalIndex(String animalID)
{
  animalID.trim();

  for (byte i = 0; i < MAX_ANIMAL_NODES; i++)
  {
    if (animalIDs[i] == animalID)
    {
      return i;
    }
  }

  return -1;
}

// =====================================================
// SEND POLL TO ANIMAL
//
// POLL,A01
// POLL,A02
//
// POLL does NOT use the normal ACK/retry system.
// DATA,Axx,... is the response.
// =====================================================

// =====================================================
// SEND POLL
// =====================================================

void sendPoll(String command)
{
  command.trim();

  String animalID = getAnimalID(command);

  if (animalID.length() == 0)
  {
    return;
  }

  Serial.println();
  Serial.println("================================");
  Serial.println("AUTOMATIC POLL");
  Serial.print("Command: ");
  Serial.println(command);
  Serial.print("Animal: ");
  Serial.println(animalID);
  Serial.println("================================");

  LoRa.beginPacket();
  LoRa.print(command);
  LoRa.endPacket();

  pollPending = true;
  pollSendTime = millis();

  Serial.println("POLL sent.");
  Serial.println("Waiting for DATA...");
}

// =====================================================
// SEND COMMAND TO ANIMAL NODE
// =====================================================

void sendLoRaCommand(String command)
{
  command.trim();

  if (command.length() == 0)
  {
    return;
  }

  // Extract target animal
  String animalID = getAnimalID(command);

  if (animalID.length() == 0)
  {
    Serial.println("Invalid command - no animal ID.");
    return;
  }

  // -----------------------------------------------------
  // Cancel automatic POLL if a normal command is sent
  // -----------------------------------------------------

  if (pollPending)
  {
    Serial.println();
    Serial.println("Cancelling active POLL.");
    Serial.print("Previous animal: ");
    Serial.println(animalIDs[pollIndex]);

    pollPending = false;

    // Continue polling from next animal
    pollIndex++;

    if (pollIndex >= MAX_ANIMAL_NODES)
    {
      pollIndex = 0;
    }

    lastPollAction = millis();
  }

  Serial.println();
  Serial.println("================================");
  Serial.println("Sending LoRa command:");
  Serial.println(command);
  Serial.print("Target animal: ");
  Serial.println(animalID);
  Serial.println("================================");

  // Save pending command
  pendingCommand = command;
  pendingAnimalID = animalID;

  commandPending = true;
  commandRetryCount = 1;

  // Send first attempt
  LoRa.beginPacket();
  LoRa.print(command);
  LoRa.endPacket();

  lastCommandSend = millis();

  Serial.println("LoRa command sent.");
  Serial.println("Waiting for ACK...");
}

// =====================================================
// CHECK ACK PACKET
// =====================================================

void processAck(String packet)
{
  // Expected:
  //
  // ACK,A02,LIVE,OFF
  // ACK,A02,LIVE,ON
  // ACK,A02,FENCE,OK

  if (!packet.startsWith("ACK,"))
  {
    return;
  }

  int comma1 = packet.indexOf(',');
  int comma2 = packet.indexOf(',', comma1 + 1);

  if (
    comma1 < 0 ||
    comma2 < 0
  )
  {
    return;
  }

  String animalID = packet.substring(
    comma1 + 1,
    comma2
  );

  animalID.trim();

  // Is this ACK for the command we're waiting for?
  if (!commandPending)
  {
    Serial.println("ACK received, but no command is pending.");
    return;
  }

  if (animalID != pendingAnimalID)
  {
    Serial.println("ACK from another animal.");
    return;
  }

  // -----------------------------------------------------
  // Check actual command
  // -----------------------------------------------------

  bool validACK = false;

  if (pendingCommand.startsWith("LIVE,"))
  {
    // Example:
    // pending: LIVE,A02,OFF
    // ACK:     ACK,A02,LIVE,OFF

    int commandComma = pendingCommand.indexOf(',');

    String pendingAction = pendingCommand.substring(
      pendingCommand.lastIndexOf(',') + 1
    );

    String ackAction = packet.substring(
      packet.lastIndexOf(',') + 1
    );

    pendingAction.trim();
    ackAction.trim();

    if (
      packet.indexOf(",LIVE,") >= 0 &&
      pendingAction == ackAction
    )
    {
      validACK = true;
    }
  }
  else if (pendingCommand.startsWith("FENCE,"))
  {
    if (packet.indexOf(",FENCE,OK") >= 0)
    {
      validACK = true;
    }
  }

  if (!validACK)
  {
    Serial.println("ACK does not match pending command.");
    return;
  }

  // -----------------------------------------------------
  // SUCCESS
  // -----------------------------------------------------

  commandPending = false;
  // -----------------------------------------------------
  // Update live state
  // -----------------------------------------------------

  if (pendingCommand.startsWith("LIVE,"))
  {
    int animalIndex = getAnimalIndex(animalID);

    if (animalIndex >= 0)
    {
      String action =
        pendingCommand.substring(
          pendingCommand.lastIndexOf(',') + 1
        );

      action.trim();

      if (action == "ON")
      {
        animalLive[animalIndex] = true;
      }
      else if (action == "OFF")
      {
        animalLive[animalIndex] = false;
      }
    }
  }

  Serial.println();
  Serial.println("================================");
  Serial.println("COMMAND ACKNOWLEDGED");
  Serial.print("Animal: ");
  Serial.println(animalID);
  Serial.print("Command: ");
  Serial.println(pendingCommand);
  Serial.print("Attempts: ");
  Serial.println(commandRetryCount);
  Serial.println("================================");

  // Tell Flutter
  String response =
    "COMMAND_SUCCESS," +
    pendingCommand;

  webSocket.broadcastTXT(response);
}

// =====================================================
// PROCESS POLL DATA
//
// Expected:
//
// DATA,A01,3.82,27.68708,85.29596,1331.7,5,1.67,0
//
// DATA itself is the response to POLL.
// =====================================================

// =====================================================
// PROCESS POLL DATA
// =====================================================

void processPollData(String packet)
{
  if (!packet.startsWith("DATA,"))
  {
    return;
  }

  int comma1 = packet.indexOf(',');
  int comma2 = packet.indexOf(',', comma1 + 1);

  if (comma1 < 0 || comma2 < 0)
  {
    Serial.println("Invalid DATA packet.");
    return;
  }

  String animalID = packet.substring(
    comma1 + 1,
    comma2
  );

  animalID.trim();

  Serial.println();
  Serial.println("================================");
  Serial.println("POLL DATA RECEIVED");
  Serial.print("Animal: ");
  Serial.println(animalID);
  Serial.println(packet);
  Serial.println("================================");

  // -----------------------------------------------------
  // Was this the animal we were polling?
  // -----------------------------------------------------

  if (!pollPending)
  {
    Serial.println("DATA received without active POLL.");
    return;
  }

  String expectedAnimal =
    animalIDs[pollIndex];

  if (animalID != expectedAnimal)
  {
    Serial.println("DATA from unexpected animal.");
    return;
  }

  // -----------------------------------------------------
  // POLL SUCCESS
  // -----------------------------------------------------

// -----------------------------------------------------
// POLL SUCCESS
// -----------------------------------------------------

  pollPending = false;

  Serial.println("POLL SUCCESS");

  // Send telemetry to Flutter
  webSocket.broadcastTXT(packet);

  // -----------------------------------------------------
  // MOVE TO NEXT ANIMAL
  // -----------------------------------------------------

  pollIndex++;

  if (pollIndex >= MAX_ANIMAL_NODES)
  {
    pollIndex = 0;
  }

  lastPollAction = millis();

}
// =====================================================
// RECEIVE LORA PACKET
// =====================================================

void receiveLoRaPacket()
{
  int packetSize = LoRa.parsePacket();

  if (!packetSize)
  {
    return;
  }

  String packet = "";

  while (LoRa.available())
  {
    packet += (char)LoRa.read();
  }

  packet.trim();

  Serial.println();
  Serial.println("================================");
  Serial.println("LoRa PACKET RECEIVED");
  Serial.println(packet);

  Serial.print("RSSI: ");
  Serial.print(LoRa.packetRssi());
  Serial.println(" dBm");

  Serial.print("SNR : ");
  Serial.print(LoRa.packetSnr());
  Serial.println(" dB");

  Serial.println("================================");

// -----------------------------------------------------
// ACK
// -----------------------------------------------------

if (packet.startsWith("ACK,"))
{
  processAck(packet);
}

// -----------------------------------------------------
// DATA
// -----------------------------------------------------

else if (packet.startsWith("DATA,"))
{
  processPollData(packet);
}

// -----------------------------------------------------
// Send everything to Flutter
// -----------------------------------------------------

webSocket.broadcastTXT(packet);
}

// =====================================================
// AUTOMATIC POLL SCHEDULER
// =====================================================

void updatePollScheduler()
{
  // -----------------------------------------------------
  // Don't poll while a normal command is waiting for ACK
  // -----------------------------------------------------

  if (commandPending)
  {
    return;
  }

  // -----------------------------------------------------
  // If waiting for DATA, check timeout
  // -----------------------------------------------------

  if (pollPending)
  {
    if (millis() - pollSendTime >= POLL_TIMEOUT)
    {
      Serial.println();
      Serial.println("================================");
      Serial.println("POLL TIMEOUT");
      Serial.print("Animal: ");
      Serial.println(animalIDs[pollIndex]);
      Serial.println("Moving to next animal.");
      Serial.println("================================");

      pollPending = false;

      pollIndex++;

      if (pollIndex >= MAX_ANIMAL_NODES)
      {
        pollIndex = 0;
      }

      lastPollAction = millis();
    }

    return;
  }

  // -----------------------------------------------------
  // Small gap between nodes
  // -----------------------------------------------------

  if (millis() - lastPollAction < POLL_GAP)
  {
    return;
  }

  // -----------------------------------------------------
  // Find next LIVE animal
  // -----------------------------------------------------

  for (byte checked = 0;
       checked < MAX_ANIMAL_NODES;
       checked++)
  {
    if (animalLive[pollIndex])
    {
      String command =
        "POLL," +
        animalIDs[pollIndex];

      sendPoll(command);

      return;
    }

    // Current animal is OFF
    pollIndex++;

    if (pollIndex >= MAX_ANIMAL_NODES)
    {
      pollIndex = 0;
    }
  }

  // -----------------------------------------------------
  // No live animals
  // -----------------------------------------------------

  lastPollAction = millis();
}


// =====================================================
// HANDLE COMMAND RETRY
// =====================================================

void updateCommandRetry()
{
  if (!commandPending)
  {
    return;
  }

  // Wait for ACK timeout
  if (
    millis() - lastCommandSend <
    COMMAND_RETRY_INTERVAL
  )
  {
    return;
  }

  // -----------------------------------------------------
  // If maximum attempts have already been sent,
  // now declare failure.
  // -----------------------------------------------------

  if (commandRetryCount >= COMMAND_MAX_RETRIES)
  {
    commandPending = false;

    Serial.println();
    Serial.println("================================");
    Serial.println("COMMAND FAILED");
    Serial.print("Animal: ");
    Serial.println(pendingAnimalID);
    Serial.print("Command: ");
    Serial.println(pendingCommand);
    Serial.println("No ACK received.");
    Serial.println("================================");

    String response =
      "COMMAND_FAILED," +
      pendingCommand;

    webSocket.broadcastTXT(response);

    return;
  }

  // -----------------------------------------------------
  // Retry
  // -----------------------------------------------------

  commandRetryCount++;

  Serial.println();
  Serial.println("================================");
  Serial.println("RETRYING COMMAND");

  Serial.print("Attempt: ");
  Serial.print(commandRetryCount);
  Serial.print("/");
  Serial.println(COMMAND_MAX_RETRIES);

  Serial.print("Command: ");
  Serial.println(pendingCommand);

  Serial.println("================================");

  LoRa.beginPacket();
  LoRa.print(pendingCommand);
  LoRa.endPacket();

  lastCommandSend = millis();
}

// SETUP
void setup()
{
  // SERIAL
  Serial.begin(9600);
  delay(1000);
  Serial.println();
  Serial.println("================================");
  Serial.println("LIVESTOCK BASE STATION");
  Serial.println("ESP8266 + LoRa + WebSocket");
  Serial.println("================================");

  // WIFI ACCESS POINT
  Serial.println();
  Serial.println("Starting WiFi...");
  WiFi.mode(WIFI_AP);
  WiFi.softAP(WIFI_SSID,WIFI_PASSWORD);
  Serial.println("WiFi AP started.");
  Serial.print("SSID: ");
  Serial.println(WIFI_SSID);
  Serial.print("IP address: ");
  Serial.println(WiFi.softAPIP());

  // LoRa
  Serial.println();
  Serial.println("Initializing LoRa...");
  SPI.begin();
  LoRa.setPins(LORA_SS,LORA_RST,LORA_DIO0);

  if (!LoRa.begin(LORA_FREQUENCY))
  {
    Serial.println("LoRa init FAILED!");
    while (true)
    {
      delay(1000);
    }
  }
  /*
  LoRa.setFrequency(LORA_FREQUENCY);
  LoRa.setSpreadingFactor(7);
  LoRa.setSignalBandwidth(125E3);
  LoRa.setCodingRate4(5);
  Serial.println("LoRa initialization SUCCESS!");
  */
  
  // LONG RANGE SETTINGS
  LoRa.setFrequency(LORA_FREQUENCY);
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
  

  // WEBSOCKET
  Serial.println();
  Serial.println("Starting WebSocket server...");
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);
  Serial.print("WebSocket server: ws://");
  Serial.print(WiFi.softAPIP());
  Serial.println(":81");

  // READY
  Serial.println();
  Serial.println("================================");
  Serial.println("BASE STATION READY");
  Serial.println("================================");
  Serial.println();
  Serial.println("Connect Flutter to WiFi:");
  Serial.println("BaseStation");
  Serial.println();
  Serial.println("WebSocket:");
  Serial.print("ws://");
  Serial.print( WiFi.softAPIP());
  Serial.println(":81");
  Serial.println();
}
// =====================================================
// LOOP
// =====================================================

void loop()
{
  // WebSocket
  webSocket.loop();

  // LoRa receive
  receiveLoRaPacket();

  // Normal command retry
  updateCommandRetry();

  // Automatic animal polling
  updatePollScheduler();
}

// BASE STATION BATTERY
void batteryStatus()
{
  int adcValue = analogRead(BATTERY_PIN);
  float voltageA0 = adcValue * (3.2 / 1023.0);
  float batteryVoltage = voltageA0 * ((R1 + R2) / R2);
  Serial.print("Base battery: ");
  Serial.print(batteryVoltage,2);
  Serial.println(" V");
}
