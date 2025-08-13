import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'dart:collection';
import 'package:permission_handler/permission_handler.dart';

class CasetaPage extends StatefulWidget {
  const CasetaPage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<CasetaPage> createState() => _CasetaPageState();
}

class _CasetaPageState extends State<CasetaPage> {
  String estadoConexion = 'Sin conexión';
  Color colorEstado = Colors.black;
  List<ScanResult> beaconsDelim =
      []; // Lista para beacons que empiezan con "Delim"

  List<ScanResult> scanResultList = [];
  Map<String, Queue<int>> rssiHistory = {};
  Map<String, DateTime> lastSeen = {};

  bool _bluetoothOn = true;
  final int rssiWindow = 5;
  bool isScanning = false;
  StreamSubscription<List<ScanResult>>? scanSubscription;

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndBluetooth();
  }

  Future<void> _checkPermissionsAndBluetooth() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        _bluetoothOn = state == BluetoothAdapterState.on;
        if (!_bluetoothOn) {
          estadoConexion = 'Sin conexión';
          colorEstado = Colors.black;
          beaconsDelim.clear();
        }
      });
      if (_bluetoothOn && !isScanning) {
        _startScan();
      }
    });

    final state = await FlutterBluePlus.adapterState.first;
    setState(() {
      _bluetoothOn = state == BluetoothAdapterState.on;
    });
    if (_bluetoothOn) {
      _startScan();
    }
  }

  void _startScan() {
    FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode.lowLatency,
      oneByOne: false,
    );
    isScanning = true;

    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      // Filtrar beacons que empiezan con "Delim" y están en el rango de RSSI
      final delimBeacons = results.where((result) {
        final name = result.advertisementData.localName.isNotEmpty
            ? result.advertisementData.localName
            : result.device.name;
        return name.startsWith('Delim') &&
            result.rssi >= -100 &&
            result.rssi <= -1;
      }).toList();

      // Actualizar estado según los beacons detectados
      setState(() {
        if (!_bluetoothOn) {
          estadoConexion = 'Sin conexión';
          colorEstado = Colors.black;
        } else if (delimBeacons.isNotEmpty) {
          estadoConexion = 'Conectado';
          colorEstado = Colors.green;
        } else {
          estadoConexion = 'Fuera de línea';
          colorEstado = Colors.orange;
        }

        beaconsDelim = delimBeacons;
      });

      // Procesamiento adicional para histórico de RSSI
      for (var result in delimBeacons) {
        final id = result.device.id.id;
        rssiHistory.putIfAbsent(id, () => Queue<int>());
        final history = rssiHistory[id]!;
        history.addLast(result.rssi);
        if (history.length > rssiWindow) {
          history.removeFirst();
        }
        lastSeen[id] = DateTime.now();
      }
    });
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Widget _buildBeaconList() {
    if (beaconsDelim.isEmpty) {
      return Center(
        child: Text(
          'No se detectan beacons Delim',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: beaconsDelim.length,
      itemBuilder: (context, index) {
        final beacon = beaconsDelim[index];
        final name = beacon.advertisementData.localName.isNotEmpty
            ? beacon.advertisementData.localName
            : beacon.device.name;
        final rssi = beacon.rssi;
        final lastSeenTime = lastSeen[beacon.device.id.id] ?? DateTime.now();

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: _getSignalColor(rssi),
            child: Icon(Icons.bluetooth, color: Colors.white),
          ),
          title: Text(name),
          subtitle: Text(beacon.device.id.id),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${rssi} dBm',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Visto: ${lastSeenTime.hour}:${lastSeenTime.minute}:${lastSeenTime.second}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getSignalColor(int rssi) {
    // Mientras más cercano a 0 (pero negativo), mejor señal
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.blue;
    if (rssi >= -85) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(
              estadoConexion,
              style: TextStyle(
                fontSize: 32,
                color: colorEstado,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(child: _buildBeaconList()),
          ],
        ),
      ),
    );
  }
}
