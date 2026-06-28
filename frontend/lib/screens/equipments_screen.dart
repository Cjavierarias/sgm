// ─── EQUIPMENTS SCREEN ────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';

class EquipmentsScreen extends StatefulWidget {
  const EquipmentsScreen({super.key});
  @override
  State<EquipmentsScreen> createState() => _EquipmentsScreenState();
}

class _EquipmentsScreenState extends State<EquipmentsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _search = '';
  String _filterStatus = 'all';

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
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _items.where((eq) {
      final matchStatus = _filterStatus == 'all' || eq['status'] == _filterStatus;
      final q = _search.toLowerCase();
      final matchSearch = q.isEmpty ||
          (eq['name'] as String? ?? '').toLowerCase().contains(q) ||
          (eq['code'] as String? ?? '').toLowerCase().contains(q) ||
          (eq['location'] as String? ?? '').toLowerCase().contains(q);
      return matchStatus && matchSearch;
    }).toList();
  }

  static Color statusColor(String s) {
    switch (s) {
      case 'operational': return BsaTheme.secondary;
      case 'maintenance': return BsaTheme.warning;
      default: return BsaTheme.error;
    }
  }

  static String statusLabel(String s) {
    switch (s) {
      case 'operational': return 'Operativo';
      case 'maintenance': return 'En Mantenimiento';
      case 'out_of_service': return 'Fuera de Servicio';
      default: return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canCreate = auth.hasAnyRole(['admin', 'maintenance_manager']);

    return Scaffold(
      backgroundColor: BsaTheme.background,
      appBar: AppBar(
        title: const Text('Equipos'),
        actions: [
          if (canCreate)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () async {
                  await _showEquipmentForm(context);
                  _load();
                },
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Barra de búsqueda + filtros
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, código o ubicación...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: BsaTheme.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: BsaTheme.border)),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ('all', 'Todos'), ('operational', 'Operativos'),
                      ('maintenance', 'En Mant.'), ('out_of_service', 'Fuera servicio'),
                    ].map((f) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(f.$2, style: TextStyle(fontSize: 12,
                            color: _filterStatus == f.$1 ? Colors.white : BsaTheme.textPrimary)),
                        selected: _filterStatus == f.$1,
                        onSelected: (_) => setState(() => _filterStatus = f.$1),
                        selectedColor: BsaTheme.primary,
                        backgroundColor: BsaTheme.background,
                        showCheckmark: false,
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? const Center(child: Text('No hay equipos que coincidan'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) => _EquipmentCard(
                              eq: _filtered[i],
                              auth: auth,
                              onRefresh: _load,
                              onEdit: () => _showEquipmentForm(context, eq: _filtered[i]),
                              onStatusChange: (s) => _changeStatus(_filtered[i], s),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeStatus(Map<String, dynamic> eq, String newStatus) async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.apiService.updateEquipment(eq['id'] as int, {'status': newStatus});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showEquipmentForm(BuildContext context, {Map<String, dynamic>? eq}) async {
    final nameCtrl = TextEditingController(text: eq?['name'] ?? '');
    final codeCtrl = TextEditingController(text: eq?['code'] ?? '');
    final locationCtrl = TextEditingController(text: eq?['location'] ?? '');
    final brandCtrl = TextEditingController(text: eq?['brand'] ?? '');
    final modelCtrl = TextEditingController(text: eq?['model'] ?? '');
    final serialCtrl = TextEditingController(text: eq?['serial_number'] ?? '');
    final notesCtrl = TextEditingController(text: eq?['notes'] ?? '');
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(eq == null ? 'Nuevo Equipo' : 'Editar Equipo'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre *'),
                    validator: (v) => v!.isEmpty ? 'Requerido' : null),
                const SizedBox(height: 8),
                TextFormField(controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Código *'),
                    validator: (v) => v!.isEmpty ? 'Requerido' : null),
                const SizedBox(height: 8),
                TextFormField(controller: locationCtrl,
                    decoration: const InputDecoration(labelText: 'Ubicación')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextFormField(controller: brandCtrl,
                      decoration: const InputDecoration(labelText: 'Marca'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(controller: modelCtrl,
                      decoration: const InputDecoration(labelText: 'Modelo'))),
                ]),
                const SizedBox(height: 8),
                TextFormField(controller: serialCtrl,
                    decoration: const InputDecoration(labelText: 'N° de Serie')),
                const SizedBox(height: 8),
                TextFormField(controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notas'),
                    maxLines: 2),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final auth = Provider.of<AuthProvider>(context, listen: false);
              final data = {
                'name': nameCtrl.text.trim(),
                'code': codeCtrl.text.trim(),
                if (locationCtrl.text.isNotEmpty) 'location': locationCtrl.text.trim(),
                if (brandCtrl.text.isNotEmpty) 'brand': brandCtrl.text.trim(),
                if (modelCtrl.text.isNotEmpty) 'model': modelCtrl.text.trim(),
                if (serialCtrl.text.isNotEmpty) 'serial_number': serialCtrl.text.trim(),
                if (notesCtrl.text.isNotEmpty) 'notes': notesCtrl.text.trim(),
              };
              try {
                if (eq == null) {
                  await auth.apiService.createEquipment(data);
                } else {
                  await auth.apiService.updateEquipment(eq['id'] as int, data);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

// ─── Card de equipo con detalle expandible ────────────────────────────────────
class _EquipmentCard extends StatelessWidget {
  final Map<String, dynamic> eq;
  final AuthProvider auth;
  final VoidCallback onRefresh;
  final VoidCallback onEdit;
  final Function(String) onStatusChange;

  const _EquipmentCard({
    required this.eq, required this.auth, required this.onRefresh,
    required this.onEdit, required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final status = eq['status'] as String? ?? 'operational';
    final color = _EquipmentsScreenState.statusColor(status);
    final canEdit = auth.hasAnyRole(['admin', 'maintenance_manager']);

    return Card(
      child: InkWell(
        onTap: () => _showDetail(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.precision_manufacturing_rounded, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(eq['name'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                      color: BsaTheme.textPrimary)),
              const SizedBox(height: 3),
              Text('${eq['code'] ?? ''} · ${eq['location'] ?? 'Sin ubicación'}',
                  style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
              if (eq['brand'] != null || eq['model'] != null)
                Text('${eq['brand'] ?? ''} ${eq['model'] ?? ''}'.trim(),
                    style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_EquipmentsScreenState.statusLabel(status),
                    style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              ),
              if (canEdit) ...[
                const SizedBox(height: 6),
                PopupMenuButton<String>(
                  tooltip: 'Cambiar estado',
                  icon: const Icon(Icons.more_vert, size: 18, color: BsaTheme.textSecondary),
                  onSelected: (s) {
                    if (s == 'edit') {
                      onEdit();
                    } else {
                      onStatusChange(s);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [
                      Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('Editar')])),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'operational', child: Row(children: [
                      Icon(Icons.check_circle_outline, color: BsaTheme.secondary, size: 16),
                      SizedBox(width: 8), Text('Marcar Operativo')])),
                    const PopupMenuItem(value: 'maintenance', child: Row(children: [
                      Icon(Icons.build_outlined, color: Colors.orange, size: 16),
                      SizedBox(width: 8), Text('En Mantenimiento')])),
                    const PopupMenuItem(value: 'out_of_service', child: Row(children: [
                      Icon(Icons.cancel_outlined, color: BsaTheme.error, size: 16),
                      SizedBox(width: 8), Text('Fuera de Servicio')])),
                  ],
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EquipmentDetailSheet(eq: eq, auth: auth, onRefresh: onRefresh),
    );
  }
}

// ─── Sheet de detalle del equipo ──────────────────────────────────────────────
class _EquipmentDetailSheet extends StatefulWidget {
  final Map<String, dynamic> eq;
  final AuthProvider auth;
  final VoidCallback onRefresh;
  const _EquipmentDetailSheet({required this.eq, required this.auth, required this.onRefresh});

  @override
  State<_EquipmentDetailSheet> createState() => _EquipmentDetailSheetState();
}

class _EquipmentDetailSheetState extends State<_EquipmentDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _workOrders = [];
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDetail();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    try {
      final api = widget.auth.apiService;
      // Cargar OT y planes del equipo en paralelo
      final results = await Future.wait([
        api.getWorkOrders(),
        api.getMaintenancePlans(),
      ]);
      if (mounted) {
        final eqId = widget.eq['id'];
        setState(() {
          _workOrders = (results[0]).where((wo) => wo['equipment_id'] == eqId).toList();
          _plans = (results[1]).where((p) => p['equipment_id'] == eqId).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eq = widget.eq;
    final status = eq['status'] as String? ?? 'operational';
    final color = _EquipmentsScreenState.statusColor(status);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Center(child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(color: BsaTheme.border, borderRadius: BorderRadius.circular(2)),
            )),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.precision_manufacturing_rounded, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(eq['name'] as String? ?? '', style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: BsaTheme.textPrimary)),
                  Text('${eq['code'] ?? ''} · ${eq['location'] ?? ''}',
                      style: const TextStyle(fontSize: 13, color: BsaTheme.textSecondary)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(_EquipmentsScreenState.statusLabel(status),
                      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            // Datos técnicos
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Wrap(spacing: 16, runSpacing: 6, children: [
                if (eq['brand'] != null) _Detail(label: 'Marca', value: eq['brand']),
                if (eq['model'] != null) _Detail(label: 'Modelo', value: eq['model']),
                if (eq['serial_number'] != null) _Detail(label: 'N° Serie', value: eq['serial_number']),
              ]),
            ),
            if (eq['notes'] != null && (eq['notes'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: BsaTheme.background, borderRadius: BorderRadius.circular(8)),
                  child: Text(eq['notes'] as String,
                      style: const TextStyle(fontSize: 13, color: BsaTheme.textSecondary)),
                ),
              ),
            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: BsaTheme.primary,
              unselectedLabelColor: BsaTheme.textSecondary,
              indicatorColor: BsaTheme.primary,
              tabs: [
                Tab(text: 'Historial OT (${_workOrders.length})'),
                Tab(text: 'Planes (${_plans.length})'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // Historial OT
                        _workOrders.isEmpty
                            ? const Center(child: Text('Sin órdenes de trabajo'))
                            : ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: _workOrders.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (_, i) {
                                  final wo = _workOrders[i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.build_rounded, size: 18, color: BsaTheme.primary),
                                    title: Text(wo['title'] as String? ?? '',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    subtitle: Text('${wo['status'] ?? ''} · ${(wo['created_at'] as String? ?? '').length >= 10 ? (wo['created_at'] as String).substring(0, 10) : ''}',
                                        style: const TextStyle(fontSize: 11)),
                                    trailing: wo['assigned_to_name'] != null
                                        ? Text(wo['assigned_to_name'] as String,
                                            style: const TextStyle(fontSize: 11, color: BsaTheme.textSecondary))
                                        : null,
                                  );
                                },
                              ),
                        // Planes preventivos
                        _plans.isEmpty
                            ? const Center(child: Text('Sin planes de mantenimiento'))
                            : ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: _plans.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (_, i) {
                                  final p = _plans[i];
                                  final overdue = p['is_overdue'] == true;
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(Icons.event_repeat_rounded, size: 18,
                                        color: overdue ? BsaTheme.error : BsaTheme.secondary),
                                    title: Text(p['title'] as String? ?? '',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                      p['next_due'] != null
                                          ? 'Próximo: ${(p['next_due'] as String).substring(0, 10)}'
                                          : 'Sin fecha',
                                      style: TextStyle(fontSize: 11,
                                          color: overdue ? BsaTheme.error : BsaTheme.textSecondary),
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final String label;
  final dynamic value;
  const _Detail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10, color: BsaTheme.textSecondary,
          fontWeight: FontWeight.w600)),
      Text('$value', style: const TextStyle(fontSize: 13, color: BsaTheme.textPrimary)),
    ]);
  }
}
