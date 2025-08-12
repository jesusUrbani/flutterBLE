import 'package:flutter/material.dart';

class CasetaPage extends StatefulWidget {
  const CasetaPage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<CasetaPage> createState() => _CasetaPageState();
}

class _CasetaPageState extends State<CasetaPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Hola', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // Acción del botón
              },
              child: const Text('Botón'),
            ),
          ],
        ),
      ),
    );
  }
}
