import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'dart:collection';
import 'package:permission_handler/permission_handler.dart';


class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<ScanResult> scanResultList = [];
  Map<String, Queue<int>> rssiHistory = {}; // Últimos valores para promedio
  Map<String, DateTime> lastSeen = {}; // Última vez que se recibió paquete

  bool _bluetoothOn = true;

  final int rssiWindow = 5; // Ventana de suavizado

  bool isScanning = false;
  StreamSubscription<List<ScanResult>>? scanSubscription;

  @override
  void initState() {
    super.initState();

    _checkPermissionsAndBluetooth();
  }

    Future<void> _checkPermissionsAndBluetooth() async {
    // Solicita permisos
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // Escucha el estado del Bluetooth
    FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        _bluetoothOn = state == BluetoothAdapterState.on;
      });
      if (_bluetoothOn && !isScanning) {
        _startScan();
      }
    });

    // Verifica el estado inicial
    final state = await FlutterBluePlus.adapterState.first;
    setState(() {
      _bluetoothOn = state == BluetoothAdapterState.on;
    });
    if (_bluetoothOn) {
      _startScan();
    }
  }

  void _startScan() {
// Inicia escaneo continuo
    FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode.lowLatency, // Más lecturas por segundo
      oneByOne: false,
    );
    isScanning = true;

    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (var result in results) {
        final id = result.device.id.id;

        // --- Guardar histórico de RSSI ---
        rssiHistory.putIfAbsent(id, () => Queue<int>());
        final history = rssiHistory[id]!;

        history.addLast(result.rssi);
        if (history.length > rssiWindow) {
          history.removeFirst();
        }

        // --- Guardar timestamp ---
        lastSeen[id] = DateTime.now();

        // --- Calcular promedio ---
        final avgRssi = history.reduce((a, b) => a + b) ~/ history.length;

        // Guardar en lista principal usando el promedio como RSSI
        final smoothedResult = ScanResult(
          device: result.device,
          advertisementData: result.advertisementData,
          rssi: avgRssi,
          timeStamp: result.timeStamp,
        );

        int index = scanResultList.indexWhere((r) => r.device.id.id == id);
        if (index >= 0) {
          scanResultList[index] = smoothedResult;
        } else {
          scanResultList.add(smoothedResult);
        }
      }

      // Elimina dispositivos que ya no están
      scanResultList.removeWhere(
        (r) => !results.any((res) => res.device.id.id == r.device.id.id),
      );

      setState(() {}); // Refrescar siempre
    });
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    super.dispose();
  }

  Widget deviceSignal(ScanResult r) {
    final lastRssi = rssiHistory[r.device.id.id]?.last ?? r.rssi;
    final seen = lastSeen[r.device.id.id];
    final seenText = seen != null
        ? "${seen.hour.toString().padLeft(2, '0')}:${seen.minute.toString().padLeft(2, '0')}:${seen.second.toString().padLeft(2, '0')}"
        : "--:--:--";

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          "${r.rssi} dBm",
          style: TextStyle(fontWeight: FontWeight.bold),
        ), // Promedio
        Text(
          "(${lastRssi} dBm)",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ), // Última lectura
        Text(
          "Visto: $seenText",
          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
        ), // Hora última actualización
      ],
    );
  }

  Widget deviceMacAddress(ScanResult r) {
    return Text(r.device.id.id);
  }

  Widget deviceName(ScanResult r) {
    String name;
    if (r.advertisementData.localName.isNotEmpty) {
      name = r.advertisementData.localName;
    } else if (r.device.name.isNotEmpty) {
      name = r.device.name;
    } else {
      name = 'N/A';
    }
    return Text(name);
  }

  Widget leading(ScanResult r) {
    return CircleAvatar(
      backgroundColor: Colors.cyan,
      child: Icon(Icons.bluetooth, color: Colors.white),
    );
  }

  Widget listItem(ScanResult r) {
    return ListTile(
      leading: leading(r),
      title: deviceName(r),
      subtitle: deviceMacAddress(r),
      trailing: deviceSignal(r),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_bluetoothOn) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(
          child: Text(
            'Por favor, enciende el Bluetooth para buscar dispositivos.',
            style: TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // Filtrar solo los dispositivos con nombre
    final filteredList = scanResultList.where((r) {
      final name = r.advertisementData.localName.isNotEmpty
          ? r.advertisementData.localName
          : r.device.name;
      return name.isNotEmpty;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView.separated(
        itemCount: filteredList.length,
        itemBuilder: (context, index) => listItem(filteredList[index]),
        separatorBuilder: (context, index) => const Divider(),
      ),
    );
  }
}
