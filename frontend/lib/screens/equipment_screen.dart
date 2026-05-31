import 'package:flutter/material.dart';

class EquipmentScreen extends StatelessWidget {
  final String equipmentId;

  const EquipmentScreen({super.key, required this.equipmentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Equipo #$equipmentId')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalle del equipo $equipmentId',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Esta pantalla es un ejemplo de navegación dinámica con GoRouter.'),
          ],
        ),
      ),
    );
  }
}
