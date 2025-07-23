import 'package:flutter/material.dart';
import 'main.dart'; // Asegúrate de importar la pantalla BLE

class EmptyScreen extends StatelessWidget {
  const EmptyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pantalla Vacía'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Esta es una pantalla vacía',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BleDeviceListScreen(),
                  ),
                );
              },
              child: const Text('Ir a Pantalla BLE'),
            ),
          ],
        ),
      ),
    );
  }
}
