import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'dart:collection';
import 'package:permission_handler/permission_handler.dart';

class CasetaPage extends StatefulWidget {
  const CasetaPage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<CasetaPage> createState() => _CasetaPageState();
}

class _CasetaPageState extends State<CasetaPage> {
  String texto = 'Sin conexión';
  Color colorTexto = Colors.black; // Color inicial

  void cambiarTexto() {
    setState(() {
      if (texto == 'Sin conexión') {
        texto = 'Conectado';
        colorTexto = Colors.green; // Cambia a verde
      } else {
        texto = 'Sin conexión';
        colorTexto = Colors.black; // Vuelve a negro
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              texto,
              style: TextStyle(
                fontSize: 32,
                color: colorTexto, // Aplica el color
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: cambiarTexto, // Llama a la función
              child: const Text('Botón'),
            ),
          ],
        ),
      ),
    );
  }
}
