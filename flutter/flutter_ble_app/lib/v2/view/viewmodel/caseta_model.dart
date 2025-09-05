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
  double saldo = 100.0;
  Function(void)? onDisconnected;

  // UUIDs
  final String serviceUUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String characteristicUUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  // Variables para los datos a enviar por BLE
  final String idDispositivo = "ESP32-URBANI";
  final String nombreEntrada = "Entrada Principal";

  // Variables para el nuevo flujo
  double? tarifaCalculada;
  bool procesandoPeticion = false;
  String? errorMensaje;

  Map<String, int> beaconRssiValues = {};
  Map<String, DateTime> lastRssiUpdate = {};

  // Mapeo de beacons a BLEs
  final Map<String, String> beaconToBle = {
    "Delim_A": "BLE_A",
    "Delim_B": "BLE_B",
    "Delim_C": "BLE_C",
  };

  // Beacon principal detectado
  String? beaconPrincipal;
  String? bleObjetivo;

  Function(void)? onStateChanged;

  // Parámetros para determinar el beacon más cercano
  final int rssiThreshold = -90;
  final int rssiHysteresis = 5;
  int? lastBestRssi;

  CasetaViewModel({this.onStateChanged, this.onDisconnected});

  Timer? _reconexionTimer;
  bool _reconexionPendiente = false;

  void notifyStateChanged() {
    onStateChanged?.call(null);
  }

  Future<void> init() async {
    await _checkPermissionsAndBluetooth();
    _startBeaconMonitoring();
  }

  String? _getNearestBeacon() {
    if (beaconRssiValues.isEmpty) return null;

    final validBeacons = beaconRssiValues.entries
        .where(
          (entry) =>
              entry.value >= rssiThreshold &&
              beaconToBle.containsKey(entry.key),
        )
        .toList();

    if (validBeacons.isEmpty) return null;

    validBeacons.sort((a, b) => b.value.compareTo(a.value));

    final bestBeacon = validBeacons.first.key;
    final bestRssi = validBeacons.first.value;

    if (lastBestRssi != null && beaconPrincipal == bestBeacon) {
      if (bestRssi < lastBestRssi! - rssiHysteresis) {
        return beaconPrincipal;
      }
    }

    lastBestRssi = bestRssi;
    return bestBeacon;
  }

  Future<void> realizarPago(double monto) async {
    if (saldo >= monto) {
      saldo -= monto;
      mensajesBLE.add('Pago realizado: \$${monto.toStringAsFixed(2)}');
      mensajesBLE.add('Saldo restante: \$${saldo.toStringAsFixed(2)}');
      notifyStateChanged();
      await _enviarDatosPorBLE();
      _reiniciarValidacionBeacons();
    } else {
      mensajesBLE.add(
        'Saldo insuficiente para pagar \$${monto.toStringAsFixed(2)}',
      );
      notifyStateChanged();
    }
  }

  Future<void> _enviarDatosPorBLE() async {
    if (dispositivoBLE == null) {
      mensajesBLE.add('No hay conexión BLE para enviar datos');
      notifyStateChanged();
      return;
    }

    procesandoPeticion = true;
    errorMensaje = null;
    notifyStateChanged();

    try {
      // 📤 NUEVO FORMATO: "id_usuario;vehicle_type"
      final datos = 'USER_123;CARRO'; // Datos fijos como especificaste
      final bytes = datos.codeUnits;

      final servicios = await dispositivoBLE!.discoverServices();
      final servicio = servicios.firstWhere(
        (s) => s.uuid == Guid(serviceUUID),
        orElse: () => throw Exception("Servicio no encontrado"),
      );

      final caracteristica = servicio.characteristics.firstWhere(
        (c) => c.uuid == Guid(characteristicUUID),
        orElse: () => throw Exception("Característica no encontrada"),
      );

      await caracteristica.write(bytes, withoutResponse: false);
      mensajesBLE.add('Datos enviados por BLE: $datos');
      mensajesBLE.add('Esperando respuesta del ESP32...');
    } catch (e) {
      errorMensaje = 'Error al enviar datos por BLE: ${e.toString()}';
      mensajesBLE.add(errorMensaje!);
    } finally {
      procesandoPeticion = false;
      notifyStateChanged();
    }
  }

  Future<void> _configurarNotificacionesBLE(
    BluetoothCharacteristic caracteristica,
  ) async {
    await caracteristica.setNotifyValue(true);

    mensajesSubscription?.cancel();

    mensajesSubscription = caracteristica.onValueReceived.listen((value) {
      final mensaje = String.fromCharCodes(value);
      mensajesBLE.add('Respuesta ESP32: $mensaje');

      // 🎯 PROCESAR RESPUESTAS DEL ESP32
      if (mensaje.startsWith('TARIFA:')) {
        final tarifaStr = mensaje.replaceFirst('TARIFA:', '');
        tarifaCalculada = double.tryParse(tarifaStr);
        if (tarifaCalculada != null) {
          mensajesBLE.add(
            'Tarifa calculada: \$${tarifaCalculada!.toStringAsFixed(2)}',
          );
        }
      } else if (mensaje.startsWith('SUCCESS:')) {
        mensajesBLE.add('Registro completado exitosamente');
      } else if (mensaje.startsWith('ERROR:')) {
        errorMensaje = mensaje.replaceFirst('ERROR:', '');
        mensajesBLE.add('Error: $errorMensaje');
      }

      if (mensajesBLE.length > 15) mensajesBLE.removeRange(0, 5);
      notifyStateChanged();
    });
  }

  void _reiniciarValidacionBeacons() {
    beaconsDelim.clear();
    beaconLastSeen.clear();
    beaconRssiValues.clear();
    lastRssiUpdate.clear();
    beaconPrincipal = null;
    bleObjetivo = null;
    lastBestRssi = null;

    if (dispositivoBLE != null) {
      detenerConexionBLE();
    }

    estadoBLE = "Revalidando beacons después de pago...";
    notifyStateChanged();
  }

  void _startBeaconMonitoring() {
    _beaconCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final now = DateTime.now();

      beaconLastSeen.removeWhere((name, lastSeen) {
        final diff = now.difference(lastSeen).inSeconds;
        if (diff > 10) {
          beaconRssiValues.remove(name);
          if (beaconPrincipal == name && dispositivoBLE == null) {
            beaconPrincipal = null;
            bleObjetivo = null;
            lastBestRssi = null;
            estadoBLE = "Beacon $name inactivo (no visto en $diff s)";
            notifyStateChanged();
          }
          return true;
        }
        return false;
      });

      if (dispositivoBLE == null) {
        final nearestBeacon = _getNearestBeacon();

        if (nearestBeacon != null && nearestBeacon != beaconPrincipal) {
          beaconPrincipal = nearestBeacon;
          bleObjetivo = beaconToBle[nearestBeacon];
          final rssi = beaconRssiValues[nearestBeacon];
          estadoBLE = "Beacon más cercano: $nearestBeacon (RSSI: $rssi dBm)";
          notifyStateChanged();

          if (!isConnecting && !_reconexionPendiente) {
            _reconexionPendiente = true;
            _reconexionTimer = Timer(Duration(seconds: 1), () {
              _reconexionPendiente = false;
              _conectarAutomaticamente();
            });
          }
        }
      }

      notifyStateChanged();
    });
  }

  void _onBeaconDetected(ScanResult result) {
    final name = result.advertisementData.localName.isNotEmpty
        ? result.advertisementData.localName
        : result.device.name;

    if (!name.startsWith('Delim')) return;

    final rssi = result.rssi;
    final now = DateTime.now();

    beaconRssiValues[name] = rssi;
    beaconLastSeen[name] = now;
    lastRssiUpdate[name] = now;

    if (!beaconsDelim.any(
      (beacon) =>
          (beacon.advertisementData.localName.isNotEmpty
              ? beacon.advertisementData.localName
              : beacon.device.name) ==
          name,
    )) {
      beaconsDelim.add(result);
    }
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
        beaconPrincipal = null;
        bleObjetivo = null;
        estadoBLE = "Bluetooth apagado";
      } else {
        _startContinuousScan();
        estadoBLE = "Bluetooth activado, escaneando...";
      }
      notifyStateChanged();
    });

    final state = await FlutterBluePlus.adapterState.first;
    _bluetoothOn = state == BluetoothAdapterState.on;
    notifyStateChanged();

    if (_bluetoothOn) {
      _startContinuousScan();
    }
  }

  void _startContinuousScan() {
    if (isScanning) return;

    FlutterBluePlus.stopScan();
    FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode.lowLatency,
      oneByOne: false,
    );
    isScanning = true;

    scanSubscription?.cancel();

    scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        final now = DateTime.now();

        final detectedBeacons = results.where((result) {
          final name = result.advertisementData.localName.isNotEmpty
              ? result.advertisementData.localName
              : result.device.name;

          return name.startsWith('Delim') &&
              result.rssi >= -100 &&
              result.rssi <= -1;
        }).toList();

        for (var beacon in detectedBeacons) {
          _onBeaconDetected(beacon);
        }

        if (!_bluetoothOn) {
          estadoConexion = 'Sin conexión';
          colorEstado = Colors.black;
        } else if (dispositivoBLE != null) {
          estadoConexion = 'Conectado a $bleObjetivo';
          colorEstado = Colors.green;
        } else if (beaconPrincipal != null) {
          final rssi = beaconRssiValues[beaconPrincipal];
          estadoConexion = 'Beacon más cercano: $beaconPrincipal (${rssi}dBm)';
          colorEstado = Colors.blue;
        } else if (beaconRssiValues.isNotEmpty) {
          estadoConexion = 'Beacons detectados: ${beaconRssiValues.length}';
          colorEstado = Colors.orange;
        } else {
          estadoConexion = 'Escaneando beacons...';
          colorEstado = Colors.orange;
        }

        notifyStateChanged();
      },
      onError: (error) {
        estadoBLE = "Error en escaneo: ${error.toString()}";
        notifyStateChanged();
        Future.delayed(Duration(seconds: 2), () {
          if (_bluetoothOn) {
            isScanning = false;
            _startContinuousScan();
          }
        });
      },
    );
  }

  Future<void> _conectarAutomaticamente() async {
    if (dispositivoBLE != null ||
        beaconPrincipal == null ||
        bleObjetivo == null ||
        isConnecting) {
      return;
    }

    isConnecting = true;
    estadoBLE = "Conectando a $bleObjetivo...";
    notifyStateChanged();

    try {
      final List<ScanResult> currentResults =
          await FlutterBluePlus.scanResults.first;

      final targetDevices = currentResults.where((device) {
        final name = device.advertisementData.localName.isNotEmpty
            ? device.advertisementData.localName
            : device.device.name;
        return name == bleObjetivo;
      }).toList();

      if (targetDevices.isEmpty) {
        throw Exception("Dispositivo $bleObjetivo no encontrado");
      }

      final targetDevice = targetDevices.first.device;

      await targetDevice
          .connect(autoConnect: false)
          .timeout(Duration(seconds: 10));

      targetDevice.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          estadoBLE = "Desconectado de $bleObjetivo";
          dispositivoBLE = null;
          isConnecting = false;
          beaconPrincipal = null;
          bleObjetivo = null;
          lastBestRssi = null;
          notifyStateChanged();
        }
      });

      final servicios = await targetDevice.discoverServices();
      final servicio = servicios.firstWhere(
        (s) => s.uuid == Guid(serviceUUID),
        orElse: () => throw Exception("Servicio no encontrado"),
      );

      final caracteristica = servicio.characteristics.firstWhere(
        (c) => c.uuid == Guid(characteristicUUID),
        orElse: () => throw Exception("Característica no encontrada"),
      );

      // ✅ CONFIGURAR NOTIFICACIONES PARA RECIBIR RESPUESTAS
      await _configurarNotificacionesBLE(caracteristica);

      dispositivoBLE = targetDevice;
      estadoBLE = "✅ Conectado a $bleObjetivo";
      estadoConexion = 'Conectado a $bleObjetivo';
      colorEstado = Colors.green;
      mensajesBLE.add('Conectado al ESP32. Listo para operar.');

      notifyStateChanged();
    } catch (e) {
      estadoBLE = "❌ Error conectando a $bleObjetivo: ${e.toString()}";
      isConnecting = false;
      notifyStateChanged();
    } finally {
      isConnecting = false;
    }
  }

  void detenerConexionBLE() {
    _reconexionTimer?.cancel();
    _reconexionPendiente = false;

    mensajesSubscription?.cancel();
    mensajesSubscription = null;
    caracteristicaNotificaciones = null;

    dispositivoBLE?.disconnect();
    dispositivoBLE = null;

    beaconPrincipal = null;
    bleObjetivo = null;
    lastBestRssi = null;

    estadoBLE = "Desconectado";
    estadoConexion = 'Fuera de línea';
    colorEstado = Colors.orange;

    notifyStateChanged();
    onDisconnected?.call(null);
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
