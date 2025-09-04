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
  final double montoPago = 10.0; // Monto fijo para el pago
  int _refreshKey = 0; // Key para forzar rebuild completo

  @override
  void initState() {
    super.initState();
    _viewModel = CasetaViewModel(
      onStateChanged: (_) => setState(() {}),
      onDisconnected: (_) => setState(() {
        _refreshKey++; // Cambiar la key fuerza rebuild completo
      }),
    );
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
            // Mostrar saldo
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    color: Colors.blue,
                    size: 30,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Saldo: \$${_viewModel.saldo.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
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
            // Botón para iniciar el escaneo de ble
            if (_viewModel.beaconsDelim.length >= 2 &&
                _viewModel.dispositivoBLE == null)
              Container(), // Ya no mostramos el botón de conexión manual

            SizedBox(height: 10),

            // Botones cuando está conectado
            if (_viewModel.dispositivoBLE != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _viewModel.detenerConexionBLE,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 15,
                      ),
                    ),
                    child: Text('Desconectar', style: TextStyle(fontSize: 16)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      _viewModel.realizarPago(montoPago);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                    ),
                    child: Text(
                      'Pagar \$${montoPago.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
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
