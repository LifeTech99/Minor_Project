import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/map_state_controller.dart';
import '../database/database_helper.dart';
import '../geofence/geofence.dart';
import '../geofence/map_layers.dart';
import '../models/download_progress.dart';
import '../providers/notification_provider.dart';
import '../screens/alerts_screen.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';
import '../services/map_download_service.dart';
import '../services/tile_cache_service.dart';
import '../services/wifi_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/download_progress_dialog.dart';
import '../widgets/geofence_panel.dart';

import '../providers/map_state_provider.dart';
//import '../providers/livestock_provider.dart';
import '../models/gps_data.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class OnlineMapScreen extends ConsumerStatefulWidget {
  const OnlineMapScreen({super.key});

  @override
  ConsumerState<OnlineMapScreen> createState() => _OnlineMapScreenState();
}

class _OnlineMapScreenState extends ConsumerState<OnlineMapScreen> {
  final MapController mapController = MapController();
  final LocationService locationService = LocationService();
  final FlutterBackgroundService backgroundService = FlutterBackgroundService();

  StreamSubscription<Position>? positionStream;
  Timer? _refreshTimer;

  //final MapStateController mapState = MapStateController();

  String? tileDirectory;

  bool isOnline = true;

  final ConnectivityService connectivityService = ConnectivityService();
  final MapDownloadService downloader = MapDownloadService();

  final ValueNotifier<DownloadProgress?> progressNotifier =
      ValueNotifier<DownloadProgress?>(null);

  Map<String, LatLng> livestockLocations = {};

  final WifiService wifi = WifiService();

  bool robotConnected = false;
  bool ledOn = false;

  final GeofenceController geofence = GeofenceController();

  MapStateController get mapState =>
    ref.read(mapStateControllerProvider);

  StreamSubscription? livestockSubscription;

  bool livestockConnected = false;

  Map<String, bool> lastGeofenceStatus = {};
  Map<String, int> lastBattery = {};

  // Number of unread notifications.
  int unreadAlerts = 0;

  // ---------------------------------------------------------------------------
  // LIVESTOCK LOCATION
  // ---------------------------------------------------------------------------

  void listenToBackgroundAnimalData() {
  backgroundService.on('animal_data').listen((event) {
    if (!mounted) return;

    try {
      if (event == null) {
        debugPrint(
          'Received null animal event',
        );
        return;
      }

      final data =
          Map<String, dynamic>.from(event);

      debugPrint(
        '================================',
      );

      debugPrint(
        'Animal data received by MapScreen:',
      );

      debugPrint(
        'Event: $data',
      );

      // ========================================================
      // SAFE PARSING
      // ========================================================

      final deviceId =
          data['deviceId']?.toString() ??
          data['device_id']?.toString() ??
          '';

      if (deviceId.isEmpty) {
        debugPrint(
          'Animal event has no device ID.',
        );

        return;
      }

      final latitude =
          (data['latitude'] as num?)?.toDouble() ??
          0.0;

      final longitude =
          (data['longitude'] as num?)?.toDouble() ??
          0.0;

      final altitude =
          (data['altitude'] as num?)?.toDouble() ??
          0.0;

      final satellites =
          (data['satellites'] as num?)?.toInt() ??
          0;

      final speed =
          (data['speed'] as num?)?.toDouble() ??
          0.0;

      final battery =
          (data['battery'] as num?)?.toDouble() ??
          0.0;

      final rssi =
          (data['rssi'] as num?)?.toInt() ??
          0;

      final snr =
          (data['snr'] as num?)?.toDouble() ??
          0.0;

      final movingValue =
          data['moving'] ??
          data['movement'];

      final bool moving;

      if (movingValue is bool) {
        moving = movingValue;
      } else if (movingValue is num) {
        moving = movingValue != 0;
      } else if (movingValue is String) {
        final value =
            movingValue.toLowerCase();

        moving =
            value == '1' ||
            value == 'true' ||
            value == 'moving';
      } else {
        moving = false;
      }

      final timestamp =
          data['timestamp']?.toString() ?? '';

      // ========================================================
      // CREATE GPS DATA
      // ========================================================

      final animal = GpsData(
        deviceId: deviceId,
        battery: battery,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        satellites: satellites,
        speed: speed,
        moving: moving,
        timestamp: timestamp,
        rssi: rssi,
        snr: snr,
      );

      // ========================================================
      // UPDATE MAP STATE
      // ========================================================

      mapState.updateAnimalData(
        animal,
      );

      debugPrint(
        'MapState updated:',
      );

      debugPrint(
        'Device: ${animal.deviceId}',
      );

      debugPrint(
        'Location: '
        '${animal.latitude}, '
        '${animal.longitude}',
      );

      debugPrint(
        'Animals currently stored: '
        '${mapState.animals.length}',
      );

      debugPrint(
        '================================',
      );

      if (mounted) {
        setState(() {});
      }
    } catch (e, stackTrace) {
      debugPrint(
        'Error processing foreground animal data: $e',
      );

      debugPrint('$stackTrace');
    }
  });
}
  Future<void> loadLivestockLocations() async {
    final animals = await DatabaseHelper.instance.getDashboard();

    if (!mounted) return;

    setState(() {
      livestockLocations.clear();

      for (final animal in animals) {
        final animalId = animal["Animal_ID"];

        final latitude = animal["Latitude"];
        final longitude = animal["Longitude"];

        if (animalId == null || latitude == null || longitude == null) {
          continue;
        }

        livestockLocations[animalId as String] = LatLng(
          (latitude as num).toDouble(),
          (longitude as num).toDouble(),
        );
      }
    });
  }

  void showAnimalDetails(
  BuildContext context,
  GpsData animal,
) {
  showDialog(
    context: context,

    builder: (context) {
      return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.pets),

            const SizedBox(width: 8),

            Text(animal.deviceId),
          ],
        ),

        content: Column(
          mainAxisSize: MainAxisSize.min,

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // ---------------------------------------------------
            // MOVEMENT
            // ---------------------------------------------------

            _animalInfoRow(
              'Status',
              animal.moving
                  ? 'MOVING'
                  : 'STATIONARY',
            ),

            // ---------------------------------------------------
            // BATTERY
            // ---------------------------------------------------

            _animalInfoRow(
              'Battery',
              '${animal.battery.toStringAsFixed(2)} V',
            ),

            // ---------------------------------------------------
            // SPEED
            // ---------------------------------------------------

            _animalInfoRow(
              'Speed',
              '${animal.speed.toStringAsFixed(2)} m/s',
            ),

            // ---------------------------------------------------
            // SATELLITES
            // ---------------------------------------------------

            _animalInfoRow(
              'Satellites',
              '${animal.satellites}',
            ),

            // ---------------------------------------------------
            // RSSI
            // ---------------------------------------------------

            _animalInfoRow(
              'RSSI',
              '${animal.rssi} dBm',
            ),

            // ---------------------------------------------------
            // SNR
            // ---------------------------------------------------

            _animalInfoRow(
              'SNR',
              '${animal.snr.toStringAsFixed(2)} dB',
            ),

            // ---------------------------------------------------
            // ALTITUDE
            // ---------------------------------------------------

            _animalInfoRow(
              'Altitude',
              '${animal.altitude.toStringAsFixed(1)} m',
            ),

            const Divider(),

            // ---------------------------------------------------
            // LATITUDE
            // ---------------------------------------------------

            _animalInfoRow(
              'Latitude',
              animal.latitude.toStringAsFixed(5),
            ),

            // ---------------------------------------------------
            // LONGITUDE
            // ---------------------------------------------------

            _animalInfoRow(
              'Longitude',
              animal.longitude.toStringAsFixed(5),
            ),

            // ---------------------------------------------------
            // TIMESTAMP
            // ---------------------------------------------------

            _animalInfoRow(
              'Timestamp',
              animal.timestamp,
            ),
          ],
        ),

        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },

            child: const Text('CLOSE'),
          ),
        ],
      );
    },
  );
}
Widget _animalInfoRow(
  String label,
  String value,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(
      vertical: 3,
    ),

    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        SizedBox(
          width: 90,

          child: Text(
            label,

            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        Expanded(
          child: Text(value),
        ),
      ],
    ),
  );
}

  Future<void> connectLivestockWebSocket() async {
  // WebSocket connection is handled by BackgroundService.
  //
  // MapScreen should not create another WebSocket connection
  // because ESP8266 broadcasts every message to every client.
  //
  // Animal data should come through the application's shared state.

  debugPrint(
    'MapScreen: WebSocket handled by BackgroundService',
  );
}
  // ---------------------------------------------------------------------------
  // MAP LOCATION
  // ---------------------------------------------------------------------------

  void recenterToMyLocation() {
    final currentLocation = ref.read(mapStateControllerProvider).currentLocation;

    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location is not available yet.')),
      );
      return;
    }

    mapController.move(currentLocation, mapController.camera.zoom);
  }

  // ---------------------------------------------------------------------------
  // INITIALIZATION
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    loadTileDirectory();
    loadConnectivity();
    loadLivestockLocations();
    //connectWifi();
    connectLivestockWebSocket();
    listenToBackgroundAnimalData();

    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      loadLivestockLocations();

      if (mounted && robotConnected != wifi.isConnected) {
        setState(() {
          robotConnected = wifi.isConnected;
        });
      }
    });

    listenToLocation();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await geofence.loadGeofence();

      if (!mounted) return;

      setState(() {});
    });

    connectivityService.connectivityStream.listen((connected) {
      if (!mounted) return;

      setState(() {
        isOnline = connected;
      });

      debugPrint('Internet Available: $connected');
    });
  }

  // ---------------------------------------------------------------------------
  // WIFI / ROBOT
  // ---------------------------------------------------------------------------

  Future<void> connectWifi() async {
    final connected = await wifi.connect();

    if (!mounted) return;

    setState(() {
      robotConnected = connected;
    });
  }

  // ---------------------------------------------------------------------------
  // CONNECTIVITY
  // ---------------------------------------------------------------------------

  Future<void> loadConnectivity() async {
    isOnline = await connectivityService.isConnected();

    if (mounted) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // TILE DIRECTORY
  // ---------------------------------------------------------------------------

  Future<void> loadTileDirectory() async {
    tileDirectory = await TileCacheService.getTileDirectoryPath();

    if (mounted) {
      setState(() {});
    }

    debugPrint('Tile Directory: $tileDirectory');
  }

  // ---------------------------------------------------------------------------
  // GPS LOCATION
  // ---------------------------------------------------------------------------

  void listenToLocation() {
    positionStream = locationService.getPositionStream().listen((position) {
      final newLocation = LatLng(position.latitude, position.longitude);

      mapState.updateCurrentLocation(newLocation);

      if (mounted) {
        setState(() {});
      }
    });
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _refreshTimer?.cancel();
    positionStream?.cancel();
    livestockSubscription?.cancel();

    progressNotifier.dispose();
    wifi.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // OPEN ALERTS
  // ---------------------------------------------------------------------------

  Future<void> openAlerts() async {
    setState(() {
      unreadAlerts = 0;
    });

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AlertsScreen()),
    );
  }

  // ---------------------------------------------------------------------------
  // NOTIFICATION BUTTON
  // ---------------------------------------------------------------------------

  Widget buildNotificationButton() {
    return IconButton(
      tooltip: 'Notifications',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications),

          if (unreadAlerts > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  unreadAlerts > 9 ? '9+' : '$unreadAlerts',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      onPressed: openAlerts,
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Listen for new notification events.
    //
    // Because this screen is already a ConsumerStatefulWidget,
    // we do not need another Consumer widget around the Scaffold.
    ref.listen<List<LogEvent>>(notificationProvider, (previous, next) {
      if (!mounted) return;

      final previousLength = previous?.length ?? 0;

      if (next.isNotEmpty && next.length != previousLength) {
        final latestEvent = next.last;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(latestEvent.message),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );

        setState(() {
          unreadAlerts++;
        });
      }
    });

    return Scaffold(
      // -----------------------------------------------------------------------
      // APP BAR
      // -----------------------------------------------------------------------
      appBar: AppBar(
        title: const Text('Livestock Tracker'),

        actions: [buildNotificationButton()],
      ),

      // -----------------------------------------------------------------------
      // DRAWER
      // -----------------------------------------------------------------------
      drawer: AppDrawer(
        robotConnected: robotConnected,
        ledOn: ledOn,

        onLedPressed: () {
          if (!robotConnected) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Robot is not connected.')),
            );

            return;
          }

          if (ledOn) {
            wifi.send('LED_OFF');
          } else {
            wifi.send('LED_ON');
          }

          setState(() {
            ledOn = !ledOn;
          });
        },

        onGeoFenceTap: () async {
          await geofence.startEditing(mapController.camera.center);

          if (!mounted) return;

          setState(() {});
        },
      ),

      // -----------------------------------------------------------------------
      // FLOATING ACTION BUTTONS
      // -----------------------------------------------------------------------
      floatingActionButton: AnimatedPadding(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,

        padding: EdgeInsets.only(bottom: geofence.showPanel ? 85 : 0),

        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // -----------------------------------------------------------------
            // CURRENT LOCATION BUTTON
            // -----------------------------------------------------------------
            FloatingActionButton(
              heroTag: 'locateMe',
              tooltip: 'Show my location',
              onPressed: recenterToMyLocation,
              child: const Icon(Icons.my_location),
            ),

            // -----------------------------------------------------------------
            // SELECT MAP DOWNLOAD AREA
            // -----------------------------------------------------------------
            if (isOnline) ...[
              const SizedBox(height: 12),

              FloatingActionButton(
                heroTag: 'selectBounds',
                tooltip: 'Select map area',

                onPressed: () {
                  final center = mapController.camera.center;

                  const double offset = 0.01;

                  mapState.updateSelectedBounds(
                    LatLngBounds(
                      LatLng(
                        center.latitude - offset,
                        center.longitude - offset,
                      ),
                      LatLng(
                        center.latitude + offset,
                        center.longitude + offset,
                      ),
                    ),
                  );

                  setState(() {});
                },

                child: const Icon(Icons.crop_square),
              ),
            ],
          ],
        ),
      ),

      // -----------------------------------------------------------------------
      // MAP DOWNLOAD BUTTON
      // -----------------------------------------------------------------------
      bottomNavigationBar: mapState.selectedBounds == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(12),

              child: ElevatedButton(
                onPressed: () async {
                  showDialog(
                    context: context,
                    barrierDismissible: false,

                    builder: (_) => DownloadProgressDialog(
                      progressNotifier: progressNotifier,

                      onCancel: () {
                        downloader.cancelDownload();
                      },
                    ),
                  );

                  await downloader.downloadArea(
                    bounds: mapState.selectedBounds!,
                    minZoom: 13,
                    maxZoom: 17,

                    onProgress: (progress) {
                      progressNotifier.value = progress;
                    },
                  );

                  if (mounted) {
                    Navigator.of(context).pop();
                  }

                  if (!mounted) return;

                  if (downloader.isCancelled) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Download cancelled')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Map downloaded successfully'),
                      ),
                    );

                    ref
                        .read(notificationProvider.notifier)
                        .log(
                          LogEventType.mapDownloaded,
                          'Offline map downloaded '
                          '(zoom up to 17)',
                        );
                  }

                  mapState.clearSelectedBounds();

                  setState(() {});
                },

                child: const Text('Download Area'),
              ),
            ),

      // -----------------------------------------------------------------------
      // BODY
      // -----------------------------------------------------------------------
      body: Stack(
        children: [
          // -------------------------------------------------------------------
          // MAP
          // -------------------------------------------------------------------
          FlutterMap(
            mapController: mapController,

            options: MapOptions(
              initialCenter:
                  mapState.currentLocation ?? const LatLng(27.7172, 85.3240),

              initialZoom: 15,

              maxZoom: 17,
            ),

            children: [
              // ---------------------------------------------------------------
              // ONLINE MAP
              // ---------------------------------------------------------------
              if (isOnline)
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/'
                      '{z}/{x}/{y}.png',

                  userAgentPackageName: 'com.example.livestock_tracker',
                )
              // ---------------------------------------------------------------
              // OFFLINE MAP
              // ---------------------------------------------------------------
              else if (tileDirectory != null)
                TileLayer(
                  tileProvider: FileTileProvider(),

                  urlTemplate: '$tileDirectory/{z}/{x}/{y}.png',
                ),

              // ---------------------------------------------------------------
              // CURRENT LOCATION
              // ---------------------------------------------------------------
              CurrentLocationLayer(
                alignPositionOnUpdate: AlignOnUpdate.never,

                alignDirectionOnUpdate: AlignOnUpdate.never,

                style: LocationMarkerStyle(
                  marker: const DefaultLocationMarker(color: Colors.blue),

                  markerSize: const Size(24, 24),

                  headingSectorColor: Colors.blue.withValues(alpha: 0.4),

                  headingSectorRadius: 80,
                ),
              ),

              // ---------------------------------------------------------------
              // GEOFENCE / MAP LAYERS
              // ---------------------------------------------------------------
              MapLayers(
                geofence: geofence,

                currentLocation: mapState.currentLocation,

                selectedBounds: mapState.selectedBounds,

                refresh: () {
                  setState(() {});
                },
              ),

              // ---------------------------------------------------------------
              // LIVESTOCK MARKERS
              // ---------------------------------------------------------------
              MarkerLayer(
                markers: livestockLocations.entries.map((entry) {
                  return Marker(
                    point: entry.value,

                    width: 60,
                    height: 60,

                    child: Column(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        // ---------------------------------------------------
                        // ANIMAL MARKER
                        // ---------------------------------------------------
                        Container(
                          width: 22,
                          height: 22,

                          decoration: BoxDecoration(
                            color: Colors.blue,

                            shape: BoxShape.circle,

                            border: Border.all(color: Colors.white, width: 4),

                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 5,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 4),

                        // ---------------------------------------------------
                        // ANIMAL ID
                        // ---------------------------------------------------
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),

                          decoration: BoxDecoration(
                            color: Colors.white,

                            borderRadius: BorderRadius.circular(12),

                            boxShadow: const [
                              BoxShadow(blurRadius: 3, color: Colors.black26),
                            ],
                          ),

                          child: Text(
                            entry.key,

                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
// ---------------------------------------------------------------
// LIVE ESP8266 ANIMALS
// ---------------------------------------------------------------

if (mapState.animals.isNotEmpty)
  MarkerLayer(
    markers: mapState.animals.values.map((animal) {
      return Marker(
        point: LatLng(
          animal.latitude,
          animal.longitude,
        ),

        width: 80,
        height: 75,

        child: GestureDetector(
          onTap: () {
            showAnimalDetails(context, animal);
          },

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              // ---------------------------------------------------
              // ANIMAL ICON
              // ---------------------------------------------------

              Container(
                width: 30,
                height: 30,

                decoration: BoxDecoration(
                  color: animal.moving
                      ? Colors.orange
                      : Colors.green,

                  shape: BoxShape.circle,

                  border: Border.all(
                    color: Colors.white,
                    width: 4,
                  ),

                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 5,
                      color: Colors.black38,
                    ),
                  ],
                ),

                child: const Icon(
                  Icons.pets,
                  color: Colors.white,
                  size: 18,
                ),
              ),

              const SizedBox(height: 3),

              // ---------------------------------------------------
              // ANIMAL ID
              // ---------------------------------------------------

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(10),

                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 3,
                      color: Colors.black26,
                    ),
                  ],
                ),

                child: Text(
                  animal.deviceId,

                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
  ),
            ],
          ),

          // -------------------------------------------------------------------
          // GEOFENCE PANEL
          // -------------------------------------------------------------------
          GeofencePanel(
            showGeofencePanel: geofence.showPanel,

            geofence: geofence,

            refresh: () {
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
