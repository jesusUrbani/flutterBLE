import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class CasetaViewModel {
  // Variables de estado
  String estadoConexion = 'Sin conexión';
  Color colorEstado = Colors.black;
  List<ScanResult> beaconsDelim = [];
  BluetoothDevice? dispositivoBLE;
  bool isConnecting = false;
  String estadoBLE = "";
  List<String> mensajesBLE = [];

  Map<String, DateTime> beaconLastSeen = {};
  bool _bluetoothOn = false;
  bool isScanning = false;
  StreamSubscription<List<ScanResult>>? scanSubscription;
  Timer? _beaconCheckTimer;
  StreamSubscription<List<int>>? mensajesSubscription;
  BluetoothCharacteristic? caracteristicaNotificaciones;

  // UUIDs
  final String serviceUUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String characteristicUUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  Map<String, int> lastBeaconRssi = {};
  Map<String, DateTime> lastRssiChange = {};

  Function(void)? onStateChanged;

  CasetaViewModel({this.onStateChanged});

  void notifyStateChanged() {
    onStateChanged?.call(null);
  }

  Future<void> init() async {
    await _checkPermissionsAndBluetooth();
    _startBeaconMonitoring();
  }

  void _startBeaconMonitoring() {
    _beaconCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();

      beaconLastSeen.removeWhere((name, lastSeen) {
        final lastChange = lastRssiChange[name];
        if (lastChange != null && now.difference(lastChange).inSeconds > 20) {
          return true;
        }
        return false;
      });

      beaconsDelim = beaconsDelim.where((result) {
        final name = result.advertisementData.localName.isNotEmpty
            ? result.advertisementData.localName
            : result.device.name;
        return beaconLastSeen.containsKey(name);
      }).toList();

      notifyStateChanged();
    });
  }

  void _onBeaconDetected(ScanResult result) {
    final name = result.advertisementData.localName.isNotEmpty
        ? result.advertisementData.localName
        : result.device.name;

    final rssi = result.rssi;
    final now = DateTime.now();

    if (!lastBeaconRssi.containsKey(name)) {
      lastRssiChange[name] = now;
    } else if (lastBeaconRssi[name] != rssi) {
      lastRssiChange[name] = now;
    }
    lastBeaconRssi[name] = rssi;
    beaconLastSeen[name] = now;
  }

  Future<void> _checkPermissionsAndBluetooth() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    FlutterBluePlus.adapterState.listen((state) {
      _bluetoothOn = state == BluetoothAdapterState.on;
      if (!_bluetoothOn) {
        detenerConexionBLE();
        estadoConexion = 'Sin conexión';
        colorEstado = Colors.black;
        beaconsDelim.clear();
        estadoBLE = "Bluetooth apagado";
      }
      notifyStateChanged();

      if (_bluetoothOn && !isScanning) {
        _startScan();
      }
    });

    final state = await FlutterBluePlus.adapterState.first;
    _bluetoothOn = state == BluetoothAdapterState.on;
    notifyStateChanged();

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

      for (var beacon in detectedNow) {
        _onBeaconDetected(beacon);
      }

      final activeBeacons = results.where((result) {
        final name = result.advertisementData.localName.isNotEmpty
            ? result.advertisementData.localName
            : result.device.name;
        final lastSeen = beaconLastSeen[name];
        return lastSeen != null && now.difference(lastSeen).inSeconds < 5;
      }).toList();

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

      notifyStateChanged();
    });
  }

  Future<void> conectarABleUrbani() async {
    if (isConnecting || dispositivoBLE != null || beaconsDelim.length < 2)
      return;

    isConnecting = true;
    estadoBLE = "Buscando BLE_URBANI...";
    notifyStateChanged();

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
          const Duration(seconds: 5),
        ).then((_) => throw TimeoutException("Tiempo agotado")),
      ]);

      final targetDevice = dispositivos.firstWhere(
        (d) =>
            (d.advertisementData.localName == "BLE_URBANI" ||
            d.device.name == "BLE_URBANI"),
      );

      estadoBLE = "Conectando a BLE_URBANI...";
      notifyStateChanged();

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
        mensajesBLE.add(mensaje);
        if (mensajesBLE.length > 10) mensajesBLE.removeAt(0);
        notifyStateChanged();
      });

      dispositivoBLE = targetDevice.device;
      estadoBLE = "✅ Conectado a BLE_URBANI";
      estadoConexion = 'Conectado (${beaconsDelim.length} beacons)';
      colorEstado = Colors.green;
      notifyStateChanged();
    } on TimeoutException catch (_) {
      estadoBLE = "❌ BLE_URBANI no encontrado";
      notifyStateChanged();
    } catch (e) {
      estadoBLE = "❌ Error: ${e.toString()}";
      notifyStateChanged();
    } finally {
      _startScan();
      isConnecting = false;
      notifyStateChanged();
    }
  }

  void detenerConexionBLE() {
    dispositivoBLE?.disconnect();
    dispositivoBLE = null;
    beaconsDelim.clear();
    beaconLastSeen.clear();
    lastBeaconRssi.clear();
    lastRssiChange.clear();

    estadoBLE = "Desconectado";
    estadoConexion = 'Fuera de línea';
    colorEstado = Colors.orange;
    notifyStateChanged();

    _startScan();
  }

  Color getSignalColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.blue;
    if (rssi >= -85) return Colors.orange;
    return Colors.red;
  }

  void dispose() {
    _beaconCheckTimer?.cancel();
    detenerConexionBLE();
    scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    mensajesSubscription?.cancel();
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}
