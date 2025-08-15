import 'package:flutter/material.dart';

import '../widget/beacon_widget.dart';
import '../viewmodel/caseta_model.dart';

class CasetaPage extends StatefulWidget {
  const CasetaPage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<CasetaPage> createState() => _CasetaPageState();
}

class _CasetaPageState extends State<CasetaPage> {
  late CasetaViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = CasetaViewModel(onStateChanged: (_) => setState(() {}));
    _viewModel.init();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              _viewModel.estadoConexion,
              style: TextStyle(
                fontSize: 24,
                color: _viewModel.colorEstado,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              _viewModel.estadoBLE,
              style: TextStyle(fontSize: 18, color: Colors.purple),
            ),
            SizedBox(height: 20),
            if (_viewModel.beaconsDelim.length >= 2 &&
                _viewModel.dispositivoBLE == null)
              ElevatedButton(
                onPressed: _viewModel.conectarABleUrbani,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                child: Text(
                  'Conectar a BLE_URBANI',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            SizedBox(height: 10),
            if (_viewModel.dispositivoBLE != null)
              ElevatedButton(
                onPressed: _viewModel.detenerConexionBLE,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                child: Text('Desconectar', style: TextStyle(fontSize: 18)),
              ),
            SizedBox(height: 20),
            if (_viewModel.dispositivoBLE != null) ...[
              Text(
                'Mensajes BLE:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: MensajesBLEWidget(
                  // Usamos el widget de mensajes
                  mensajes: _viewModel.mensajesBLE,
                ),
              ),
            ],
            Text(
              'Beacons detectados:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Expanded(
              child: BeaconListWidget(
                // Usamos el widget de beacons
                beacons: _viewModel.beaconsDelim,
                getSignalColor: _viewModel.getSignalColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
