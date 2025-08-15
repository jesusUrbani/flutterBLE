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
  // Variables de estado
  String estadoConexion = 'Sin conexión';
  Color colorEstado = Colors.black;
  List<ScanResult> beaconsDelim = [];
  BluetoothDevice? dispositivoBLE;
  bool isConnecting = false;
  String estadoBLE = "";
  List<String> mensajesBLE = [];

  Map<String, DateTime> beaconLastSeen = {};

  // Variables de escaneo BLE
  bool _bluetoothOn = false;
  bool isScanning = false;
  StreamSubscription<List<ScanResult>>? scanSubscription;
  Timer? _beaconCheckTimer;

  // Variables para recepción de mensajes
  StreamSubscription<List<int>>? mensajesSubscription;
  BluetoothCharacteristic? caracteristicaNotificaciones;

  // UUIDs
  final String serviceUUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String characteristicUUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  Map<String, int> beaconMissCount = {};
  Map<String, int?> beaconLastHeartbeat = {};
  Map<String, int> currentBeaconHeartbeat = {};

  // Guardar el último RSSI y cuándo cambió
  Map<String, int> lastBeaconRssi = {};
  Map<String, DateTime> lastRssiChange = {};

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndBluetooth();
    _startBeaconMonitoring();
  }

  void _startBeaconMonitoring() {
    _beaconCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();

      beaconLastSeen.removeWhere((name, lastSeen) {
        // Eliminar si el RSSI no ha cambiado en más de 10 segundos
        final lastChange = lastRssiChange[name];
        if (lastChange != null && now.difference(lastChange).inSeconds > 20) {
          return true;
        }
        return false;
      });

      setState(() {
        beaconsDelim = beaconsDelim.where((result) {
          final name = result.advertisementData.localName.isNotEmpty
              ? result.advertisementData.localName
              : result.device.name;
          return beaconLastSeen.containsKey(name);
        }).toList();
      });
    });
  }

  void _onBeaconDetected(ScanResult result) {
    final name = result.advertisementData.localName.isNotEmpty
        ? result.advertisementData.localName
        : result.device.name;

    final rssi = result.rssi;
    final now = DateTime.now();

    // Si es la primera vez o cambió el RSSI, actualizamos hora de cambio
    if (!lastBeaconRssi.containsKey(name) || lastBeaconRssi[name] != rssi) {
      lastRssiChange[name] = now;
      lastBeaconRssi[name] = rssi;
    }

    beaconLastSeen[name] = now; // Seguimos registrando última detección
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
          _detenerConexionBLE();
          estadoConexion = 'Sin conexión';
          colorEstado = Colors.black;
          beaconsDelim.clear();
          estadoBLE = "Bluetooth apagado";
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
      final now = DateTime.now();

      final detectedNow = results.where((result) {
        final name = result.advertisementData.localName.isNotEmpty
            ? result.advertisementData.localName
            : result.device.name;

        return name.startsWith('Delim') &&
            result.rssi >= -100 &&
            result.rssi <= -1;
      }).toList();

      // Registrar última vez visto usando el nombre como clave
      /*
      for (var beacon in detectedNow) {
        final name = beacon.advertisementData.localName.isNotEmpty
            ? beacon.advertisementData.localName
            : beacon.device.name;
        beaconLastSeen[name] = now;
      }*/
      for (var beacon in detectedNow) {
        _onBeaconDetected(beacon);
      }

      // Construir lista solo con los que llevan menos de 5 segundos sin verse
      final activeBeacons = results.where((result) {
        final name = result.advertisementData.localName.isNotEmpty
            ? result.advertisementData.localName
            : result.device.name;
        final lastSeen = beaconLastSeen[name];
        return lastSeen != null && now.difference(lastSeen).inSeconds < 5;
      }).toList();

      setState(() {
        beaconsDelim = activeBeacons;

        if (!_bluetoothOn) {
          estadoConexion = 'Sin conexión';
          colorEstado = Colors.black;
        } else if (dispositivoBLE != null) {
          estadoConexion = 'Conectado a BLE_URBANI';
          colorEstado = Colors.green;
        } else if (beaconsDelim.isNotEmpty) {
          estadoConexion = 'Beacons activos: ${beaconsDelim.length}';
          colorEstado = Colors.blue;
        } else {
          estadoConexion = 'Fuera de línea';
          colorEstado = Colors.orange;
        }
      });
    });
  }

  Future<void> _conectarABleUrbani() async {
    if (isConnecting || dispositivoBLE != null || beaconsDelim.length < 2)
      return;

    setState(() {
      isConnecting = true;
      estadoBLE = "Buscando BLE_URBANI...";
    });

    try {
      await FlutterBluePlus.stopScan();
      isScanning = false;

      final dispositivos = await Future.any([
        FlutterBluePlus.scanResults.firstWhere(
          (results) => results.any((device) {
            final name = device.advertisementData.localName.isNotEmpty
                ? device.advertisementData.localName
                : device.device.name;
            return name == "BLE_URBANI";
          }),
        ),
        Future.delayed(
          Duration(seconds: 5),
        ).then((_) => throw TimeoutException("Tiempo agotado")),
      ]);

      final targetDevice = dispositivos.firstWhere(
        (d) =>
            (d.advertisementData.localName == "BLE_URBANI" ||
            d.device.name == "BLE_URBANI"),
      );

      setState(() {
        estadoBLE = "Conectando a BLE_URBANI...";
      });

      await targetDevice.device.connect(autoConnect: false);

      final servicios = await targetDevice.device.discoverServices();
      final servicio = servicios.firstWhere(
        (s) => s.uuid == Guid(serviceUUID),
        orElse: () => throw Exception("Servicio no encontrado"),
      );

      final caracteristica = servicio.characteristics.firstWhere(
        (c) => c.uuid == Guid(characteristicUUID),
        orElse: () => throw Exception("Característica no encontrada"),
      );

      await caracteristica.setNotifyValue(true);
      mensajesSubscription = caracteristica.onValueReceived.listen((value) {
        final mensaje = String.fromCharCodes(value);
        setState(() {
          mensajesBLE.add(mensaje);
          if (mensajesBLE.length > 10) mensajesBLE.removeAt(0);
        });
      });

      setState(() {
        dispositivoBLE = targetDevice.device;
        estadoBLE = "✅ Conectado a BLE_URBANI";
        estadoConexion = 'Conectado (${beaconsDelim.length} beacons)';
        colorEstado = Colors.green;
      });
    } on TimeoutException catch (_) {
      setState(() {
        estadoBLE = "❌ BLE_URBANI no encontrado";
      });
    } catch (e) {
      setState(() {
        estadoBLE = "❌ Error: ${e.toString()}";
      });
    } finally {
      _startScan();
      setState(() {
        isConnecting = false;
      });
    }
  }

  void _detenerConexionBLE() {
    dispositivoBLE?.disconnect();
    dispositivoBLE = null;

    // Limpiar listas de beacons
    beaconsDelim.clear();
    beaconLastSeen.clear();
    beaconMissCount.clear();
    lastBeaconRssi.clear();
    lastRssiChange.clear();

    // Actualizar estado
    setState(() {
      estadoBLE = "Desconectado";
      estadoConexion = 'Fuera de línea';
      colorEstado = Colors.orange;
    });

    // Reiniciar búsqueda de beacons
    _startScan();
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

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: _getSignalColor(rssi),
            child: Icon(Icons.bluetooth, color: Colors.white),
          ),
          title: Text(name),
          subtitle: Text('${beacon.device.id.id} (${rssi} dBm)'),
        );
      },
    );
  }

  Widget _buildMensajesBLE() {
    if (mensajesBLE.isEmpty) {
      return Center(
        child: Text(
          'No hay mensajes recibidos',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: mensajesBLE.length,
      itemBuilder: (context, index) {
        return ListTile(
          leading: Icon(Icons.message, color: Colors.blue),
          title: Text(mensajesBLE[index]),
        );
      },
    );
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.blue;
    if (rssi >= -85) return Colors.orange;
    return Colors.red;
  }

  @override
  void dispose() {
    _beaconCheckTimer?.cancel();
    _detenerConexionBLE();
    scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              estadoConexion,
              style: TextStyle(
                fontSize: 24,
                color: colorEstado,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              estadoBLE,
              style: TextStyle(fontSize: 18, color: Colors.purple),
            ),
            SizedBox(height: 20),
            // Botón de conexión (solo visible cuando hay ≥2 beacons y no está conectado)
            if (beaconsDelim.length >= 2 && dispositivoBLE == null)
              ElevatedButton(
                onPressed: _conectarABleUrbani,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                child: Text(
                  'Conectar a BLE_URBANI',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            SizedBox(height: 10),
            // Botón de desconexión (solo visible cuando está conectado)
            if (dispositivoBLE != null)
              ElevatedButton(
                onPressed: _detenerConexionBLE,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                child: Text('Desconectar', style: TextStyle(fontSize: 18)),
              ),
            SizedBox(height: 20),
            if (dispositivoBLE != null) ...[
              Text(
                'Mensajes BLE:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Expanded(child: _buildMensajesBLE()),
            ],
            Text(
              'Beacons detectados:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Expanded(child: _buildBeaconList()),
          ],
        ),
      ),
    );
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}
