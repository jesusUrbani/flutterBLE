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
  String _bleMessage = "Esperando dispositivo...";
  bool _isConnected = false;
  BluetoothCharacteristic? _messageCharacteristic;
  bool _showDialog = false;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
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
    FlutterBluePlus.stopScan();

    FlutterBluePlus.scanResults.listen((results) {
      for (var result in results) {
        if (result.device.platformName.startsWith('ESP32') && !_isConnected) {
          _connectToDevice(result.device);
          break;
        }
      }
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 30));
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        _bleName = device.platformName;
        _bleMessage = "Conectando...";
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
                if (value.isNotEmpty) {
                  final message = String.fromCharCodes(value);
                  setState(() => _bleMessage = message);
                  _triggerGateProcess();
                }
              });

              setState(() {
                _isConnected = true;
                _connectedDevice = device;
                _bleMessage = "Conectado. Esperando mensajes...";
              });
              return;
            }
          }
        }
      }

      // Si llega aquí es que no encontró la característica
      setState(() {
        _bleMessage = "Característica no encontrada";
      });
      _disconnectDevice();
    } catch (e) {
      setState(() {
        _bleMessage = "Error: ${e.toString()}";
      });
      _disconnectDevice();
    }
  }

  void _triggerGateProcess() {
    if (!_showDialog && mounted) {
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );

    if (openGate == true && mounted) {
      await _processGateOpening();
    }

    if (mounted) {
      setState(() {
        _showDialog = false;
      });
    }
    _disconnectDevice();
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

  Future<void> _disconnectDevice() async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (e) {
        debugPrint("Error al desconectar: $e");
      } finally {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _connectedDevice = null;
            _bleMessage = "Desconectado. Escaneando...";
          });
        }
        _startAutoScan();
      }
    }
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prueba BLE'),
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
            const SizedBox(height: 40),
            Text(_bleName, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 10),
            Text(
              _bleMessage,
              style: TextStyle(
                color: _isConnected ? Colors.green : Colors.grey,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
