import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';


class TileCacheService {
  /// Returns the local file for a tile.
  static Future<File> _tileFile({
    required int zoom,
    required int x,
    required int y,
  }) async {
    final dir = await getApplicationDocumentsDirectory();

    return File(
      '${dir.path}/tiles/$zoom/$x/$y.png',
    );
  }

  /// Returns true if the tile already exists.
  static Future<bool> tileExists({
    required int zoom,
    required int x,
    required int y,
  }) async {
    final file = await _tileFile(
      zoom: zoom,
      x: x,
      y: y,
    );

    return file.exists();
  }

  /// Returns the tile file if it exists.
  static Future<File?> getTile({
    required int zoom,
    required int x,
    required int y,
  }) async {
    final file = await _tileFile(
      zoom: zoom,
      x: x,
      y: y,
    );

    if (await file.exists()) {
      return file;
    }

    return null;
  }

    /// Downloads and caches a tile.
    /// Downloads and caches a tile.
  static Future<void> downloadTile({
    required int zoom,
    required int x,
    required int y,
  }) async {
    if (await tileExists(
      zoom: zoom,
      x: x,
      y: y,
    )) {
      return;
    }

    final url =
        'https://tile.openstreetmap.org/$zoom/$x/$y.png';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) return;

      final file = await _tileFile(
        zoom: zoom,
        x: x,
        y: y,
      );

      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
    } catch (_) {
      // Ignore network errors.
    }
  }
  /// Returns the application's tile directory.
/// Returns the root tile directory path.
  static Future<String> getTileDirectoryPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/tiles';
  }
    /// Downloads all tiles within a selected area for a range of zoom levels.

}