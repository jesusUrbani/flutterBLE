import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  double _saldo = 100.0;
  BluetoothDevice? _connectedDevice;
  String _bleName = "No conectado";
  String _bleMessage = "Escaneando dispositivos...";
  bool _isConnected = false;
  BluetoothCharacteristic? _messageCharacteristic;
  bool _showDialog = false;
  bool _count = true;
  bool _isWaitingToReconnect = false;
  int? _currentRssi;
  final List<double> _rssiThresholds = [-43, -50, -60, -70, -80];
  int _currentThresholdIndex = 0;
  Timer? _scanTimer;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  Future<void> _initBluetooth() async {
    await _requestPermissions();
    _startAutoScan();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  void _startAutoScan() {
    if (_isWaitingToReconnect || _isConnected) return;

    FlutterBluePlus.stopScan();
    _currentThresholdIndex = 0;
    _scanTimer?.cancel();
    _scanSubscription?.cancel();

    setState(() {
      _bleMessage = "Buscando dispositivos cercanos...";
      _currentRssi = null;
    });

    _scanWithCurrentThreshold();
  }

  void _scanWithCurrentThreshold() {
    if (_currentThresholdIndex >= _rssiThresholds.length) {
      _currentThresholdIndex = 0;
    }

    final currentThreshold = _rssiThresholds[_currentThresholdIndex];

    setState(() {
      _bleMessage =
          "Buscando (RSSI > ${currentThreshold.toStringAsFixed(0)} dBm)...";
    });

    ScanResult? strongestDevice;
    bool deviceFound = false;

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (_isConnected || _isWaitingToReconnect || !mounted) return;

      for (var result in results) {
        if (result.device.platformName.startsWith('ESP32') &&
            result.rssi > currentThreshold) {
          if (strongestDevice == null || result.rssi > strongestDevice!.rssi) {
            strongestDevice = result;
          }
        }
      }

      if (strongestDevice != null && !deviceFound) {
        deviceFound = true;
        final nonNullDevice = strongestDevice!;
        _connectToDevice(nonNullDevice.device, nonNullDevice.rssi);
      }
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

    _scanTimer = Timer(const Duration(seconds: 8), () {
      if (!deviceFound && !_isConnected && mounted) {
        _currentThresholdIndex++;
        if (_currentThresholdIndex < _rssiThresholds.length) {
          _scanWithCurrentThreshold();
        } else {
          setState(() {
            _bleMessage =
                "No se encontraron dispositivos. Reiniciando búsqueda...";
          });
          Timer(const Duration(seconds: 2), () {
            _currentThresholdIndex = 0;
            _scanWithCurrentThreshold();
          });
        }
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device, int rssi) async {
    try {
      _scanTimer?.cancel();
      _scanSubscription?.cancel();

      setState(() {
        _connectedDevice = device;
        _bleName = device.platformName;
        _bleMessage = "Conectando... (RSSI: $rssi)";
        _isConnected = true;
        _currentRssi = rssi;
      });

      await device.connect(autoConnect: false);

      List<BluetoothService> services = await device.discoverServices();

      const serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
      const characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() ==
                characteristicUuid) {
              _messageCharacteristic = characteristic;

              await characteristic.setNotifyValue(true);
              characteristic.value.listen((value) {
                if (value.isNotEmpty && mounted) {
                  final message = String.fromCharCodes(value);
                  setState(() {
                    _bleMessage = "Mensaje: $message (RSSI: $_currentRssi)";
                  });
                  _triggerGateProcess();
                }
              });

              setState(() {
                _bleMessage =
                    "Conectado. Esperando mensajes... (RSSI: $_currentRssi)";
              });
              return;
            }
          }
        }
      }

      setState(() {
        _bleMessage = "Característica no encontrada";
      });
      _scheduleReconnection();
    } catch (e) {
      if (mounted) {
        setState(() {
          _bleMessage = "Error: ${e.toString()}";
        });
      }
      _scheduleReconnection();
    }
  }

  void _triggerGateProcess() {
    if (!_showDialog && mounted && _count) {
      _showDialog = true;
      _showGateDialog();
    }
  }

  Future<void> _showGateDialog() async {
    bool? openGate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Dispositivo: $_bleName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Mensaje recibido: $_bleMessage'),
            const SizedBox(height: 10),
            Text('Fuerza señal: $_currentRssi dBm'),
            const SizedBox(height: 20),
            const Text('¿Abrir compuerta? (\$5.00)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => {Navigator.pop(context, true), _count = false},
            child: const Text('Abrir'),
          ),
        ],
      ),
    );

    if (mounted) {
      setState(() {
        _showDialog = false;
      });
    }

    if (openGate == true && mounted) {
      await _processGateOpening();
    }

    _scheduleReconnection();
  }

  Future<void> _processGateOpening() async {
    if (_messageCharacteristic != null) {
      await _messageCharacteristic!.write("abrir".codeUnits);
    }

    if (mounted) {
      setState(() {
        _saldo -= 5.0;
        _bleMessage = "Procesando apertura...";
      });

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Compuerta abierta'),
          content: const Text('Se ha descontado \$5.00 de tu saldo'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _scheduleReconnection() async {
    if (_isWaitingToReconnect || !mounted) return;

    try {
      setState(() {
        _isWaitingToReconnect = true;
        _isConnected = false;
        _bleMessage = "Esperando 5 segundos para nueva conexión...";
        _bleName = "Buscando dispositivo...";
      });

      await _disconnectDevice();
      _count = false;

      await Future.delayed(const Duration(seconds: 5));

      _count = true;

      if (!mounted) return;

      setState(() {
        _isWaitingToReconnect = false;
        _bleMessage = "Buscando dispositivo más cercano...";
        _currentRssi = null;
        _bleName = "No conectado";
      });

      _startAutoScan();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isWaitingToReconnect = false;
        _bleMessage = "Error al reconectar: $e";
        _bleName = "Error de conexión";
      });
      _startAutoScan();
    }
  }

  Future<void> _disconnectDevice() async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect().timeout(
          const Duration(seconds: 2),
        );
      } catch (e) {
        debugPrint("Error al desconectar: $e");
      } finally {
        if (mounted) {
          setState(() {
            _connectedDevice = null;
            _messageCharacteristic = null;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de Compuerta BLE - Búsqueda Inteligente'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Saldo: \$${_saldo.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            Text(
              _bleName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            Text(
              _bleMessage,
              style: TextStyle(
                color: _isConnected
                    ? Colors.green
                    : _isWaitingToReconnect
                    ? Colors.orange
                    : Colors.grey,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            if (_currentRssi != null) ...[
              const SizedBox(height: 10),
              Text(
                'Fuerza de señal: $_currentRssi dBm',
                style: TextStyle(
                  color: _getRssiColor(_currentRssi!),
                  fontSize: 16,
                ),
              ),
            ],
            if (_isWaitingToReconnect) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              const Text(
                'Preparando nueva conexión...',
                style: TextStyle(color: Colors.orange),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi > -50) return Colors.green;
    if (rssi > -60) return Colors.lightGreen;
    if (rssi > -70) return Colors.yellow;
    return Colors.red;
  }
}
