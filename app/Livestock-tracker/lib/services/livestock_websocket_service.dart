import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/gps_data.dart';
import '../models/base_station_data.dart';

class LivestockWebSocketService {
  WebSocket? _socket;

  // ============================================================
  // ANIMAL DATA STREAM
  // ============================================================

  final StreamController<GpsData> _animalDataController =
      StreamController<GpsData>.broadcast();

  Stream<GpsData> get dataStream =>
      _animalDataController.stream;

  // ============================================================
  // BASE STATION DATA STREAM
  // ============================================================

  final StreamController<BaseStationData>
      _baseStationDataController =
      StreamController<BaseStationData>.broadcast();

  Stream<BaseStationData> get baseStationStream =>
      _baseStationDataController.stream;

  // ============================================================
  // CONNECTION STATUS
  // ============================================================

  bool get isConnected => _socket != null;

  // ============================================================
  // CONNECT
  // ============================================================

  Future<bool> connect({
    String host = "192.168.4.1",
    int port = 81,
  }) async {
    if (_socket != null) {
      return true;
    }

    try {
      final url = "ws://$host:$port/";

      print("Connecting to livestock WebSocket...");
      print("URL: $url");

      _socket = await WebSocket.connect(url).timeout(
        const Duration(seconds: 5),
      );

      print("Livestock WebSocket connected");

      _socket!.listen(
        (message) {
          print("================================");
          print("RAW ESP MESSAGE:");
          print(message);
          print("================================");

          try {
            // --------------------------------------------------
            // Decode JSON
            // --------------------------------------------------

            final json =
                jsonDecode(message) as Map<String, dynamic>;

            // --------------------------------------------------
            // Determine message type
            // --------------------------------------------------

            final type = json["type"]?.toString();

            // ==================================================
            // ANIMAL DATA
            // ==================================================

            if (type == "animal") {
              final gpsData =
                  GpsData.fromJson(json);

              _animalDataController.add(gpsData);

              print("Animal data received:");
              print("Device: ${gpsData.deviceId}");
              print(
                "Location: "
                "${gpsData.latitude}, "
                "${gpsData.longitude}",
              );
            }

            // ==================================================
            // BASE STATION DATA
            // ==================================================

            else if (type == "base_station") {
              final baseStationData =
                  BaseStationData.fromJson(json);

              _baseStationDataController
                  .add(baseStationData);

              print("Base station data received:");
              print(
                "Device: "
                "${baseStationData.deviceId}",
              );
              print(
                "Battery: "
                "${baseStationData.battery} V",
              );
            }

            // ==================================================
            // UNKNOWN DATA TYPE
            // ==================================================

            else {
              print(
                "Unknown ESP message type: $type",
              );
            }
          } catch (e) {
            print(
              "Invalid livestock data: $e",
            );
          }
        },

        // ========================================================
        // CONNECTION CLOSED
        // ========================================================

        onDone: () {
          print(
            "Livestock WebSocket disconnected",
          );

          _socket = null;
        },

        // ========================================================
        // CONNECTION ERROR
        // ========================================================

        onError: (error) {
          print(
            "Livestock WebSocket error: $error",
          );

          _socket = null;
        },
      );

      return true;
    } catch (e) {
      print(
        "WebSocket connection failed: $e",
      );

      _socket = null;

      return false;
    }
  }

  // ============================================================
  // DISCONNECT
  // ============================================================

  void disconnect() {
    _socket?.close();
    _socket = null;
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    disconnect();

    _animalDataController.close();

    _baseStationDataController.close();
  }
}