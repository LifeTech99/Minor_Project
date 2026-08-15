import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/gps_data.dart';

class MapStateController extends ChangeNotifier {
  LatLng? currentLocation;

  // ============================================================
  // ANIMAL DATA
  // ============================================================

  // Store data for every animal using device ID
  final Map<String, GpsData> animals = {};

  // Keep this for compatibility with existing code
  GpsData? animalData;

  LatLngBounds? selectedBounds;

  bool showGeofencePanel = false;

  final List<Marker> animalMarkers = [];

  // ============================================================
  // CURRENT LOCATION
  // ============================================================

  void updateCurrentLocation(
    LatLng location,
  ) {
    currentLocation = location;

    notifyListeners();
  }

  // ============================================================
  // UPDATE ANIMAL DATA
  // ============================================================

  void updateAnimalData(
    GpsData data,
  ) {
    // Store/update animal using device ID
    animals[data.deviceId] = data;

    // Keep latest animal for existing code
    animalData = data;

    // Rebuild all animal markers
    _updateAnimalMarkers();

    notifyListeners();
  }

  // ============================================================
  // UPDATE ALL ANIMAL MARKERS
  // ============================================================

void _updateAnimalMarkers() {
  animalMarkers.clear();

  for (final data in animals.values) {
    final animalLocation = LatLng(
      data.latitude,
      data.longitude,
    );

    animalMarkers.add(
      Marker(
        point: animalLocation,
        width: 60,
        height: 60,
        child: GestureDetector(
          onTap: () {
            // Optional later
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: data.moving
                  ? Colors.orange
                  : Colors.green,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 3,
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
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

  // ============================================================
  // GET ANIMAL
  // ============================================================

  GpsData? getAnimal(String deviceId) {
    return animals[deviceId];
  }

  // ============================================================
  // SELECTED BOUNDS
  // ============================================================

  void updateSelectedBounds(
    LatLngBounds bounds,
  ) {
    selectedBounds = bounds;

    notifyListeners();
  }

  void clearSelectedBounds() {
    selectedBounds = null;

    notifyListeners();
  }

  // ============================================================
  // GEOFENCE PANEL
  // ============================================================

  void showPanel() {
    showGeofencePanel = true;

    notifyListeners();
  }

  void hidePanel() {
    showGeofencePanel = false;

    notifyListeners();
  }

  // ============================================================
  // MANUAL MARKERS
  // ============================================================

  void setAnimalMarkers(
    List<Marker> markers,
  ) {
    animalMarkers
      ..clear()
      ..addAll(markers);

    notifyListeners();
  }

  void addAnimalMarker(
    Marker marker,
  ) {
    animalMarkers.add(marker);

    notifyListeners();
  }

  // ============================================================
  // REMOVE ONE ANIMAL
  // ============================================================

  void removeAnimal(String deviceId) {
    animals.remove(deviceId);

    _updateAnimalMarkers();

    if (animalData?.deviceId == deviceId) {
      animalData = null;
    }

    notifyListeners();
  }

  // ============================================================
  // CLEAR ALL ANIMALS
  // ============================================================

  void clearAnimals() {
    animals.clear();

    animalMarkers.clear();

    animalData = null;

    notifyListeners();
  }
}