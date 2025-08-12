import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<ScanResult> scanResultList = [];
  var scan_mode = 0;
  bool isScanning = false;
  Timer? periodicScanTimer;
  StreamSubscription<List<ScanResult>>? scanSubscription;
  // Guarda los dispositivos conectados para evitar reconexiones
  final Set<String> connectedDeviceIds = {};

  @override
  void initState() {
    super.initState();
    FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode(scan_mode),
      oneByOne: false,
    );
    isScanning = true;
    setState(() {});
    scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (var result in results) {
        int index = scanResultList.indexWhere(
          (r) => r.device.id.id == result.device.id.id,
        );
        if (index >= 0) {
          scanResultList[index] = result;
        } else {
          scanResultList.add(result);
        }

        // --- CONEXIÓN AUTOMÁTICA SI EL NOMBRE EMPIEZA CON "delim" ---
        final name = result.advertisementData.localName.isNotEmpty
            ? result.advertisementData.localName
            : result.device.name;
        if (name.toLowerCase().startsWith('delim') &&
            !connectedDeviceIds.contains(result.device.id.id)) {
          try {
            await result.device.connect(
              autoConnect: false,
              timeout: Duration(seconds: 8),
            );
            connectedDeviceIds.add(result.device.id.id);
            print('Conectado a ${result.device.id.id}');
          } catch (e) {
            print('No se pudo conectar a ${result.device.id.id}: $e');
          }
        }
      }
      scanResultList.removeWhere(
        (r) => !results.any((res) => res.device.id.id == r.device.id.id),
      );
      setState(() {});
    });
    //startPeriodicScan();
  }

  @override
  void dispose() {
    periodicScanTimer?.cancel();
    scanSubscription?.cancel();
    super.dispose();
  }

  void startPeriodicScan() {
    periodicScanTimer?.cancel();
    periodicScanTimer = Timer.periodic(Duration(seconds: 4), (_) async {
      if (!isScanning) {
        isScanning = true;
        FlutterBluePlus.startScan(
          androidScanMode: AndroidScanMode(scan_mode),
          oneByOne: false,
        );
        setState(() {});
      }
      // Detén el escaneo después de 2 segundos
      await Future.delayed(Duration(seconds: 2));
      FlutterBluePlus.stopScan();
      isScanning = false;
      setState(() {});
    });
  }

  /* 시작, 정지 */
  void toggleState() {
    isScanning = !isScanning;

    if (isScanning) {
      FlutterBluePlus.startScan(
        androidScanMode: AndroidScanMode(scan_mode),
        oneByOne: false,
      );
      //scan();
    } else {
      FlutterBluePlus.stopScan();
    }
    setState(() {});
  }

  /* 
  Scan Mode
  Ts = scan interval 
  Ds = duration of every scan window
             | Ts [s] | Ds [s]
  LowPower   | 5.120  | 1.024
  BALANCED   | 4.096  | 1.024
  LowLatency | 4.096  | 4.096

  LowPower = ScanMode(0);
  BALANCED = ScanMode(1);
  LowLatency = ScanMode(2);

  opportunistic = ScanMode(-1);
   */

  /* Scan */
  void scan() async {
    if (isScanning) {
      FlutterBluePlus.scanResults.listen((results) {
        // Actualiza o agrega dispositivos según su id-
        for (var result in results) {
          int index = scanResultList.indexWhere(
            (r) => r.device.id.id == result.device.id.id,
          );
          if (index >= 0) {
            // Actualiza el RSSI y datos si ya existe
            scanResultList[index] = result;
          } else {
            // Agrega nuevo dispositivo
            scanResultList.add(result);
          }
        }
        // Limpia dispositivos que ya no están presentes
        scanResultList.removeWhere(
          (r) => !results.any((res) => res.device.id.id == r.device.id.id),
        );
        setState(() {});
      });
    }
  }

  /* device RSSI */
  Widget deviceSignal(ScanResult r) {
    return Text(r.rssi.toString());
  }

  /* device MAC address  */
  Widget deviceMacAddress(ScanResult r) {
    return Text(r.device.id.id);
  }

  /* device name  */
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

  /* BLE icon widget */
  Widget leading(ScanResult r) {
    return CircleAvatar(
      backgroundColor: Colors.cyan,
      child: Icon(Icons.bluetooth, color: Colors.white),
    );
  }

  void onTap(ScanResult r) {
    print('${r.device.name}');
  }

  /* ble item widget */
  Widget listItem(ScanResult r) {
    return ListTile(
      onTap: () => onTap(r),
      leading: leading(r),
      title: deviceName(r),
      subtitle: deviceMacAddress(r),
      trailing: deviceSignal(r),
    );
  }

  /* UI */
  @override
  Widget build(BuildContext context) {
    // Filtra solo los dispositivos con nombre
    final filteredList = scanResultList.where((r) {
      final name = r.advertisementData.localName.isNotEmpty
          ? r.advertisementData.localName
          : r.device.name;
      return name.isNotEmpty;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: ListView.separated(
          itemCount: filteredList.length,
          itemBuilder: (context, index) {
            return listItem(filteredList[index]);
          },
          separatorBuilder: (BuildContext context, int index) {
            return const Divider();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: toggleState,
        child: Icon(isScanning ? Icons.stop : Icons.search),
      ),
    );
  }
}
