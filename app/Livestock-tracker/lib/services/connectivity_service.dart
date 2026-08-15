import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  /// Returns the current network status.
  Future<bool> isConnected() async {
    final result = await _connectivity.checkConnectivity();

    return result.contains(ConnectivityResult.mobile) ||
        result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
  }

  /// Stream of connectivity changes.
  Stream<bool> get connectivityStream {
    return _connectivity.onConnectivityChanged.map(
      (results) =>
          results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet),
    );
  }
}