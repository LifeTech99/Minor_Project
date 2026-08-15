import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:latlong2/latlong.dart';

import '../database/database_helper.dart';
import '../providers/notification_provider.dart';
import '../providers/provider_container.dart';
import 'package:livestock_tracker/services/geofence_service.dart';
import 'livestock_websocket_service.dart';
import '../models/gps_data.dart';

// ============================================================================
// GLOBAL STATE
// ============================================================================

final Map<String, bool> _previousGeofenceState = {};

final Map<String, DateTime> _onlineAnimals = {};

final Map<String, int> _lastBatteryNotification = {};


// ============================================================================
// BACKGROUND SERVICE
// ============================================================================

class BackgroundService {
  static final FlutterBackgroundService _service =
      FlutterBackgroundService();

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // --------------------------------------------------------------------------
  // SHOW ALERT
  // --------------------------------------------------------------------------

  static Future<void> showAlert({
    required String title,
    required String body,
  }) async {
    const android = AndroidNotificationDetails(
      'livestock_alerts',
      'Livestock Alerts',
      channelDescription: 'Geofence alerts',
      importance: Importance.max,
      priority: Priority.high,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: android,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // INITIALIZE
  // --------------------------------------------------------------------------

  static Future<void> initialize() async {
    const android =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _notifications.initialize(
      const InitializationSettings(
        android: android,
      ),
    );

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        foregroundServiceNotificationId: 100,
        initialNotificationTitle: 'Livestock Tracker',
        initialNotificationContent: 'Monitoring livestock...',
      ),
      iosConfiguration: IosConfiguration(),
    );
  }

  // --------------------------------------------------------------------------
  // START
  // --------------------------------------------------------------------------

  static Future<void> start() async {
    final started = await _service.startService();

    debugPrint(
      'Background service started: $started',
    );
  }

  // --------------------------------------------------------------------------
  // STOP
  // --------------------------------------------------------------------------

  static Future<void> stop() async {
    _service.invoke('stop');
  }

  // --------------------------------------------------------------------------
  // LISTEN FOR ANIMAL DATA
  //
  // This listener runs in the MAIN Flutter isolate.
  //
  // The background service sends:
  //
  //     service.invoke('animal_data', ...)
  //
  // and this receives it.
  // --------------------------------------------------------------------------

  static StreamSubscription? _animalSubscription;

  static void startAnimalDataListener(
    void Function(GpsData data) onAnimalData,
  ) {
    _animalSubscription?.cancel();

    _animalSubscription = _service.on('animal_data').listen(
      (event) {
        try {
          if (event == null) {
            return;
          }

          final data = Map<String, dynamic>.from(
            event,
          );

          final gpsData = GpsData.fromJson(data);

          debugPrint(
            'Main isolate received animal data: '
            '${gpsData.deviceId}',
          );

          onAnimalData(gpsData);
        } catch (e, stackTrace) {
          debugPrint(
            'Error receiving animal data: $e',
          );

          debugPrint('$stackTrace');
        }
      },
    );
  }

  // --------------------------------------------------------------------------
  // STOP ANIMAL LISTENER
  // --------------------------------------------------------------------------

  static Future<void> stopAnimalDataListener() async {
    await _animalSubscription?.cancel();

    _animalSubscription = null;
  }
}


// ============================================================================
// BACKGROUND SERVICE ENTRY POINT
// ============================================================================

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  debugPrint('onStart() called');

  // ============================================================
  // ANDROID FOREGROUND SERVICE
  // ============================================================

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();

    debugPrint('Foreground service requested');

    await service.setForegroundNotificationInfo(
      title: 'Livestock Tracker',
      content: '0 animals online',
    );

    debugPrint('Foreground notification initialized');
  }

  // ============================================================
  // ESP WEBSOCKET
  // ============================================================

  final livestockSocket = LivestockWebSocketService();

  await connectToEsp(livestockSocket);

  // ============================================================
  // RECONNECT TIMER
  // ============================================================

  final reconnectTimer = Timer.periodic(
    const Duration(seconds: 5),
    (timer) async {
      try {
        if (!livestockSocket.isConnected) {
          debugPrint(
            'ESP WebSocket disconnected. Reconnecting...',
          );

          await connectToEsp(livestockSocket);
        }
      } catch (e, stackTrace) {
        debugPrint(
          'WebSocket reconnect error: $e',
        );

        debugPrint('$stackTrace');
      }
    },
  );

  // ============================================================
  // ONLINE ANIMAL CLEANUP
  // ============================================================

  final cleanupTimer = Timer.periodic(
    const Duration(seconds: 10),
    (timer) async {
      try {
        final now = DateTime.now();

        final before = _onlineAnimals.length;

        _onlineAnimals.removeWhere(
          (deviceId, lastSeen) {
            final elapsed =
                now.difference(lastSeen).inSeconds;

            return elapsed > 30;
          },
        );

        final after = _onlineAnimals.length;

        debugPrint(
          'Online animals: $after',
        );

        if (after != before &&
            service is AndroidServiceInstance) {
          await service.setForegroundNotificationInfo(
            title: 'Livestock Tracker',
            content: '$after animals online',
          );

          debugPrint(
            'Foreground notification updated: '
            '$after animals online',
          );
        }
      } catch (e, stackTrace) {
        debugPrint(
          'Cleanup timer error: $e',
        );

        debugPrint('$stackTrace');
      }
    },
  );

  // ============================================================
  // STOP SERVICE
  // ============================================================

  service.on('stop').listen((event) {
    debugPrint(
      'Stopping background service...',
    );

    reconnectTimer.cancel();
    cleanupTimer.cancel();

    service.stopSelf();
  });

  // ============================================================
  // ESP DATA LISTENER
  // ============================================================

  livestockSocket.dataStream.listen(
    (GpsData data) async {
      try {
        debugPrint('================================');
        debugPrint('Background ESP data received');

        debugPrint(
          'Device: ${data.deviceId}',
        );

        debugPrint(
          'Location: '
          '${data.latitude}, '
          '${data.longitude}',
        );

        debugPrint(
          'Battery: ${data.battery}',
        );

        debugPrint(
          'Movement: '
          '${data.moving ? "MOVING" : "STATIONARY"}',
        );

        debugPrint('================================');

        // ========================================================
        // BASIC VALIDATION
        // ========================================================

        if (data.deviceId.isEmpty) {
          debugPrint(
            'Ignoring animal with empty device ID',
          );

          return;
        }

        // ========================================================
        // DEVICE ID
        // ========================================================

        final String animalId = data.deviceId;

        // ========================================================
        // UPDATE ONLINE ANIMAL
        // ========================================================

        final before = _onlineAnimals.length;

        _onlineAnimals[animalId] = DateTime.now();

        final after = _onlineAnimals.length;

        if (after != before &&
            service is AndroidServiceInstance) {
          await service.setForegroundNotificationInfo(
            title: 'Livestock Tracker',
            content: '$after animals online',
          );

          debugPrint(
            'Foreground notification updated: '
            '$after animals online',
          );
        }

        // ========================================================
        // SEND LIVE ANIMAL DATA TO MAIN ISOLATE
        //
        // IMPORTANT:
        // This MUST happen BEFORE geofence processing.
        //
        // Therefore A01 will appear on the map even if:
        //
        // - there is no geofence
        // - animal is outside
        // - geofence database is unavailable
        //
        // ========================================================

        service.invoke(
          'animal_data',
          {
            'deviceId': data.deviceId,
            'battery': data.battery,
            'latitude': data.latitude,
            'longitude': data.longitude,
            'altitude': data.altitude,
            'satellites': data.satellites,
            'speed': data.speed,
            'moving': data.moving,
            'timestamp': data.timestamp,
            'rssi': data.rssi,
            'snr': data.snr,
          },
        );

        debugPrint(
          'Animal data sent to main isolate',
        );

        debugPrint(
          'Battery: ${data.battery} V',
        );

        // ========================================================
        // BATTERY
        // ========================================================

        final battery = data.battery.toInt();

        // ========================================================
        // LOW BATTERY
        // ========================================================

        final lastBattery =
            _lastBatteryNotification[animalId];

        if (battery <= 15 &&
            lastBattery != battery) {
          _lastBatteryNotification[animalId] = battery;

          providerContainer
              .read(notificationProvider.notifier)
              .log(
                LogEventType.battery,
                '$animalId battery is $battery%',
              );

          debugPrint(
            'Low battery notification: '
            '$animalId = $battery%',
          );
        }

        // ========================================================
        // GPS
        // ========================================================

        final latitude = data.latitude;
        final longitude = data.longitude;
        final timestamp = data.timestamp;

        // ========================================================
        // GEOFENCE
        // ========================================================
        //
        // IMPORTANT:
        // Do NOT return before this point affects live marker.
        //
        // Marker has already been sent to main isolate above.
        //
        // ========================================================

        final fence =
            await DatabaseHelper.instance.getGeofence();

        if (fence == null) {
          debugPrint(
            'No geofence configured.',
          );

          // Live marker has already been sent.
          return;
        }

        // ========================================================
        // GEOFENCE ID
        // ========================================================

        final dynamic rawGeofenceId =
            fence['id'];

        if (rawGeofenceId == null) {
          debugPrint(
            'Geofence exists but ID is null.',
          );

          return;
        }

        final int geofenceId =
            (rawGeofenceId as num).toInt();

        // ========================================================
        // GET POLYGON
        // ========================================================

        final polygon =
            await DatabaseHelper.instance
                .getGeofencePoints(
          geofenceId,
        );

        if (polygon.isEmpty) {
          debugPrint(
            'Geofence polygon is empty.',
          );

          return;
        }

        // ========================================================
        // POINT IN POLYGON
        // ========================================================

        final bool inside =
            GeofenceUtils.isPointInsidePolygon(
          LatLng(
            latitude,
            longitude,
          ),
          polygon,
        );

        final geofenceStatus =
            inside ? 'inside' : 'outside';

        debugPrint(
          '$animalId is $geofenceStatus '
          'the geofence',
        );

        // ========================================================
        // PREVIOUS GEOFENCE STATE
        // ========================================================

        final previous =
            _previousGeofenceState[animalId];

        // ========================================================
        // FIRST LOCATION
        // ========================================================

        if (previous == null) {
          _previousGeofenceState[animalId] =
              inside;

          debugPrint(
            'Initial geofence state for '
            '$animalId: $geofenceStatus',
          );
        }

        // ========================================================
        // GEOFENCE STATE CHANGED
        // ========================================================

        else if (previous != inside) {
          _previousGeofenceState[animalId] =
              inside;

          if (inside) {
            providerContainer
                .read(
                  notificationProvider.notifier,
                )
                .log(
                  LogEventType.geofence,
                  '$animalId entered the geofence.',
                );

            debugPrint(
              '$animalId entered the geofence',
            );
          } else {
            providerContainer
                .read(
                  notificationProvider.notifier,
                )
                .log(
                  LogEventType.geofence,
                  '$animalId left the geofence!',
                );

            debugPrint(
              '$animalId left the geofence',
            );
          }
        }

        // ========================================================
        // UPDATE DASHBOARD
        // ========================================================

        await DatabaseHelper.instance.updateDashboard(
          animalId: animalId,
          latitude: latitude,
          longitude: longitude,
          status: geofenceStatus,
          battery: battery,
          timestamp: timestamp,
          geofenceId: geofenceId,
        );

        // ========================================================
        // SAVE HISTORY
        // ========================================================

        await DatabaseHelper.instance
            .insertDashboardHistory(
          animalId: animalId,
          latitude: latitude,
          longitude: longitude,
          status: geofenceStatus,
          battery: battery,
          timestamp: timestamp,
          geofenceId: geofenceId,
        );

        debugPrint(
          'Dashboard/history updated for '
          '$animalId',
        );
      } catch (e, stackTrace) {
        debugPrint(
          'Error processing ESP WebSocket data: $e',
        );

        debugPrint('$stackTrace');
      }
    },
    onError: (error) {
      debugPrint(
        'WebSocket data stream error: $error',
      );
    },
  );
}

// ============================================================================
// ESP CONNECTION
// ============================================================================

Future<void> connectToEsp(
  LivestockWebSocketService livestockSocket,
) async {
  if (livestockSocket.isConnected) {
    debugPrint('ESP WebSocket already connected.');
    return;
  }

  try {
    debugPrint('Trying to connect to ESP WebSocket...');

    final connected = await livestockSocket.connect();

    if (connected) {
      debugPrint('Connected to ESP8266 WebSocket');
    } else {
      debugPrint('ESP WebSocket connection failed.');
    }
  } catch (e, stackTrace) {
    debugPrint('ESP WebSocket connection error: $e');
    debugPrint('$stackTrace');
  }
}