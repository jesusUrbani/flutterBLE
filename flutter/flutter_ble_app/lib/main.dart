import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'test.dart'; // Importa la nueva pantalla
import 'saldo.dart'; // Importa la nueva pantalla

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const SaldoScreen(), // Usa EmptyScreen como pantalla inicial
    );
  }
}

class BleDeviceListScreen extends StatefulWidget {
  const BleDeviceListScreen({super.key});

  @override
  State<BleDeviceListScreen> createState() => _BleDeviceListScreenState();
}

class _BleDeviceListScreenState extends State<BleDeviceListScreen> {
  List<ScanResult> _scanResults = [];
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
      setState(() {
        _scanResults = results
            .where((result) => result.device.platformName.startsWith('ESP32'))
            .toList();
      });
    });

    FlutterBluePlus.isScanning.listen((isScanning) {
      setState(() {
        _isScanning = isScanning;
      });
    });
  }

  Future<void> _startScan() async {
    if (!_hasPermissions) {
      await _checkPermissions();
      if (!_hasPermissions) return;
    }

    try {
      setState(() {
        _scanResults = [];
      });
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

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al detener escaneo: $e')));
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        _message = "Conectando...";
        _isConnected = false;
      });

      // Cancelar conexión previa si existe
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }

      // Conectar al dispositivo
      await device.connect(autoConnect: false);
      setState(() {
        _connectedDevice = device;
        _message = "Buscando servicios...";
      });

      // Descubrir servicios
      List<BluetoothService> services = await device.discoverServices();

      // UUIDs del servicio y característica (debe coincidir con el ESP32)
      const serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
      const characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() ==
                characteristicUuid) {
              _messageCharacteristic = characteristic;

              // Leer el valor inicial
              List<int> value = await characteristic.read();
              setState(() {
                _message = String.fromCharCodes(value);
                _isConnected = true;
              });

              // Configurar notificaciones para recibir actualizaciones
              await characteristic.setNotifyValue(true);
              characteristic.value.listen((value) {
                if (value.isNotEmpty) {
                  setState(() {
                    _message = String.fromCharCodes(value);
                  });
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

  Future<void> _disconnectDevice() async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        setState(() {
          _message = "Desconectado";
          _isConnected = false;
          _connectedDevice = null;
          _messageCharacteristic = null;
        });
      } catch (e) {
        setState(() {
          _message = "Error al desconectar: $e";
        });
      }
    }
  }

  void _showDeviceDetails(ScanResult result) {
    final device = result.device;
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Detalles del dispositivo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text('Nombre: ${device.platformName}'),
              Text('ID: ${device.remoteId.str}'),
              Text('RSSI: ${result.rssi}'),
              const SizedBox(height: 16),
              if (_connectedDevice?.remoteId == device.remoteId && _isConnected)
                Column(
                  children: [
                    Text('Mensaje del ESP32: $_message'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        await _disconnectDevice(); // Agregar paréntesis y await
                        if (mounted) {
                          Navigator.pop(
                            context,
                          ); // Cerrar después de desconectar
                        }
                      },
                      child: const Text('Desconectar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                )
              else
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _connectToDevice(device);
                  },
                  child: const Text('Conectar y leer mensaje'),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos BLE'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _startScan,
            tooltip: 'Refrescar lista',
          ),
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.search),
            onPressed: _isScanning ? _stopScan : _startScan,
            tooltip: _isScanning ? 'Detener escaneo' : 'Iniciar escaneo',
          ),
        ],
      ),
      body: _buildDeviceList(),
    );
  }

  Widget _buildDeviceList() {
    if (!_hasPermissions) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Se requieren permisos para escanear dispositivos BLE'),
            ElevatedButton(
              onPressed: _checkPermissions,
              child: const Text('Solicitar permisos'),
            ),
          ],
        ),
      );
    }

    if (_scanResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _isScanning
                  ? 'Escaneando dispositivos...'
                  : 'No se encontraron dispositivos',
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (!_isScanning)
              ElevatedButton(
                onPressed: _startScan,
                child: const Text('Iniciar escaneo'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _scanResults.length,
      itemBuilder: (context, index) {
        final result = _scanResults[index];
        final device = result.device;
        final isConnected =
            _connectedDevice?.remoteId == device.remoteId && _isConnected;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            leading: Icon(
              Icons.bluetooth,
              color: isConnected ? Colors.blue : Colors.grey,
            ),
            title: Text(
              device.platformName.isNotEmpty
                  ? device.platformName
                  : 'Dispositivo desconocido',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.remoteId.str),
                Text('RSSI: ${result.rssi}'),
                if (isConnected)
                  Text(
                    'Mensaje: $_message',
                    style: const TextStyle(color: Colors.green),
                  ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showDeviceDetails(result),
            ),
            onTap: () => _showDeviceDetails(result),
          ),
        );
      },
    );
  }
}
