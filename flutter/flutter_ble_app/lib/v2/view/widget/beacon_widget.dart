import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BeaconListWidget extends StatelessWidget {
  final List<ScanResult> beacons;
  final Color Function(int rssi) getSignalColor;

  const BeaconListWidget({
    Key? key,
    required this.beacons,
    required this.getSignalColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (beacons.isEmpty) {
      return Center(
        child: Text(
          'No se detectan beacons Delim',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: beacons.length,
      itemBuilder: (context, index) {
        final beacon = beacons[index];
        final name = beacon.advertisementData.localName.isNotEmpty
            ? beacon.advertisementData.localName
            : beacon.device.name;
        final rssi = beacon.rssi;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: getSignalColor(rssi),
            child: Icon(Icons.bluetooth, color: Colors.white),
          ),
          title: Text(name),
          subtitle: Text('${beacon.device.id.id} (${rssi} dBm)'),
        );
      },
    );
  }
}

class MensajesBLEWidget extends StatelessWidget {
  final List<String> mensajes;

  const MensajesBLEWidget({Key? key, required this.mensajes}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (mensajes.isEmpty) {
      return Center(
        child: Text(
          'No hay mensajes recibidos',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: mensajes.length,
      itemBuilder: (context, index) {
        return ListTile(
          leading: Icon(Icons.message, color: Colors.blue),
          title: Text(mensajes[index]),
        );
      },
    );
  }
}
