// ─── EQUIPMENTS SCREEN ────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class EquipmentsScreen extends StatefulWidget {
  const EquipmentsScreen({super.key});
  @override
  State<EquipmentsScreen> createState() => _EquipmentsScreenState();
}

class _EquipmentsScreenState extends State<EquipmentsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final data = await auth.apiService.getEquipments();
      if (mounted) setState(() { _items = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'operational': return const Color(0xFF27AE60);
      case 'maintenance': return const Color(0xFFE67E22);
      default: return const Color(0xFFC0392B);
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'operational': return 'Operativo';
      case 'maintenance': return 'En Mantenimiento';
      default: return 'Fuera de Servicio';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canCreate = auth.hasAnyRole(['admin', 'maintenance_manager']);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Equipos'),
        actions: [
          if (canCreate)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo Equipo'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () async {
                  await _showEquipmentForm(context);
                  _load();
                },
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? const Center(child: Text('No hay equipos registrados'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final eq = _items[i];
                        final status = eq['status'] as String? ?? 'operational';
                        return Card(
                          child: ListTile(
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E3A5F).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.precision_manufacturing_rounded,
                                color: Color(0xFF1E3A5F),
                              ),
                            ),
                            title: Text(
                              eq['name'] as String? ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${eq['code'] ?? ''} · ${eq['location'] ?? 'Sin ubicación'}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor(status).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _statusLabel(status),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: _statusColor(status),
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Future<void> _showEquipmentForm(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Equipo'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre *'),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Código *'),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(labelText: 'Ubicación'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: brandCtrl,
                  decoration: const InputDecoration(labelText: 'Marca'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: modelCtrl,
                  decoration: const InputDecoration(labelText: 'Modelo'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final auth = Provider.of<AuthProvider>(context, listen: false);
              await auth.apiService.createEquipment({
                'name': nameCtrl.text.trim(),
                'code': codeCtrl.text.trim(),
                'location': locationCtrl.text.trim(),
                'brand': brandCtrl.text.trim(),
                'model': modelCtrl.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
