import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';
import 'spare_part_detail_screen.dart';

class SparePartsScreen extends StatefulWidget {
  const SparePartsScreen({super.key});
  @override
  State<SparePartsScreen> createState() => _SparePartsScreenState();
}

class _SparePartsScreenState extends State<SparePartsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _parts = [];
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final parts = await auth.apiService.getSpareParts();
      final reqs = await auth.apiService.getSparePartRequests();
      if (mounted) {
        setState(() {
          _parts = parts;
          _requests = reqs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredParts {
    if (_search.isEmpty) return _parts;
    final q = _search.toLowerCase();
    return _parts
        .where((p) =>
            (p['name'] as String? ?? '').toLowerCase().contains(q) ||
            (p['code'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canManage =
        auth.hasAnyRole(['admin', 'warehouse', 'maintenance_manager']);
    final pendingCount =
        _requests.where((r) => r['status'] == 'pending').length;

    return Scaffold(
      backgroundColor: BsaTheme.background,
      appBar: AppBar(
        title: const Text('Depósito y Stock'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.inventory_2_rounded), text: 'Repuestos'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_horiz_rounded, size: 18),
                  const SizedBox(width: 6),
                  const Text('Pedidos'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$pendingCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.compare_arrows_rounded, size: 18),
                  const SizedBox(width: 6),
                  const Text('Movimientos'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SparePartFormScreen(),
                    ),
                  );
                  _load();
                },
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _PartsTab(
                  parts: _filteredParts,
                  search: _search,
                  onSearchChanged: (v) => setState(() => _search = v),
                  onRefresh: _load,
                  auth: auth,
                ),
                _RequestsTab(
                  requests: _requests,
                  onRefresh: _load,
                  auth: auth,
                ),
                _MovementsTab(
                  parts: _parts,
                  auth: auth,
                  onRefresh: _load,
                ),
              ],
            ),
      floatingActionButton: auth.hasAnyRole(
              ['admin', 'maintenance_manager', 'technician', 'warehouse'])
          ? FloatingActionButton.extended(
              onPressed: () async {
                await _showRequestForm(context);
                _load();
              },
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Pedir Repuesto'),
              backgroundColor: BsaTheme.primary,
            )
          : null,
    );
  }

  Future<void> _showRequestForm(BuildContext context) async {
    if (_parts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay repuestos disponibles')));
      return;
    }
    int? selectedPartId = _parts.first['id'] as int?;
    final qtyCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Pedir Repuesto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: selectedPartId,
                  decoration: const InputDecoration(labelText: 'Repuesto *'),
                  items: _parts
                      .map((p) => DropdownMenuItem(
                            value: p['id'] as int,
                            child: Text(
                                '${p['code']} - ${p['name']} (${p['stock']} ${p['unit']})',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setD(() => selectedPartId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Cantidad *'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Notas (opcional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (selectedPartId == null) return;
                final qty = double.tryParse(qtyCtrl.text) ?? 0;
                if (qty <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Ingresá una cantidad válida')));
                  return;
                }
                try {
                  final auth =
                      Provider.of<AuthProvider>(context, listen: false);
                  await auth.apiService.createSparePartRequest({
                    'spare_part_id': selectedPartId,
                    'quantity': qty,
                    if (notesCtrl.text.isNotEmpty) 'notes': notesCtrl.text,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  // Mostrar confirmación en la pantalla padre
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Pedido enviado al depósito'),
                      backgroundColor: BsaTheme.secondary,
                    ),
                  );
                } catch (e) {
                  if (ctx.mounted)
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Enviar Pedido'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab Repuestos ────────────────────────────────────────────────────────────

class _PartsTab extends StatelessWidget {
  final List<Map<String, dynamic>> parts;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;
  final AuthProvider auth;

  const _PartsTab({
    required this.parts,
    required this.search,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.auth,
  });

  @override
  Widget build(BuildContext context) {
    final lowStockCount = parts.where((p) => p['is_low_stock'] == true).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o código...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: onSearchChanged,
              ),
              if (lowStockCount > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '$lowStockCount repuesto${lowStockCount > 1 ? 's' : ''} con stock bajo',
                        style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => onRefresh(),
            child: parts.isEmpty
                ? const Center(child: Text('No hay repuestos registrados'))
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: parts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _PartCard(
                        part: parts[i], auth: auth, onRefresh: onRefresh),
                  ),
          ),
        ),
      ],
    );
  }
}

class _PartCard extends StatelessWidget {
  final Map<String, dynamic> part;
  final AuthProvider auth;
  final VoidCallback onRefresh;
  const _PartCard(
      {required this.part, required this.auth, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final stock = (part['stock'] as num?)?.toDouble() ?? 0;
    final minStock = (part['min_stock'] as num?)?.toDouble() ?? 0;
    final isLow = part['is_low_stock'] == true;
    final canManage =
        auth.hasAnyRole(['admin', 'warehouse', 'maintenance_manager']);

    return Card(
      child: InkWell(
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      SparePartDetailScreen(partId: part['id'] as int)));
          onRefresh();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isLow
                      ? Colors.orange.withOpacity(0.1)
                      : const Color(0xFF1E3A5F).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isLow
                      ? Icons.warning_amber_rounded
                      : Icons.inventory_2_rounded,
                  color: isLow ? Colors.orange : const Color(0xFF1E3A5F),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(part['name'] as String? ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      'Código: ${part['code']} · ${part['location'] ?? 'Sin ubicación'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isLow
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$stock ${part['unit'] ?? ''}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isLow ? Colors.orange : Colors.green),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('mín: $minStock',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'entry' || action == 'exit') {
                      await _showMovementDialog(context, action);
                      onRefresh();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'entry',
                        child: Row(children: [
                          Icon(Icons.add_circle_outline,
                              color: Colors.green, size: 18),
                          SizedBox(width: 8),
                          Text('Entrada de stock'),
                        ])),
                    const PopupMenuItem(
                        value: 'exit',
                        child: Row(children: [
                          Icon(Icons.remove_circle_outline,
                              color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Text('Salida de stock'),
                        ])),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMovementDialog(BuildContext context, String type) async {
    final qtyCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();
    final isEntry = type == 'entry';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEntry ? 'Entrada de Stock' : 'Salida de Stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Repuesto: ${part['name']}',
                style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('Stock actual: ${part['stock']} ${part['unit']}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: 'Cantidad *'),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: isEntry ? Colors.green : Colors.red),
            onPressed: () async {
              final qty = double.tryParse(qtyCtrl.text) ?? 0;
              if (qty <= 0) return;
              final authProv =
                  Provider.of<AuthProvider>(context, listen: false);
              if (isEntry) {
                await authProv.apiService
                    .sparePartEntry(part['id'] as int, qty, notesCtrl.text);
              } else {
                await authProv.apiService
                    .sparePartExit(part['id'] as int, qty, notesCtrl.text);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(isEntry ? 'Registrar Entrada' : 'Registrar Salida'),
          ),
        ],
      ),
    );
  }
}

// ─── Tab Pedidos ──────────────────────────────────────────────────────────────

class _RequestsTab extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final VoidCallback onRefresh;
  final AuthProvider auth;
  const _RequestsTab(
      {required this.requests, required this.onRefresh, required this.auth});

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return const Color(0xFF2E86AB);
      case 'delivered':
        return const Color(0xFF27AE60);
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String s) {
    const m = {
      'pending': 'Pendiente',
      'approved': 'Aprobado',
      'delivered': 'Entregado',
      'rejected': 'Rechazado',
    };
    return m[s] ?? s;
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        auth.hasAnyRole(['admin', 'warehouse', 'maintenance_manager']);

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: requests.isEmpty
          ? const Center(child: Text('No hay pedidos'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final req = requests[i];
                final status = req['status'] as String? ?? '';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${req['spare_part_name'] ?? 'Repuesto'} (${req['spare_part_code'] ?? ''})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor(status).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _statusLabel(status),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _statusColor(status)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Cantidad: ${req['quantity']} · Solicitado por: ${req['requested_by_name'] ?? 'N/A'}',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        if (req['work_order_title'] != null)
                          Text(
                            'OT: ${req['work_order_title']}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        if (req['notes'] != null &&
                            (req['notes'] as String).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              req['notes'] as String,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic),
                            ),
                          ),
                        if (canManage && status == 'pending') ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.check_circle_outline,
                                    size: 16),
                                label: const Text('Aprobar',
                                    style: TextStyle(fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF2E86AB)),
                                onPressed: () async {
                                  await Provider.of<AuthProvider>(context,
                                          listen: false)
                                      .apiService
                                      .approveSparePartRequest(
                                          req['id'] as int);
                                  onRefresh();
                                },
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.local_shipping_rounded,
                                    size: 16),
                                label: const Text('Entregar',
                                    style: TextStyle(fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.green),
                                onPressed: () async {
                                  await Provider.of<AuthProvider>(context,
                                          listen: false)
                                      .apiService
                                      .deliverSparePartRequest(
                                          req['id'] as int);
                                  onRefresh();
                                },
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                icon:
                                    const Icon(Icons.cancel_outlined, size: 16),
                                label: const Text('Rechazar',
                                    style: TextStyle(fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red),
                                onPressed: () async {
                                  await Provider.of<AuthProvider>(context,
                                          listen: false)
                                      .apiService
                                      .rejectSparePartRequest(req['id'] as int);
                                  onRefresh();
                                },
                              ),
                            ],
                          ),
                        ],
                        if (canManage && status == 'approved') ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.local_shipping_rounded,
                                    size: 16),
                                label: const Text('Marcar Entregado'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.green),
                                onPressed: () async {
                                  await Provider.of<AuthProvider>(context,
                                          listen: false)
                                      .apiService
                                      .deliverSparePartRequest(
                                          req['id'] as int);
                                  onRefresh();
                                },
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ─── Tab Movimientos (Entregas/Ingresos Batch) ────────────────────────────────

class _MovementsTab extends StatefulWidget {
  final List<Map<String, dynamic>> parts;
  final AuthProvider auth;
  final VoidCallback onRefresh;
  const _MovementsTab(
      {required this.parts, required this.auth, required this.onRefresh});

  @override
  State<_MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends State<_MovementsTab> {
  final _items = <_BatchItem>[];
  List<Map<String, dynamic>> _movements = [];
  bool _loadingMovements = false;

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  Future<void> _loadMovements() async {
    setState(() => _loadingMovements = true);
    try {
      _movements = await widget.auth.apiService.getMovementHistory(days: 30);
    } catch (_) {
      _movements = [];
    }
    if (mounted) setState(() => _loadingMovements = false);
  }

  @override
  void didUpdateWidget(covariant _MovementsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onRefresh != oldWidget.onRefresh) _loadMovements();
  }

  Color _movementColor(String type) {
    switch (type) {
      case 'entry':
        return Colors.green;
      case 'exit':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        widget.auth.hasAnyRole(['admin', 'warehouse', 'maintenance_manager']);

    return Column(
      children: [
        if (canManage && widget.parts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Entrada de Stock'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _showBatchForm(context, 'entry'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('Salida / Entrega'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _showBatchForm(context, 'exit'),
                  ),
                ),
              ],
            ),
          ),
        // ── Historial diario ──────────────────────────────────────────────
        Expanded(
          child: _loadingMovements
              ? const Center(child: CircularProgressIndicator())
              : _movements.isEmpty
                  ? const Center(child: Text('No hay movimientos registrados'))
                  : _buildHistoryList(),
        ),
      ],
    );
  }

  Widget _buildHistoryList() {
    // Agrupar por fecha (día)
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final m in _movements) {
      final dt = DateTime.parse(m['created_at'] as String);
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(m);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Historial de movimientos (últimos 30 días)',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700]),
          ),
        ),
        ...grouped.entries.map((entry) {
          final dayMovements = entry.value;
          // Calcular resumen del día
          double entries = 0, exits = 0;
          for (final m in dayMovements) {
            if (m['movement_type'] == 'entry')
              entries += (m['quantity'] as num).toDouble();
            else
              exits += (m['quantity'] as num).toDouble();
          }
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(entry.key,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const Spacer(),
                      if (entries > 0)
                        Text('+$entries  ',
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                                fontSize: 12)),
                      if (exits > 0)
                        Text('-$exits',
                            style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                                fontSize: 12)),
                    ],
                  ),
                  const Divider(height: 12),
                  ...dayMovements.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    _movementColor(m['movement_type'] as String)
                                        .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                m['movement_type'] == 'entry' ? 'ENT' : 'SAL',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _movementColor(
                                      m['movement_type'] as String),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${m['spare_part_name'] ?? 'N/A'} (${m['spare_part_code'] ?? ''})',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  if (m['notes'] != null)
                                    Text(m['notes'] as String,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600])),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(m['quantity'] as num).toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _movementColor(
                                    m['movement_type'] as String),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _showBatchForm(BuildContext context, String type) async {
    _items.clear();
    _items.add(_BatchItem());

    final notesCtrl = TextEditingController();
    final isEntry = type == 'entry';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(isEntry ? 'Entrada de Stock' : 'Salida / Entrega'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEntry
                        ? 'Registrar ingreso de uno o más repuestos'
                        : 'Registrar entrega de uno o más repuestos',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  ..._items.asMap().entries.map((entry) {
                    final item = entry.value;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: item.sparePartId,
                                    decoration: const InputDecoration(
                                        labelText: 'Repuesto *',
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8)),
                                    isExpanded: true,
                                    items: widget.parts
                                        .map((p) => DropdownMenuItem(
                                              value: p['id'] as int,
                                              child: Text(
                                                  '${p['code']} - ${p['name']} (${p['stock']} ${p['unit']})',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 13)),
                                            ))
                                        .toList(),
                                    onChanged: (v) =>
                                        setD(() => item.sparePartId = v),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 80,
                                  child: TextFormField(
                                    initialValue: item.quantity.toString(),
                                    decoration: const InputDecoration(
                                        labelText: 'Cant.',
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8)),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) => setD(() => item.quantity =
                                        double.tryParse(v) ?? 1),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: item.notes,
                              decoration: InputDecoration(
                                  labelText: 'Notas (opcional)',
                                  hintText: isEntry
                                      ? 'Ej: Recepción OC #123'
                                      : 'Ej: Entregado a técnico',
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8)),
                              onChanged: (v) => setD(() => item.notes = v),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Agregar otro artículo'),
                    onPressed: () => setD(() => _items.add(_BatchItem())),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Nota general (opcional)',
                        hintText: 'Ej: Recepción semanal'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: isEntry ? Colors.green : Colors.red),
              onPressed: () async {
                final validItems = _items
                    .where((i) => i.sparePartId != null && i.quantity > 0)
                    .map((i) => {
                          'spare_part_id': i.sparePartId,
                          'quantity': i.quantity,
                          if (i.notes != null && i.notes!.isNotEmpty)
                            'notes': i.notes,
                        })
                    .toList();
                if (validItems.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text(
                          'Agregá al menos un artículo con cantidad válida')));
                  return;
                }
                // Agregar nota general a cada item si no tiene notas específicas
                if (notesCtrl.text.isNotEmpty) {
                  for (final item in validItems) {
                    if (item['notes'] == null) {
                      item['notes'] = notesCtrl.text;
                    }
                  }
                }
                try {
                  final result = await widget.auth.apiService
                      .batchSparePartMovement(type, validItems);
                  if (ctx.mounted) Navigator.pop(ctx);
                  widget.onRefresh();
                  if (ctx.mounted) {
                    final r = result;
                    final errors = r['errors'] as List? ?? [];
                    final msg = errors.isEmpty
                        ? '✅ ${r['processed']} artículo(s) procesado(s)'
                        : '⚠️ ${r['processed']} procesado(s), ${errors.length} error(es):\n${errors.join('\n')}';
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: Text(isEntry ? 'Registrar Entrada' : 'Registrar Salida'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchItem {
  int? sparePartId;
  double quantity = 1;
  String? notes;

  _BatchItem();
}
