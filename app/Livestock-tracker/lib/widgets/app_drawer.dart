import 'package:flutter/material.dart';
import '../screens/dashboard_screen.dart';

class AppDrawer extends StatelessWidget {
  final VoidCallback onGeoFenceTap;
  final bool robotConnected;
  final bool ledOn;
  final VoidCallback onLedPressed;

  const AppDrawer({
    super.key,
    required this.onGeoFenceTap,
    required this.robotConnected,
    required this.ledOn,
    required this.onLedPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 240,
            child: DrawerHeader(
              decoration: BoxDecoration(color: Colors.green),
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.pets, size: 60, color: Colors.white),
                  const SizedBox(height: 8),
                  const Text(
                    "Livestock Tracker",
                    style: TextStyle(color: Colors.white, fontSize: 22),
                  ),

                  Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          robotConnected ? Icons.wifi : Icons.wifi_off,
                          color: robotConnected ? Colors.white : Colors.red,
                        ),

                        const SizedBox(width: 8),

                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.lightbulb,
                            color: ledOn ? Colors.yellow : Colors.white,
                          ),
                          onPressed: robotConnected ? onLedPressed : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text("Home"),
            onTap: () {
              Navigator.pop(context);
            },
          ),

          ListTile(
            leading: const Icon(Icons.map),
            title: const Text("Map"),
            onTap: () {
              Navigator.pop(context);
            },
          ),

          ListTile(
            leading: const Icon(Icons.location_on),
            title: const Text("Geo-Fence"),
            onTap: () {
              Navigator.pop(context);
              onGeoFenceTap();
            },
          ),

          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text("Dashboard"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text("Settings"),
            onTap: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
