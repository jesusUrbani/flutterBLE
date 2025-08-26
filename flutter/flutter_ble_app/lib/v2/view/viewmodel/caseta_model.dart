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

  // UUIDs
  final String serviceUUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String characteristicUUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  // Variables para los datos a enviar por BLE
  final String idDispositivo = "ESP32-URBANI";
  final String nombreEntrada = "Entrada Principal";

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
    lastBeaconRssi.clear();
    lastRssiChange.clear();

    // Si estábamos conectados, desconectamos para revalidar beacons primero
    if (dispositivoBLE != null) {
      detenerConexionBLE();
    }

    estadoBLE = "Revalidando beacons después de pago...";
    notifyStateChanged();
  }

  void _startBeaconMonitoring() {
    _beaconCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();

      // Limpiar beacons antiguos (no vistos en 60 segundos)
      beaconLastSeen.removeWhere((name, lastSeen) {
        return now.difference(lastSeen).inSeconds > 60;
      });

      // Filtrar beacons activos
      beaconsDelim = beaconsDelim.where((result) {
        final name = result.advertisementData.localName.isNotEmpty
            ? result.advertisementData.localName
            : result.device.name;
        return beaconLastSeen.containsKey(name);
      }).toList();

      // Si teníamos conexión pero perdimos los beacons, desconectar
      if (dispositivoBLE != null && beaconsDelim.length < 2) {
        estadoBLE = "Perdiendo beacons, desconectando...";
        notifyStateChanged();
        detenerConexionBLE();
      }

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

    // Iniciar escaneo continuo (sin timeout)
    FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode.lowLatency,
      oneByOne: false,
      // Sin timeout para escaneo continuo
    );
    isScanning = true;

    // Cancelar si había una suscripción previa
    scanSubscription?.cancel();

    scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
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

        // Lógica: Conectar automáticamente cuando hay suficientes beacons (2 o más)
        if (beaconsDelim.length >= 2 &&
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
      },
      onError: (error) {
        estadoBLE = "Error en escaneo: ${error.toString()}";
        notifyStateChanged();
        // En caso de error, intentar reiniciar el escaneo después de un breve delay
        Future.delayed(Duration(seconds: 2), () {
          if (_bluetoothOn && !isScanning) {
            _startContinuousScan();
          }
        });
      },
    );
  }

  // función para la conexión automática
  Future<void> _conectarAutomaticamente() async {
    // Verificar que todavía hay al menos 2 beacons antes de conectar
    if (beaconsDelim.length < 2) {
      estadoBLE =
          "Beacons insuficientes para conectar (${beaconsDelim.length})";
      isConnecting = false;
      notifyStateChanged();
      return;
    }

    if (isConnecting || dispositivoBLE != null) {
      return; // ya estoy conectado o intentando conectar
    }

    isConnecting = true;
    estadoBLE = "Conectando a BLE_URBANI...";
    notifyStateChanged();

    try {
      // Buscar dispositivo BLE_URBANI en los resultados actuales del escaneo
      final List<ScanResult> currentResults =
          await FlutterBluePlus.scanResults.first;

      final dispositivos = currentResults.where((device) {
        final name = device.advertisementData.localName.isNotEmpty
            ? device.advertisementData.localName
            : device.device.name;
        return name == "BLE_URBANI";
      }).toList();

      if (dispositivos.isEmpty) {
        estadoBLE = "BLE_URBANI no encontrado";
        isConnecting = false;
        notifyStateChanged();
        return;
      }

      final targetDevice = dispositivos.first;

      estadoBLE = "Conectando a BLE_URBANI...";
      notifyStateChanged();

      // Conectar con timeout
      final connectionCompleter = Completer<bool>();
      final connectionTimer = Timer(Duration(seconds: 10), () {
        if (!connectionCompleter.isCompleted) {
          connectionCompleter.complete(false);
        }
      });

      final connectionSubscription = targetDevice.device.connectionState.listen(
        (state) {
          if (state == BluetoothConnectionState.connected &&
              !connectionCompleter.isCompleted) {
            connectionCompleter.complete(true);
          }
        },
      );

      await targetDevice.device.connect(autoConnect: false);

      final connected = await connectionCompleter.future;
      connectionTimer.cancel();
      connectionSubscription.cancel();

      if (!connected) {
        throw TimeoutException("Timeout de conexión a BLE_URBANI");
      }

      targetDevice.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          estadoBLE = "🔌 Desconectado, validando beacons...";
          dispositivoBLE = null;
          isConnecting = false;

          notifyStateChanged();

          // Esperar y validar beacons antes de reconectar
          Future.delayed(Duration(seconds: 3), () {
            if (_bluetoothOn &&
                dispositivoBLE == null &&
                beaconsDelim.length >= 2) {
              _conectarAutomaticamente();
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
      estadoBLE = "✅ Conectado automáticamente a BLE_URBANI";
      estadoConexion = 'Conectado (${beaconsDelim.length} beacons)';
      colorEstado = Colors.green;
      notifyStateChanged();
    } catch (e) {
      estadoBLE = "❌ Error en conexión automática: ${e.toString()}";
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

    // Actualizar estado
    estadoBLE = "Desconectado de BLE_URBANI";
    estadoConexion = 'Fuera de línea después de desconectar';
    colorEstado = Colors.orange;

    // Notificar cambios
    notifyStateChanged();

    // No reiniciamos el escaneo, se mantiene activo continuamente
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
