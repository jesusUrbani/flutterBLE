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

  Timer? _reconexionTimer;
  bool _reconexionPendiente = false;

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
      } else {
        // Cuando el Bluetooth se enciende, reiniciar el escaneo
        _reiniciarEscaneo();
        estadoBLE = "Bluetooth activado, escaneando...";
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
    // Limpiar listas y mapas de beacons para forzar un nuevo escaneo fresco

    beaconsDelim.clear();
    beaconLastSeen.clear();
    lastBeaconRssi.clear();
    lastRssiChange.clear();
    mensajesBLE.clear();

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

      // lógica: Conectar automáticamente cuando hay suficientes beacons (2 o más)
      if (beaconsDelim.length >= 2 && // Cambiado de >= 1 a >= 2
          dispositivoBLE == null &&
          !isConnecting &&
          !_reconexionPendiente &&
          _bluetoothOn) {
        _reconexionPendiente = true;
        estadoBLE = "Múltiples beacons detectados, conectando...";
        notifyStateChanged();

        _reconexionTimer = Timer(Duration(seconds: 2), () {
          _reconexionPendiente = false;
          _conectarAutomaticamente();
        });
      }

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

  // función para la conexión automática
  Future<void> _conectarAutomaticamente() async {
    // Verificar que todavía hay al menos 2 beacons antes de conectar
    if (beaconsDelim.length < 2) {
      estadoBLE =
          "Beacons insuficientes para conectar (${beaconsDelim.length})";
      isConnecting = false;
      _reiniciarEscaneo();
      notifyStateChanged();
      return;
    }

    if (isConnecting || dispositivoBLE != null) return;

    isConnecting = true;
    estadoBLE = "Conectando a BLE_URBANI...";
    notifyStateChanged();

    try {
      await FlutterBluePlus.stopScan();
      isScanning = false;

      // Buscar dispositivo BLE_URBANI
      final dispositivos = await FlutterBluePlus.scanResults.firstWhere(
        (results) => results.any((device) {
          final name = device.advertisementData.localName.isNotEmpty
              ? device.advertisementData.localName
              : device.device.name;
          return name == "BLE_URBANI";
        }),
        orElse: () => [],
      );

      if (dispositivos.isEmpty) {
        estadoBLE = "BLE_URBANI no encontrado";
        _reiniciarEscaneo();
        isConnecting = false;
        notifyStateChanged();
        return;
      }

      final targetDevice = dispositivos.firstWhere(
        (d) =>
            (d.advertisementData.localName == "BLE_URBANI" ||
            d.device.name == "BLE_URBANI"),
      );

      estadoBLE = "Conectando a BLE_URBANI...";
      notifyStateChanged();

      await targetDevice.device.connect(autoConnect: false);

      targetDevice.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          estadoBLE = "🔌 Desconectado, reintentando...";
          dispositivoBLE = null;
          isConnecting = false;

          notifyStateChanged();

          // Reiniciar escaneo
          _reiniciarEscaneo();

          // Esperar unos segundos y validar beacons antes de reconectar
          Future.delayed(Duration(seconds: 3), () {
            if (_bluetoothOn &&
                dispositivoBLE == null &&
                beaconsDelim.length >= 2) {
              // Validar que hay al menos 2 beacons
              _conectarAutomaticamente();
            } /*else {
              estadoBLE = "⚠️ Esperando suficientes beacons para reconectar...";

              notifyStateChanged();
              // Reiniciar el escaneo después de 5 segundos
              Future.delayed(Duration(seconds: 5), () {
                if (_bluetoothOn &&
                    dispositivoBLE == null &&
                    beaconsDelim.length < 2) {
                  estadoBLE = "Reiniciando escaneo...123";
                  notifyStateChanged();
                  _reiniciarEscaneo();
                }
              });
            }*/
          });
        }
      });

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
      estadoBLE = "✅ Conectado automáticamente a BLE_URBANI";
      estadoConexion = 'Conectado (${beaconsDelim.length} beacons)';
      colorEstado = Colors.green;
      notifyStateChanged();
    } catch (e) {
      estadoBLE = "❌ Error en conexión automática: ${e.toString()}";
      _reiniciarEscaneo();
      isConnecting = false;
      notifyStateChanged();
    }
  }

  Future<void> conectarABleUrbani() async {
    // Verificar que hay al menos 2 beacons
    if (beaconsDelim.length < 2) {
      estadoBLE = "Se necesitan al menos 2 beacons para conectar";
      notifyStateChanged();
      return;
    }

    if (isConnecting || dispositivoBLE != null) return;

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

      targetDevice.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          estadoBLE = "🔌 Desconectado, reintentando...";
          dispositivoBLE = null;
          isConnecting = false;

          notifyStateChanged();

          // Reiniciar escaneo
          _reiniciarEscaneo();

          // Esperar unos segundos y validar beacons antes de reconectar
          Future.delayed(Duration(seconds: 3), () {
            if (_bluetoothOn &&
                dispositivoBLE == null &&
                beaconsDelim.length >= 2) {
              // Validar que hay al menos 2 beacons
              _conectarAutomaticamente();
            } else {
              estadoBLE = "⚠️ Esperando suficientes beacons para reconectar...";
              notifyStateChanged();
              // Reiniciar el escaneo después de 10 segundos
              Future.delayed(Duration(seconds: 10), () {
                if (_bluetoothOn &&
                    dispositivoBLE == null &&
                    beaconsDelim.length < 2) {
                  estadoBLE = "Reiniciando escaneo...";
                  notifyStateChanged();
                  _reiniciarEscaneo();
                }
              });
            }
          });
        }
      });

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
    // Cancelar cualquier reconexión pendiente
    _reconexionTimer?.cancel();
    _reconexionPendiente = false;

    // Cancelar la suscripción a mensajes BLE
    mensajesSubscription?.cancel();
    mensajesSubscription = null;
    caracteristicaNotificaciones = null;

    // Desconectar el dispositivo
    dispositivoBLE?.disconnect();
    dispositivoBLE = null;

    // Limpiar listas y mapas
    beaconsDelim.clear();
    beaconLastSeen.clear();
    lastBeaconRssi.clear();
    lastRssiChange.clear();
    mensajesBLE.clear();

    // Actualizar estado
    estadoBLE = "Desconectado de BLE_URBANI";
    estadoConexion = 'Fuera de línea después de desconectar';
    colorEstado = Colors.orange;

    // Notificar cambios
    notifyStateChanged();

    // Reiniciar el escaneo con un pequeño delay para asegurar la desconexión
    Future.delayed(Duration(milliseconds: 500), () {
      _reiniciarEscaneo();
    });
  }

  // Añade este método para reiniciar el escaneo
  void _reiniciarEscaneo() {
    // Detener el escaneo actual si está activo
    if (isScanning) {
      FlutterBluePlus.stopScan();
      scanSubscription?.cancel();
      isScanning = false;
    }

    // Reiniciar el escaneo
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
    _reconexionTimer?.cancel();
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
