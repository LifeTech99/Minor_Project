import 'dart:async';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import 'location_screen.dart';
import 'package:data_table_2/data_table_2.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, Object?>> records = [];
  String selectedFilter = "Present Data";
  Timer? _refreshTimer;

  @override
    void initState() {
    super.initState();
    loadData();

      _refreshTimer = Timer.periodic(
    const Duration(seconds: 2),
    (_) => loadData(),
  );
  }
  @override
void dispose() {
  _refreshTimer?.cancel();
  super.dispose();
}

  Future<void> loadData() async {
    switch (selectedFilter) {
      case "Present Data":
        records = await DatabaseHelper.instance.getDashboard();
        break;

      case "Last 15 Days":
        records =
            await DatabaseHelper.instance.getDashboardLast15Days();
        break;

      case "Last 30 Days":
        records =
            await DatabaseHelper.instance.getDashboardLast30Days();
        break;

      case "All Data":
        records =
            await DatabaseHelper.instance.getDashboardHistory();
        break;
    }

    setState(() {});
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard"),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          children: [

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,

              children: [
                const Text(
                  "Livestock History",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                PopupMenuButton<String>(
                  onSelected: (value) async{
                      selectedFilter = value;
                      await loadData();
                    },
                  

                    // Database query here later
                  
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: "Present Data",
                      child: Text("Present Data"),
                    ),

                    PopupMenuItem(
                      value: "Last 15 Days",
                      child: Text("Last 15 Days"),
                    ),

                    PopupMenuItem(
                      value: "Last 30 Days",
                      child: Text("Last 30 Days"),
                    ),

                    PopupMenuItem(
                      value: "All Data",
                      child: Text("All Data"),
                    ),
                  ],

                  child: Row(
                    children: [
                      Text(selectedFilter),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Expanded(
                child: DataTable2(
                      fixedTopRows: 1,
                      minWidth: 700,
                      columnSpacing: 20,
                      horizontalMargin: 12,
                  columns: const [

                    DataColumn(
                      label: Text("ID"),
                    ),

                    DataColumn(
                      label: Text("Location"),
                    ),

                    DataColumn(
                      label: Text("Status"),
                    ),

                    DataColumn(
                      label: Text("Date"),
                    ),
                    DataColumn(
                      label: Text("Battery"),
                    ),
                     
                  ],

                 rows: records.map((row){
                   return DataRow(
                      cells: [

                        DataCell(
                          Text(row["Animal_ID"].toString()),
                        ),

                        DataCell(
                         TextButton(
  child: const Text("View"),
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationScreen(
          animalId: row["Animal_ID"].toString(),
          latitude: row["Latitude"] as double,
          longitude: row["Longitude"] as double,
        ),
      ),
    );
  },
),
    ),

                        DataCell(
                              Text(
                row["Geofence_Status"].toString(),
              ),
                        ),

                        DataCell(
                          Text(
                selectedFilter == "Present Data"
                  ? row["Timestamp"].toString().replaceFirst("T", " ").substring(0, 19)
                  : row["Timestamp"].toString().replaceFirst("T", " ").substring(0, 19),
              ),
                        ),

                      DataCell(
                        Text("${row["Battery"]}%"),
                      ),
                  ],
                    );
  },
                ).toList(),
              ),

            ),
                        ],
        ),
      ),
        );
  }
}