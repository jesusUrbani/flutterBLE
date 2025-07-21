import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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
      home: const BleDeviceListScreen(),
    );
  }
}

class BleDeviceListScreen extends StatefulWidget {
  const BleDeviceListScreen({super.key});

  @override
  State<BleDeviceListScreen> createState() => _BleDeviceListScreenState();
}

class _BleDeviceListScreenState extends State<BleDeviceListScreen> {
  List<BluetoothDevice> _devices = [];
  bool _isScanning = false;
  bool _hasPermissions = false;

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

    if (allGranted) {
      setState(() {
        _hasPermissions = true;
      });
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Permissions not granted')));
    }
  }

  void _setupBluetoothListeners() {
    // Listen for scan results
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        // Filter devices with names and remove duplicates
        _devices = results
            .where((r) => r.device.platformName.isNotEmpty)
            .map((r) => r.device)
            .toSet()
            .toList();
      });
    });

    // Listen for scan state changes
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
      // Clear previous results
      setState(() {
        _devices = [];
      });

      // Start scan with timeout
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error starting scan: $e')));
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error stopping scan: $e')));
    }
  }

  Future<void> _refreshDeviceList() async {
    if (_isScanning) {
      await _stopScan();
    }
    await _startScan();
  }

  void _showDeviceDetails(BluetoothDevice device) {
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
                'Device Details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text('Name: ${device.platformName}'),
              Text('ID: ${device.remoteId.str}'),
              FutureBuilder<int?>(
                future: device.mtu.first,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Text('MTU: ${snapshot.data}');
                  } else {
                    return const Text('MTU: Unknown');
                  }
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
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
        title: const Text('BLE Devices'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshDeviceList,
            tooltip: 'Refresh list',
          ),
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.search),
            onPressed: _isScanning ? _stopScan : _startScan,
            tooltip: _isScanning ? 'Stop scan' : 'Start scan',
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
            const Text('Location permission required for BLE scanning'),
            ElevatedButton(
              onPressed: _checkPermissions,
              child: const Text('Request Permission'),
            ),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _isScanning ? 'Scanning for devices...' : 'No devices found',
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (!_isScanning)
              ElevatedButton(
                onPressed: _startScan,
                child: const Text('Start Scan'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return ListTile(
          leading: const Icon(Icons.bluetooth),
          title: Text(device.platformName),
          subtitle: Text(device.remoteId.str),
          trailing: IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showDeviceDetails(device),
          ),
        );
      },
    );
  }
}
