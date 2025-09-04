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

  Map<String, int> beaconRssiValues =
      {}; // Almacena el RSSI más reciente de cada beacon
  Map<String, DateTime> lastRssiUpdate = {};

  // Mapeo de beacons a BLEs
  final Map<String, String> beaconToBle = {
    "Delim_A": "BLE_A",
    "Delim_B": "BLE_B",
    "Delim_C": "BLE_C",
  };

  // Beacon principal detectado (el más cercano al momento de conexión)
  String? beaconPrincipal;
  String? bleObjetivo;

  Function(void)? onStateChanged;

  // Parámetros para determinar el beacon más cercano
  final int rssiThreshold = -90; // Umbral mínimo de RSSI
  final int rssiHysteresis = 5; // Histéresis para evitar cambios bruscos
  int? lastBestRssi; // Mejor RSSI de la última detección

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

  // Método para obtener el beacon más cercano basado en RSSI
  String? _getNearestBeacon() {
    if (beaconRssiValues.isEmpty) return null;

    // Filtrar beacons con RSSI válido y por encima del umbral
    final validBeacons = beaconRssiValues.entries
        .where(
          (entry) =>
              entry.value >= rssiThreshold &&
              beaconToBle.containsKey(entry.key),
        )
        .toList();

    if (validBeacons.isEmpty) return null;

    // Ordenar por RSSI (mayor RSSI = más cercano)
    validBeacons.sort((a, b) => b.value.compareTo(a.value));

    final bestBeacon = validBeacons.first.key;
    final bestRssi = validBeacons.first.value;

    // Aplicar histéresis para evitar cambios bruscos
    if (lastBestRssi != null && beaconPrincipal == bestBeacon) {
      // Si el RSSI actual es significativamente peor que el anterior, mantener el beacon actual
      if (bestRssi < lastBestRssi! - rssiHysteresis) {
        return beaconPrincipal; // Mantener el beacon actual
      }
    }

    lastBestRssi = bestRssi;
    return bestBeacon;
  }

  // Método para realizar un pago
  Future<void> realizarPago(double monto) async {
    if (saldo >= monto) {
      saldo -= monto;
      mensajesBLE.add('Pago realizado: \$${monto.toStringAsFixed(2)}');
      mensajesBLE.add('Saldo restante: \$${saldo.toStringAsFixed(2)}');
      notifyStateChanged();
      // Enviar datos por BLE después del pago
      await _enviarDatosPorBLE();

      // Solo desconectamos después del pago pero mantenemos el escaneo
      _reiniciarValidacionBeacons();
    } else {
      mensajesBLE.add(
        'Saldo insuficiente para pagar \$${monto.toStringAsFixed(2)}',
      );
      notifyStateChanged();
    }
  }

  // Método para enviar datos por BLE
  Future<void> _enviarDatosPorBLE() async {
    if (dispositivoBLE == null) {
      mensajesBLE.add('No hay conexión BLE para enviar datos');
      notifyStateChanged();
      return;
    }

    try {
      // Formato: "id_dispositivo;nombre_entrada"
      final datos = '$idDispositivo;$nombreEntrada';
      final bytes = datos.codeUnits;

      // Buscar la característica para escribir
      final servicios = await dispositivoBLE!.discoverServices();
      final servicio = servicios.firstWhere(
        (s) => s.uuid == Guid(serviceUUID),
        orElse: () => throw Exception("Servicio no encontrado"),
      );

      final caracteristica = servicio.characteristics.firstWhere(
        (c) => c.uuid == Guid(characteristicUUID),
        orElse: () => throw Exception("Característica no encontrada"),
      );

      // Escribir en la característica BLE
      await caracteristica.write(bytes, withoutResponse: false);

      mensajesBLE.add('Datos enviados por BLE: $datos');
      notifyStateChanged();

      // Opcional: Esperar un breve momento para asegurar que el envío se complete
      await Future.delayed(Duration(milliseconds: 500));
    } catch (e) {
      mensajesBLE.add('Error al enviar datos por BLE: ${e.toString()}');
      notifyStateChanged();
    }
  }

  void _reiniciarValidacionBeacons() {
    // Limpiamos el estado de beacons para forzar revalidación
    beaconsDelim.clear();
    beaconLastSeen.clear();
    beaconRssiValues.clear();
    lastRssiUpdate.clear();
    beaconPrincipal = null;
    bleObjetivo = null;
    lastBestRssi = null;

    // Si estábamos conectados, desconectamos para revalidar beacons primero
    if (dispositivoBLE != null) {
      detenerConexionBLE();
    }

    estadoBLE = "Revalidando beacons después de pago...";
    notifyStateChanged();
  }

  void _startBeaconMonitoring() {
    _beaconCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final now = DateTime.now();

      // Limpiar beacons antiguos (no vistos en los últimos 10 segundos)
      beaconLastSeen.removeWhere((name, lastSeen) {
        final diff = now.difference(lastSeen).inSeconds;
        if (diff > 10) {
          beaconRssiValues.remove(name);
          // Solo actualizar el beacon principal si no estamos conectados a un BLE
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

      // ⚠️ IMPORTANTE: Solo determinar el beacon más cercano si NO estamos conectados a un BLE
      if (dispositivoBLE == null) {
        final nearestBeacon = _getNearestBeacon();

        if (nearestBeacon != null && nearestBeacon != beaconPrincipal) {
          beaconPrincipal = nearestBeacon;
          bleObjetivo = beaconToBle[nearestBeacon];
          final rssi = beaconRssiValues[nearestBeacon];
          estadoBLE = "Beacon más cercano: $nearestBeacon (RSSI: $rssi dBm)";
          notifyStateChanged();

          // Intentar conectar automáticamente al nuevo beacon más cercano
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

    // Solo procesar beacons Delim
    if (!name.startsWith('Delim')) return;

    final rssi = result.rssi;
    final now = DateTime.now();

    // Actualizar información del beacon
    beaconRssiValues[name] = rssi;
    beaconLastSeen[name] = now;
    lastRssiUpdate[name] = now;

    // Agregar a la lista de beacons detectados
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
        // Cuando el Bluetooth se enciende, iniciar el escaneo continuo
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
    // Si ya estamos escaneando, no hacer nada
    if (isScanning) return;

    // Detener cualquier escaneo previo
    FlutterBluePlus.stopScan();

    // Iniciar escaneo continuo
    FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode.lowLatency,
      oneByOne: false,
    );
    isScanning = true;

    // Cancelar si había una suscripción previa
    scanSubscription?.cancel();

    scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        final now = DateTime.now();

        // Filtrar solo beacons Delim con RSSI válido
        final detectedBeacons = results.where((result) {
          final name = result.advertisementData.localName.isNotEmpty
              ? result.advertisementData.localName
              : result.device.name;

          return name.startsWith('Delim') &&
              result.rssi >= -100 &&
              result.rssi <= -1;
        }).toList();

        // Procesar cada beacon detectado
        for (var beacon in detectedBeacons) {
          _onBeaconDetected(beacon);
        }

        // Actualizar estado de conexión
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
        // Reiniciar el escaneo después de un error
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
    // ⚠️ NO conectar si ya estamos conectados a un BLE
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
      // Buscar dispositivo BLE objetivo
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

      // Conectar con timeout
      await targetDevice
          .connect(autoConnect: false)
          .timeout(Duration(seconds: 10));

      // Configurar listener para desconexiones
      targetDevice.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          estadoBLE = "Desconectado de $bleObjetivo";
          dispositivoBLE = null;
          isConnecting = false;

          // ⚠️ IMPORTANTE: Al desconectarse, volver a evaluar el beacon más cercano
          beaconPrincipal = null;
          bleObjetivo = null;
          lastBestRssi = null;

          notifyStateChanged();
        }
      });

      // Descubrir servicios y características
      final servicios = await targetDevice.discoverServices();
      final servicio = servicios.firstWhere(
        (s) => s.uuid == Guid(serviceUUID),
        orElse: () => throw Exception("Servicio no encontrado"),
      );

      final caracteristica = servicio.characteristics.firstWhere(
        (c) => c.uuid == Guid(characteristicUUID),
        orElse: () => throw Exception("Característica no encontrada"),
      );

      // Configurar notificaciones
      await caracteristica.setNotifyValue(true);
      mensajesSubscription = caracteristica.onValueReceived.listen((value) {
        final mensaje = String.fromCharCodes(value);
        mensajesBLE.add(mensaje);
        if (mensajesBLE.length > 10) mensajesBLE.removeAt(0);
        notifyStateChanged();
      });

      dispositivoBLE = targetDevice;
      estadoBLE = "✅ Conectado a $bleObjetivo";
      estadoConexion = 'Conectado a $bleObjetivo';
      colorEstado = Colors.green;
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

    // ⚠️ IMPORTANTE: Al desconectar, limpiar el beacon principal para re-evaluar
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
