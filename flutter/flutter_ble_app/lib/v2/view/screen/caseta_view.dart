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
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = CasetaViewModel(
      onStateChanged: (_) => setState(() {}),
      onDisconnected: (_) => setState(() {
        _refreshKey++;
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

            // Mostrar tarifa calculada si existe
            if (_viewModel.tarifaCalculada != null) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.attach_money, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'Tarifa: \$${_viewModel.tarifaCalculada!.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10),
            ],

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
              Container(),

            SizedBox(height: 10),

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

                  // BOTÓN DE PAGO ACTUALIZADO
                  ElevatedButton(
                    onPressed: () {
                      if (_viewModel.tarifaCalculada != null) {
                        _viewModel.realizarPago(_viewModel.tarifaCalculada!);
                      } else {
                        // Si no hay tarifa, usar un valor por defecto o mostrar error
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Esperando tarifa del ESP32...'),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _viewModel.tarifaCalculada != null
                          ? Colors.green
                          : Colors.grey,
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 15,
                      ),
                    ),
                    child: Text(
                      _viewModel.tarifaCalculada != null
                          ? 'Pagar \$${_viewModel.tarifaCalculada!.toStringAsFixed(2)}'
                          : 'Esperando tarifa...',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: 20),

            // Mensaje de error si existe
            if (_viewModel.errorMensaje != null) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _viewModel.errorMensaje!,
                        style: TextStyle(color: Colors.red[800]),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10),
            ],

            if (_viewModel.dispositivoBLE != null) ...[
              Text(
                'Mensajes BLE:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: MensajesBLEWidget(mensajes: _viewModel.mensajesBLE),
              ),
            ],
            Text(
              'Beacons detectados:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Expanded(
              child: BeaconListWidget(
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
