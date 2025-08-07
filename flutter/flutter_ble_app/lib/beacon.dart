import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class BeaconScreen extends StatefulWidget {
  const BeaconScreen({super.key});

  @override
  State<BeaconScreen> createState() => _BleDeviceListScreenState();
}

class _BleDeviceListScreenState extends State<BeaconScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _hasPermissions = false;
  BluetoothDevice? _connectedDevice;
  String _message = "No conectado";
  bool _isConnected = false;
  BluetoothCharacteristic? _messageCharacteristic;
  Timer? _scanTimer;
  Timer? _rssiTimer;
  Map<String, int> _deviceRssi = {};
  bool _isRssiMonitoring = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _setupBluetoothListeners();
    _startScan();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _rssiTimer?.cancel();
    _stopRssiUpdates();
    _disconnectDevice();
    super.dispose();
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
            .where((result) => result.device.platformName.startsWith('Delim_'))
            .toList();

        // Actualizar RSSI de los dispositivos encontrados
        for (var result in _scanResults) {
          _deviceRssi[result.device.remoteId.str] = result.rssi;
        }

        // Iniciar monitoreo de RSSI si hay dispositivos
        if (_scanResults.isNotEmpty && !_isRssiMonitoring) {
          _startRssiUpdates();
        }
      });
    });

    FlutterBluePlus.isScanning.listen((isScanning) {
      setState(() {
        _isScanning = isScanning;
      });
    });
  }

  void _startRssiUpdates() {
    _stopRssiUpdates(); // Detener cualquier actualización previa

    setState(() {
      _isRssiMonitoring = true;
    });

    _rssiTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_scanResults.isEmpty) {
        _stopRssiUpdates();
        return;
      }

      // Crear una copia de los resultados para evitar modificaciones durante la iteración
      final devices = List<BluetoothDevice>.from(
        _scanResults.map((result) => result.device),
      );

      for (var device in devices) {
        try {
          if (device.isConnected) {
            // Para dispositivos conectados, podemos leer el RSSI directamente
            int rssi = await device.readRssi();
            _updateRssi(device.remoteId.str, rssi);
          } else {
            // Para dispositivos no conectados, necesitamos escanear continuamente
            // El RSSI se actualizará a través del listener de scanResults
          }
        } catch (e) {
          debugPrint('Error al leer RSSI: $e');
        }
      }
    });
  }

  void _stopRssiUpdates() {
    _rssiTimer?.cancel();
    setState(() {
      _isRssiMonitoring = false;
    });
  }

  void _updateRssi(String deviceId, int rssi) {
    if (mounted) {
      setState(() {
        _deviceRssi[deviceId] = rssi;
      });
    }
  }

  Future<void> _startScan() async {
    if (!_hasPermissions) {
      await _checkPermissions();
      if (!_hasPermissions) return;
    }

    try {
      setState(() {
        _scanResults = [];
        _deviceRssi.clear();
      });

      // Configurar escaneo continuo con intervalo
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );

      // Detener el escaneo después de 15 segundos
      _scanTimer?.cancel();
      _scanTimer = Timer(const Duration(seconds: 15), _stopScan);
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
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _startScan,
      child: ListView.builder(
        itemCount: _scanResults.length,
        itemBuilder: (context, index) {
          final result = _scanResults[index];
          final device = result.device;
          final isConnected =
              _connectedDevice?.remoteId == device.remoteId && _isConnected;
          final rssi = _deviceRssi[device.remoteId.str] ?? result.rssi;

          // Calcular la intensidad de la señal como porcentaje (aproximado)
          int signalStrength = 0;
          if (rssi > -50) {
            signalStrength = 100;
          } else if (rssi > -60) {
            signalStrength = 80;
          } else if (rssi > -70) {
            signalStrength = 60;
          } else if (rssi > -80) {
            signalStrength = 40;
          } else if (rssi > -90) {
            signalStrength = 20;
          }

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
                  Row(
                    children: [
                      Text('RSSI: $rssi dBm'),
                      const SizedBox(width: 10),
                      Text(
                        '$signalStrength%',
                        style: TextStyle(
                          color: signalStrength > 60
                              ? Colors.green
                              : signalStrength > 30
                              ? Colors.orange
                              : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.signal_cellular_alt,
                        size: 16,
                        color: signalStrength > 60
                            ? Colors.green
                            : signalStrength > 30
                            ? Colors.orange
                            : Colors.red,
                      ),
                    ],
                  ),
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
      ),
    );
  }

  void _showDeviceDetails(ScanResult result) {
    final device = result.device;
    final rssi = _deviceRssi[device.remoteId.str] ?? result.rssi;
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
              Text('RSSI: $rssi dBm'),
              const SizedBox(height: 16),
              if (_connectedDevice?.remoteId == device.remoteId && _isConnected)
                Column(
                  children: [
                    Text('Mensaje del ESP32: $_message'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        await _disconnectDevice();
                        if (mounted) {
                          Navigator.pop(context);
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
}
