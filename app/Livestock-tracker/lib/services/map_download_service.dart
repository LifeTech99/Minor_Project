import 'package:flutter_map/flutter_map.dart';
import '../models/download_progress.dart';
import 'tile_cache_service.dart';
import 'tile_calculator.dart';

class MapDownloadService {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled; 
  void cancelDownload() {
    _isCancelled = true;
  }

  void resetCancellation() {
    _isCancelled = false;
  } 
  Future<void> downloadArea({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    resetCancellation();
    // -------- PASS 1: Calculate total number of tiles --------
    int totalTiles = 0;

    for (int zoom = minZoom; zoom <= maxZoom; zoom++) {
      final minX = TileCalculator.longitudeToTileX(bounds.west, zoom);
      final maxX = TileCalculator.longitudeToTileX(bounds.east, zoom);

      final minY = TileCalculator.latitudeToTileY(bounds.north, zoom);
      final maxY = TileCalculator.latitudeToTileY(bounds.south, zoom);

      totalTiles += (maxX - minX + 1) * (maxY - minY + 1);
    }

    // -------- PASS 2: Download tiles and report progress --------
    int downloadedTiles = 0;

    for (int zoom = minZoom; zoom <= maxZoom; zoom++) {
      final minX = TileCalculator.longitudeToTileX(bounds.west, zoom);
      final maxX = TileCalculator.longitudeToTileX(bounds.east, zoom);

      final minY = TileCalculator.latitudeToTileY(bounds.north, zoom);
      final maxY = TileCalculator.latitudeToTileY(bounds.south, zoom);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          if (_isCancelled) {
            return;
          }

          if (!await TileCacheService.tileExists(
            zoom: zoom,
            x: x,
            y: y,
          )) {
            await TileCacheService.downloadTile(
              zoom: zoom,
              x: x,
              y: y,
            );
          }

          downloadedTiles++;
          onProgress?.call(
            DownloadProgress(
              downloadedTiles: downloadedTiles,
              totalTiles: totalTiles,
              currentZoom: zoom,
            ),
          );
        }
      }
    }
  }
}