import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/equipment.dart';
import '../providers/auth_provider.dart';

class EquipmentScreen extends StatefulWidget {
  final String equipmentId;

  const EquipmentScreen({super.key, required this.equipmentId});

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  late Future<Equipment> _equipmentFuture;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final id = int.tryParse(widget.equipmentId);
    if (id == null) {
      _equipmentFuture = Future.error('ID de equipo inválido');
    } else {
      _equipmentFuture = authProvider.fetchEquipmentById(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Equipo #${widget.equipmentId}')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<Equipment>(
          future: _equipmentFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  snapshot.error?.toString() ?? 'No se pudo cargar el equipo.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.red[700]),
                  textAlign: TextAlign.center,
                ),
              );
            }

            final equipment = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  equipment.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey[900],
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  equipment.code,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.blueGrey[700]),
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildField('Ubicación', equipment.location ?? 'No definida'),
                        const SizedBox(height: 12),
                        _buildField('Marca', equipment.brand ?? 'No especificada'),
                        const SizedBox(height: 12),
                        _buildField('Modelo', equipment.model ?? 'No especificado'),
                        const SizedBox(height: 12),
                        _buildField('Compañía ID', equipment.companyId.toString()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    if (context.mounted) {
                      context.go('/home');
                    }
                  },
                  child: const Text('Volver a la lista de equipos'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.blueGrey[600]),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
