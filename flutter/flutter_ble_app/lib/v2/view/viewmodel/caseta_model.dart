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

  Map<String, int> lastBeaconRssi = {};
  Map<String, DateTime> lastRssiChange = {};

  // Mapeo de beacons a BLEs
  final Map<String, String> beaconToBle = {
    "Delim_A": "BLE_A",
    "Delim_B": "BLE_B",
    "Delim_C": "BLE_C",
  };

  // Beacon principal detectado (el primero que se detecte)
  String? beaconPrincipal;
  String? bleObjetivo;

  Function(void)? onStateChanged;

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
    beaconPrincipal = null;
    bleObjetivo = null;

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

      beaconLastSeen.removeWhere((name, lastSeen) {
        final diff = now.difference(lastSeen).inSeconds;
        if (diff > 5) {
          // ⚠️ más de 5s sin señal
          if (beaconPrincipal == name) {
            beaconPrincipal = null;
            bleObjetivo = null;
            estadoBLE = "Beacon $name inactivo (no visto en $diff s)";
            notifyStateChanged();
          }
          return true;
        }
        return false;
      });

      notifyStateChanged();
    });
  }

  void _onBeaconDetected(ScanResult result) {
    final name = result.advertisementData.localName.isNotEmpty
        ? result.advertisementData.localName
        : result.device.name;

    final rssi = result.rssi;
    final now = DateTime.now();

    // Guardar última señal
    lastBeaconRssi[name] = rssi;
    beaconLastSeen[name] = now;

    // Histeresis de estado: activo/inactivo
    if (rssi > -90) {
      // Señal fuerte, marcar como activo
      if (beaconPrincipal == null && beaconToBle.containsKey(name)) {
        beaconPrincipal = name;
        bleObjetivo = beaconToBle[name];
        estadoBLE = "Beacon $name activo (RSSI: $rssi)";
        notifyStateChanged();
      }
    } else if (rssi < -95) {
      // Señal muy débil, marcar como inactivo
      if (beaconPrincipal == name) {
        beaconPrincipal = null;
        bleObjetivo = null;
        estadoBLE = "Beacon $name inactivo por RSSI bajo ($rssi dBm)";
        notifyStateChanged();
      }
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

        // 🔎 Nueva lógica: solo considerar activos los que siguen apareciendo en results
        final activeBeacons = detectedNow.where((result) {
          final name = result.advertisementData.localName.isNotEmpty
              ? result.advertisementData.localName
              : result.device.name;
          final lastSeen = beaconLastSeen[name];
          return lastSeen != null && now.difference(lastSeen).inSeconds < 5;
        }).toList();

        beaconsDelim = activeBeacons;

        // Si el beacon principal ya no está en la lista → limpiamos
        if (beaconPrincipal != null &&
            !beaconsDelim.any(
              (b) =>
                  (b.advertisementData.localName.isNotEmpty
                      ? b.advertisementData.localName
                      : b.device.name) ==
                  beaconPrincipal,
            )) {
          estadoBLE = "Beacon $beaconPrincipal desapareció";
          beaconPrincipal = null;
          bleObjetivo = null;
          dispositivoBLE = null;
          notifyStateChanged();
        }
        // Lógica: Conectar automáticamente cuando hay un beacon principal detectado
        if (beaconPrincipal != null &&
            bleObjetivo != null &&
            dispositivoBLE == null &&
            !isConnecting &&
            !_reconexionPendiente &&
            _bluetoothOn) {
          _reconexionPendiente = true;
          estadoBLE =
              "Beacon $beaconPrincipal detectado, conectando a $bleObjetivo...";
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
          estadoConexion = 'Conectado a $bleObjetivo';
          colorEstado = Colors.green;
        } else if (beaconPrincipal != null) {
          estadoConexion = 'Beacon principal: $beaconPrincipal';
          colorEstado = Colors.blue;
        } else if (beaconsDelim.isNotEmpty) {
          estadoConexion = 'Beacons detectados: ${beaconsDelim.length}';
          colorEstado = Colors.orange;
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
    // Verificar que tenemos un beacon principal y BLE objetivo
    if (beaconPrincipal == null || bleObjetivo == null) {
      estadoBLE = "No hay beacon principal o BLE objetivo definido";
      isConnecting = false;
      notifyStateChanged();
      return;
    }
    // 🔎 Validar si el beacon sigue en la lista de activos
    final beaconSigueActivo = beaconsDelim.any((result) {
      final name = result.advertisementData.localName.isNotEmpty
          ? result.advertisementData.localName
          : result.device.name;
      return name == beaconPrincipal;
    });

    if (!beaconSigueActivo) {
      estadoBLE =
          "El beacon $beaconPrincipal ya no está activo, limpiando estado";
      beaconPrincipal = null;
      bleObjetivo = null;
      isConnecting = false;
      notifyStateChanged();
      return;
    }

    if (isConnecting || dispositivoBLE != null) {
      return; // ya estoy conectado o intentando conectar
    }

    isConnecting = true;
    estadoBLE = "Conectando a $bleObjetivo...";
    notifyStateChanged();

    try {
      // Buscar dispositivo BLE objetivo en los resultados actuales del escaneo
      final List<ScanResult> currentResults =
          await FlutterBluePlus.scanResults.first;

      final dispositivos = currentResults.where((device) {
        final name = device.advertisementData.localName.isNotEmpty
            ? device.advertisementData.localName
            : device.device.name;
        return name == bleObjetivo;
      }).toList();

      if (dispositivos.isEmpty) {
        estadoBLE = "$bleObjetivo no encontrado";
        isConnecting = false;
        notifyStateChanged();
        return;
      }

      final targetDevice = dispositivos.first;

      estadoBLE = "Conectando a $bleObjetivo...";
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
        throw TimeoutException("Timeout de conexión a $bleObjetivo");
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
                beaconPrincipal != null) {
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
      estadoBLE = "✅ Conectado automáticamente a $bleObjetivo";
      estadoConexion = 'Conectado a $bleObjetivo';
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

    // ⚠️ IMPORTANTE: limpiar beacons para evitar reconectar a uno viejo
    beaconPrincipal = null;
    bleObjetivo = null;

    // Actualizar estado
    estadoBLE = "Desconectado de $bleObjetivo";
    estadoConexion = 'Fuera de línea después de desconectar';
    colorEstado = Colors.orange;

    // Notificar cambios
    notifyStateChanged();

    // Llamar al callback de desconexión para refrescar toda la página
    onDisconnected?.call(null);

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
