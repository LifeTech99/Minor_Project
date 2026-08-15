import 'package:latlong2/latlong.dart';
import '../database/database_helper.dart';
import 'dart:math' as math;


class EdgeHandle {
  final int edgeIndex;
  final LatLng position;

  EdgeHandle({
    required this.edgeIndex,
    required this.position,
  });
}


class GeofenceController {
  bool isEditing = false;
  bool showPanel = false;
  List<LatLng> points = [];
  List<LatLng> savedPoints = [];
  int? selectedVertex;
  int? activeInsertedVertex;

  double _calculateDistance(LatLng p1, LatLng p2) {
    final dx = p1.latitude - p2.latitude;
    final dy = p1.longitude - p2.longitude;
    return math.sqrt(dx * dx + dy * dy);
  }

  void removeVertexIfNeeded(int index) {
    if (points.length <= 3) return;

    final previousIndex =
        (index - 1 + points.length) % points.length;

    final nextIndex =
        (index + 1) % points.length;

    const threshold = 0.0001;

    if (_calculateDistance(points[index], points[previousIndex]) <
            threshold ||
          _calculateDistance(points[index], points[nextIndex]) <
            threshold) {
      points.removeAt(index);
    }
  } 

  List<EdgeHandle> getEdgeHandles() {
    final handles = <EdgeHandle>[];

    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];

      handles.add(
        EdgeHandle(
          edgeIndex: i,
          position: LatLng(
            (p1.latitude + p2.latitude) / 2,
            (p1.longitude + p2.longitude) / 2,
          ),
        ),
      );
    }

    return handles;
  }  
  

  int insertVertex(int edgeIndex) {
    final p1 = points[edgeIndex];
    final p2 = points[(edgeIndex + 1) % points.length];

    final midpoint = LatLng(
      (p1.latitude + p2.latitude) / 2,
      (p1.longitude + p2.longitude) / 2,
    );

    points.insert(edgeIndex + 1, midpoint);

    return edgeIndex + 1;
  }


  Future<void> loadGeofence() async {
    final fence = await DatabaseHelper.instance.getGeofence();

    if (fence != null) {
      final points = await DatabaseHelper.instance
          .getGeofencePoints(fence['id'] as int);

      this.points = List.from(points);
      savedPoints = List.from(points);
    }
  }
  
  
  Future<void> startEditing(LatLng center) async{
    isEditing = true;
    showPanel = true;
    final fence = await DatabaseHelper.instance.getGeofence();
    
    if (fence != null) {
      savedPoints = await DatabaseHelper.instance
        .getGeofencePoints(fence['id'] as int);

      points = List.from(savedPoints);
    } else {
      points = [
        LatLng(center.latitude + 0.0005, center.longitude),
        LatLng(center.latitude - 0.0005, center.longitude - 0.0005),
        LatLng(center.latitude - 0.0005, center.longitude + 0.0005),
      ];
    }
  }
  void stopEditing() {
    isEditing = false;
    showPanel = false;
  }
  void save() async {
    stopEditing();
    await DatabaseHelper.instance.insertGeofence(
      name: "Farm A",
      points: points,
    );
    savedPoints = List.from(points);
    
  }
  void delete() async {
    points.clear();
    savedPoints.clear();
    await DatabaseHelper.instance.deleteAllGeofences(); 
    stopEditing();
  }
  void cancel() {
    if (savedPoints.isEmpty) {
      points.clear();
    } else {
      points = List.from(savedPoints);
    }
    stopEditing();
  }

}