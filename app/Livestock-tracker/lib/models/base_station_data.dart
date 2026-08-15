class BaseStationData {
  final String deviceId;
  final double battery;
  final int uptime;

  BaseStationData({
    required this.deviceId,
    required this.battery,
    required this.uptime,
  });

  factory BaseStationData.fromJson(Map<String, dynamic> json) {
    return BaseStationData(
      deviceId: json["device_id"]?.toString() ?? "",
      battery: (json["battery"] as num?)?.toDouble() ?? 0.0,
      uptime: (json["uptime"] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "device_id": deviceId,
      "battery": battery,
      "uptime": uptime,
    };
  }
}