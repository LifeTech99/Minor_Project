import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/map_state_controller.dart';

final mapStateControllerProvider =
    Provider<MapStateController>((ref) {
  final controller = MapStateController();

  ref.onDispose(() {
    controller.dispose();
  });

  return controller;
});