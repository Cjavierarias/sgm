import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';
import 'work_order_form_screen.dart';

class WorkOrdersScreen extends StatefulWidget {
  const WorkOrdersScreen({super.key});
  @override
  State<WorkOrdersScreen> createState() => _WorkOrdersScreenState();
}

class _WorkOrdersScreenState extends State<WorkOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String _error = '';
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final data = await auth.apiService.getWorkOrders();
      if (mounted) setState(() { _orders = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _exportToSheets(BuildContext context, AuthProvider auth) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exportando a Google Sheets...')),
      );
      final data = await auth.apiService.exportToSheets('work-orders');
      final url = data['sheet_url'] as String?;
      if (url != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exportado: ${data['rows_exported']} filas'),
            backgroundColor: BsaTheme.secondary,
            action: SnackBarAction(label: 'Abrir', onPressed: () => _openUrl(url)),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _openUrl(String url) {
    if (url.isNotEmpty) {
      html.window.open(url, '_blank');
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filterStatus == 'all') return _orders;
    return _orders.where((o) => o['status'] == _filterStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canCreate =
        auth.hasAnyRole(['admin', 'maintenance_manager', 'technician']);

    return Scaffold(
      backgroundColor: BsaTheme.background,
      appBar: AppBar(
        title: const Text('Órdenes de Trabajo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file, size: 20),
            tooltip: 'Exportar a Google Sheets',
            onPressed: () => _exportToSheets(context, auth),
          ),
          if (canCreate)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva OT'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const WorkOrderFormScreen()),
                  );
                  _load();
                },
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            selected: _filterStatus,
            onChanged: (v) => setState(() => _filterStatus = v),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error),
                            const SizedBox(height: 12),
                            ElevatedButton(
                                onPressed: _load, child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _filtered.isEmpty
                            ? const Center(
                                child: Text('No hay órdenes de trabajo'))
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, i) =>
                                    _WOCard(wo: _filtered[i]),
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _FilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final filters = [
      ('all', 'Todas'),
      ('open', 'Abiertas'),
      ('assigned', 'Asignadas'),
      ('in_progress', 'En Progreso'),
      ('waiting_parts', 'Esperando Repuestos'),
      ('closed', 'Cerradas'),
    ];
    return Container(
      color: Colors.white,
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: filters
            .map((f) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f.$2,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: selected == f.$1
                                ? Colors.white
                                : BsaTheme.textPrimary)),
                    selected: selected == f.$1,
                    onSelected: (_) => onChanged(f.$1),
                    selectedColor: BsaTheme.primary,
                    backgroundColor: BsaTheme.background,
                    showCheckmark: false,
                    side: BorderSide(
                      color: selected == f.$1
                          ? BsaTheme.primary
                          : BsaTheme.border,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _WOCard extends StatelessWidget {
  final Map<String, dynamic> wo;
  const _WOCard({required this.wo});

  Color _statusColor(String s) {
    switch (s) {
      case 'open': return BsaTheme.primary;
      case 'assigned': return const Color(0xFF7C3AED);
      case 'in_progress': return const Color(0xFFF59E0B);
      case 'waiting_parts': return const Color(0xFFD97706);
      case 'closed': return BsaTheme.secondary;
      case 'cancelled': return BsaTheme.textSecondary;
      default: return BsaTheme.textSecondary;
    }
  }

  String _statusLabel(String s) {
    const m = {
      'open': 'Abierta',
      'assigned': 'Asignada',
      'in_progress': 'En Progreso',
      'waiting_parts': 'Esp. Repuestos',
      'closed': 'Cerrada',
      'cancelled': 'Cancelada',
    };
    return m[s] ?? s;
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'critical': return const Color(0xFFEF4444);
      case 'high': return const Color(0xFFF59E0B);
      case 'medium': return BsaTheme.primary;
      default: return BsaTheme.textSecondary;
    }
  }

  String _priorityLabel(String p) {
    const m = {
      'low': 'Baja',
      'medium': 'Media',
      'high': 'Alta',
      'critical': 'Crítica',
    };
    return m[p] ?? p;
  }

  @override
  Widget build(BuildContext context) {
    final status = wo['status'] as String? ?? 'open';
    final priority = wo['priority'] as String? ?? 'medium';

    return Card(
      child: InkWell(
        onTap: () => context.go('/work-orders/${wo['id']}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      wo['title'] as String? ?? 'Sin título',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1E3A5F),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Badge(
                      label: _statusLabel(status),
                      color: _statusColor(status)),
                ],
              ),
              if (wo['description'] != null &&
                  (wo['description'] as String).isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  wo['description'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (wo['equipment_name'] != null)
                    Flexible(
                      child: _InfoChip(
                        icon: Icons.precision_manufacturing_rounded,
                        label: wo['equipment_name'] as String,
                      ),
                    ),
                  if (wo['assigned_to_name'] != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: _InfoChip(
                        icon: Icons.person_rounded,
                        label: wo['assigned_to_name'] as String,
                      ),
                    ),
                  ],
                  const Spacer(),
                  _Badge(
                    label: _priorityLabel(priority),
                    color: _priorityColor(priority),
                    small: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool small;
  const _Badge({required this.label, required this.color, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 8 : 10, vertical: small ? 3 : 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: small ? 11 : 12,
            fontWeight: FontWeight.w600,
            color: color),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
