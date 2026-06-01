import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/equipment.dart';
import '../providers/auth_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Equipment>> _equipmentsFuture;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _equipmentsFuture = authProvider.fetchEquipments();
  }

  void _reloadEquipments() {
    setState(() {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _equipmentsFuture = authProvider.fetchEquipments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SGM Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await authProvider.logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bienvenido, ${authProvider.email.isNotEmpty ? authProvider.email : 'Usuario'}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[900],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Compañía: ${authProvider.companyId ?? 'No disponible'}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.blueGrey[700]),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: FutureBuilder<List<Equipment>>(
                future: _equipmentsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'No se pudo cargar la lista de equipos.',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.red[700]),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _reloadEquipments,
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    );
                  }

                  final equipments = snapshot.data ?? [];
                  if (equipments.isEmpty) {
                    return Center(
                      child: Text(
                        'No hay equipos registrados en tu compañía.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.blueGrey[700]),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      _reloadEquipments();
                      await _equipmentsFuture;
                    },
                    child: ListView.separated(
                      itemCount: equipments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final equipment = equipments[index];
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          elevation: 1,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            title: Text(equipment.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${equipment.code} · ${equipment.location ?? 'Sin ubicación'}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go('/equipment/${equipment.id}'),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
