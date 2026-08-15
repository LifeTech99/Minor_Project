import 'package:flutter/material.dart';
import 'screens/map_screen.dart';
import 'services/background_service.dart';
import 'package:permission_handler/permission_handler.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Request notification permission from the main isolate.
    await Permission.notification.request();

    // Configure background service.
    await BackgroundService.initialize();

    // Start background service after Flutter UI has started.
    await BackgroundService.start();
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OnlineMapScreen(),
    );
  }
}