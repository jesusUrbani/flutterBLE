import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class SaldoScreen extends StatefulWidget {
  const SaldoScreen({super.key});

  @override
  State<SaldoScreen> createState() => _SaldoScreenState();
}

class _SaldoScreenState extends State<SaldoScreen> {
  double _saldo = 100.0; // Saldo inicial
  bool _isScanning = false;
  bool _hasPermissions = false;
  BluetoothDevice? _connectedDevice;
  String _message = "No conectado";
  bool _isConnected = false;
  BluetoothCharacteristic? _messageCharacteristic;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _setupBluetoothListeners();
  }

  Future<void> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);

    setState(() {
      _hasPermissions = allGranted;
    });

    if (!allGranted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Permisos no concedidos')));
    }
  }

  void _setupBluetoothListeners() {
    FlutterBluePlus.scanResults.listen((results) {
      for (var result in results) {
        // Filtrar dispositivos ESP32 a menos de 2 metros (RSSI mayor a -60 aprox)
        if (result.device.platformName.startsWith('ESP32') &&
            result.rssi > -60) {
          _connectAndHandleDevice(result.device);
          break; // Conectarse solo al primero que cumpla las condiciones
        }
      }
    });

    FlutterBluePlus.isScanning.listen((isScanning) {
      setState(() {
        _isScanning = isScanning;
      });
    });
  }

  Future<void> _connectAndHandleDevice(BluetoothDevice device) async {
    try {
      setState(() {
        _message = "Conectando...";
        _isConnected = false;
      });

      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }

      await device.connect(autoConnect: false);
      setState(() {
        _connectedDevice = device;
        _message = "Buscando servicios...";
      });

      List<BluetoothService> services = await device.discoverServices();

      const serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
      const characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() ==
                characteristicUuid) {
              _messageCharacteristic = characteristic;

              List<int> value = await characteristic.read();
              setState(() {
                _message = String.fromCharCodes(value);
                _isConnected = true;
              });

              await characteristic.setNotifyValue(true);
              characteristic.value.listen((value) {
                if (value.isNotEmpty) {
                  final message = String.fromCharCodes(value);
                  setState(() {
                    _message = message;
                  });

                  // Si el mensaje indica que la compuerta está lista
                  if (message.contains("compuerta_lista")) {
                    _mostrarDialogoCompuerta();
                  }
                }
              });

              return;
            }
          }
        }
      }

      setState(() {
        _message = "No se encontró la característica del mensaje";
      });
    } catch (e) {
      setState(() {
        _message = "Error: $e";
        _isConnected = false;
      });
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _connectedDevice = null;
      }
    }
  }

  Future<void> _mostrarDialogoCompuerta() async {
    bool? abrir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Compuerta detectada'),
        content: const Text(
          '¿Deseas abrir la compuerta? Se descontará \$5 de tu saldo.',
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

    if (abrir == true) {
      // Enviar comando para abrir compuerta
      if (_messageCharacteristic != null) {
        await _messageCharacteristic!.write("abrir_compuerta".codeUnits);
      }

      // Actualizar saldo
      setState(() {
        _saldo -= 5.0;
      });

      // Mostrar confirmación
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Compuerta abierta'),
            content: const Text('La compuerta se ha abierto correctamente.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _startScan() async {
    if (!_hasPermissions) {
      await _checkPermissions();
      if (!_hasPermissions) return;
    }

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al escanear: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de Saldo'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Tu saldo actual es:', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            Text(
              '\$${_saldo.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _startScan,
              child: const Text('Buscar dispositivos cercanos'),
            ),
            const SizedBox(height: 20),
            Text(
              _isConnected ? 'Conectado: $_message' : _message,
              style: TextStyle(
                color: _isConnected ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
