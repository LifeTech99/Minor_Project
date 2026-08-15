class GpsData {
  final String deviceId;

  final double latitude;
  final double longitude;
  final double altitude;

  final int satellites;
  final double speed;

  // Battery voltage
  final double battery;

  final bool moving;

  final String timestamp;

  // LoRa link information
  final int rssi;
  final double snr;

  GpsData({
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.satellites,
    required this.speed,
    required this.battery,
    required this.moving,
    required this.timestamp,
    required this.rssi,
    required this.snr,
  });

  factory GpsData.fromJson(Map<String, dynamic> json) {
    return GpsData(
      deviceId: json["device_id"]?.toString() ?? "",

      latitude:
          (json["latitude"] as num?)?.toDouble() ?? 0.0,

      longitude:
          (json["longitude"] as num?)?.toDouble() ?? 0.0,

      altitude:
          (json["altitude"] as num?)?.toDouble() ?? 0.0,

      satellites:
          (json["satellites"] as num?)?.toInt() ?? 0,

      speed:
          (json["speed"] as num?)?.toDouble() ?? 0.0,

      // IMPORTANT: battery is voltage, so keep decimal value
      battery:
          (json["battery"] as num?)?.toDouble() ?? 0.0,

      moving:
          _parseMovement(json["movement"]),

      timestamp:
          json["timestamp"]?.toString() ?? "",

      rssi:
          (json["rssi"] as num?)?.toInt() ?? 0,

      snr:
          (json["snr"] as num?)?.toDouble() ?? 0.0,
    );
  }

  static bool _parseMovement(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final text = value.toLowerCase();

      return text == "1" ||
          text == "true" ||
          text == "moving";
    }

    return false;
  }

  Map<String, dynamic> toMap() {
    return {
      "device_id": deviceId,
      "latitude": latitude,
      "longitude": longitude,
      "altitude": altitude,
      "satellites": satellites,
      "speed": speed,
      "battery": battery,
      "movement": moving ? 1 : 0,
      "timestamp": timestamp,
      "rssi": rssi,
      "snr": snr,
    };
  }
}