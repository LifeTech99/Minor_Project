import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/livestock_websocket_service.dart';
import '../models/gps_data.dart';
import '../models/base_station_data.dart';


// ============================================================
// WEBSOCKET SERVICE
// ============================================================

final livestockWebSocketProvider =
    Provider<LivestockWebSocketService>((ref) {
  final service = LivestockWebSocketService();

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});


// ============================================================
// ANIMAL DATA
// ============================================================

final livestockDataProvider =
    StreamProvider<GpsData>((ref) {
  final service = ref.watch(
    livestockWebSocketProvider,
  );

  return service.dataStream;
});


final baseStationDataProvider =
    StreamProvider<BaseStationData>((ref) {
  final service = ref.watch(
    livestockWebSocketProvider,
  );

  return service.baseStationStream;
});