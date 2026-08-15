import 'dart:math';
import 'package:latlong2/latlong.dart';

class GeofenceUtils {
  static const double epsilon = 1e-10;

  static bool isPointInsidePolygon(
    LatLng point,
    List<LatLng> polygon,
  ) {
    if (polygon.length < 3) return false;

    // Boundary check
    for (int i = 0; i < polygon.length; i++) {
      final LatLng a = polygon[i];
      final LatLng b = polygon[(i + 1) % polygon.length];

      if (_isPointOnSegment(point, a, b)) {
        return true;
      }
    }

    bool inside = false;

    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;

      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;

      final intersect =
          ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) *
                      (point.latitude - yi) /
                      (yj - yi) +
                  xi);

      if (intersect) {
        inside = !inside;
      }

      j = i;
    }

    return inside;
  }

  static bool _isPointOnSegment(
    LatLng p,
    LatLng a,
    LatLng b,
  ) {
    final cross =
        (p.latitude - a.latitude) * (b.longitude - a.longitude) -
        (p.longitude - a.longitude) * (b.latitude - a.latitude);

    if (cross.abs() > epsilon) {
      return false;
    }

    final dot =
        (p.longitude - a.longitude) * (b.longitude - a.longitude) +
        (p.latitude - a.latitude) * (b.latitude - a.latitude);

    if (dot < 0) {
      return false;
    }

    final squaredLength =
        pow(b.longitude - a.longitude, 2) +
        pow(b.latitude - a.latitude, 2);

    return dot <= squaredLength;
  }
}