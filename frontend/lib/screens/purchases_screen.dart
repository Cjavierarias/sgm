import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _pos = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _invoices = [];
  bool _loading = true;
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
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
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      final results = await Future.wait([
        api.getPurchaseOrders(),
        api.getSuppliers(),
        api.getInvoices(),
      ]);
      if (mounted) {
        setState(() {
          _pos = results[0];
          _suppliers = results[1];
          _invoices = results[2];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredPOs {
    if (_filterStatus == 'all') return _pos;
    return _pos.where((p) => p['status'] == _filterStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canManage = auth.hasAnyRole(['admin', 'purchasing', 'maintenance_manager']);
    final pendingInvoices = _invoices.where((i) => i['status'] == 'pending').length;

    return Scaffold(
      backgroundColor: BsaTheme.background,
      appBar: AppBar(
        title: const Text('Módulo de Compras'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.shopping_cart_rounded), text: 'Órdenes de Compra'),
            const Tab(icon: Icon(Icons.business_rounded), text: 'Proveedores'),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.receipt_long_rounded, size: 18),
                const SizedBox(width: 6),
                const Text('Facturas'),
                if (pendingInvoices > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: BsaTheme.warning,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$pendingInvoices',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
            ),
          ],
        ),
        actions: [
          if (canManage && _tabController.index == 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva OC'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () => _showPOForm(context),
              ),
            ),
          if (canManage && _tabController.index == 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Proveedor'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () => _showSupplierForm(context),
              ),
            ),
          if (canManage && _tabController.index == 2)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Factura'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () => _showInvoiceForm(context),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _POTab(
                  pos: _filteredPOs,
                  allPos: _pos,
                  filterStatus: _filterStatus,
                  onFilterChanged: (v) => setState(() => _filterStatus = v),
                  onRefresh: _load,
                  onReceive: _showReceiveForm,
                  onChangeStatus: _changePOStatus,
                  onShowDetail: (po) => _showPODetail(context, po),
                  auth: auth,
                  canEdit: canManage,
                ),
                _SuppliersTab(
                  suppliers: _suppliers,
                  onRefresh: _load,
                  auth: auth,
                  onEdit: (s) => _showSupplierForm(context, supplier: s),
                  canEdit: canManage,
                ),
                _InvoicesTab(
                  invoices: _invoices,
                  pos: _pos,
                  onRefresh: _load,
                  auth: auth,
                  canEdit: canManage,
                ),
              ],
            ),
    );
  }

  // ── Detalle OC ───────────────────────────────────────────────────────────
  void _showPODetail(BuildContext context, Map<String, dynamic> po) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PODetailSheet(
        po: po,
        auth: Provider.of<AuthProvider>(context, listen: false),
        onReceive: () { Navigator.pop(context); _showReceiveForm(po); },
        onSend: () { Navigator.pop(context); _changePOStatus(po, 'sent'); },
        onCancel: () { Navigator.pop(context); _changePOStatus(po, 'cancelled'); },
        onRefresh: _load,
      ),
    );
  }

  // ── Formulario Nueva OC ──────────────────────────────────────────────────
  Future<void> _showPOForm(BuildContext context) async {
    int? supplierId;
    final poNumCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final items = <_POItemDraft>[];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nueva Orden de Compra'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int?>(
                    initialValue: supplierId,
                    decoration: const InputDecoration(labelText: 'Proveedor (opcional)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sin proveedor')),
                      ..._suppliers.map((s) => DropdownMenuItem(
                          value: s['id'] as int, child: Text(s['name'] as String))),
                    ],
                    onChanged: (v) => setD(() => supplierId = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: poNumCtrl,
                    decoration: const InputDecoration(labelText: 'N° de OC (opcional)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notas'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Ítems', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Agregar'),
                        onPressed: () => setD(() => items.add(_POItemDraft())),
                      ),
                    ],
                  ),
                  ...items.asMap().entries.map((e) => _POItemRow(
                        item: e.value,
                        index: e.key,
                        onRemove: () => setD(() => items.removeAt(e.key)),
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final validItems = items.where((i) => i.description.isNotEmpty).toList();
                if (validItems.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('⚠️ Agregá al menos un ítem a la OC')));
                  return;
                }
                final api = Provider.of<AuthProvider>(context, listen: false).apiService;
                try {
                  await api.createPurchaseOrder({
                    if (supplierId != null) 'supplier_id': supplierId,
                    if (poNumCtrl.text.isNotEmpty) 'po_number': poNumCtrl.text,
                    if (notesCtrl.text.isNotEmpty) 'notes': notesCtrl.text,
                    'items': validItems.map((i) => {
                          'description': i.description,
                          'quantity': i.quantity,
                          if (i.unitPrice > 0) 'unit_price': i.unitPrice,
                        }).toList(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Crear OC'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Recibir mercadería ───────────────────────────────────────────────────
  Future<void> _showReceiveForm(Map<String, dynamic> po) async {
    final items = (po['items'] as List? ?? []).cast<Map<String, dynamic>>();
    final qtyControllers = {
      for (var item in items)
        item['id'] as int: TextEditingController(
          text: ((item['quantity'] as num? ?? 0) -
                  (item['quantity_received'] as num? ?? 0))
              .toStringAsFixed(0),
        )
    };

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recibir OC #${po['po_number'] ?? po['id']}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: items.map((item) {
                final pending = (item['quantity'] as num? ?? 0) -
                    (item['quantity_received'] as num? ?? 0);
                if (pending <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['description'] as String? ?? '',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Pend: $pending', style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: qtyControllers[item['id'] as int],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Cant.',
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final api = Provider.of<AuthProvider>(context, listen: false).apiService;
              final receiveItems = qtyControllers.entries
                  .where((e) => (double.tryParse(e.value.text) ?? 0) > 0)
                  .map((e) => {
                        'po_item_id': e.key,
                        'quantity_received': double.tryParse(e.value.text) ?? 0,
                      })
                  .toList();
              if (receiveItems.isEmpty) {
                Navigator.pop(ctx);
                return;
              }
              try {
                await api.receivePurchaseOrder(po['id'] as int, receiveItems);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Confirmar recepción'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePOStatus(Map<String, dynamic> po, String newStatus) async {
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    try {
      await api.updatePOStatus(po['id'] as int, newStatus);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  // ── Formulario Proveedor ─────────────────────────────────────────────────
  Future<void> _showSupplierForm(BuildContext context, {Map<String, dynamic>? supplier}) async {
    final nameCtrl = TextEditingController(text: supplier?['name'] ?? '');
    final contactCtrl = TextEditingController(text: supplier?['contact'] ?? '');
    final emailCtrl = TextEditingController(text: supplier?['email'] ?? '');
    final phoneCtrl = TextEditingController(text: supplier?['phone'] ?? '');
    final addressCtrl = TextEditingController(text: supplier?['address'] ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(supplier == null ? 'Nuevo Proveedor' : 'Editar Proveedor'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre *')),
              const SizedBox(height: 10),
              TextFormField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contacto')),
              const SizedBox(height: 10),
              TextFormField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),
              TextFormField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Teléfono'), keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              TextFormField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Dirección'), maxLines: 2),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              final api = Provider.of<AuthProvider>(context, listen: false).apiService;
              final data = {
                'name': nameCtrl.text.trim(),
                if (contactCtrl.text.isNotEmpty) 'contact': contactCtrl.text.trim(),
                if (emailCtrl.text.isNotEmpty) 'email': emailCtrl.text.trim(),
                if (phoneCtrl.text.isNotEmpty) 'phone': phoneCtrl.text.trim(),
                if (addressCtrl.text.isNotEmpty) 'address': addressCtrl.text.trim(),
              };
              try {
                if (supplier == null) {
                  await api.createSupplier(data);
                } else {
                  await api.updateSupplier(supplier['id'] as int, data);
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

  // ── Formulario Factura ───────────────────────────────────────────────────
  Future<void> _showInvoiceForm(BuildContext context) async {
    int? poId;
    final numCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nueva Factura'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int?>(
                  initialValue: poId,
                  decoration: const InputDecoration(labelText: 'Orden de Compra (opcional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sin OC')),
                    ..._pos.map((p) => DropdownMenuItem(
                        value: p['id'] as int,
                        child: Text('OC #${p['po_number'] ?? p['id']}'))),
                  ],
                  onChanged: (v) => setD(() => poId = v),
                ),
                const SizedBox(height: 10),
                TextFormField(controller: numCtrl, decoration: const InputDecoration(labelText: 'N° de Factura *')),
                const SizedBox(height: 10),
                TextFormField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'Monto *', prefixText: '\$ '),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                TextFormField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notas'), maxLines: 2),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (numCtrl.text.isEmpty || amountCtrl.text.isEmpty) return;
                final api = Provider.of<AuthProvider>(context, listen: false).apiService;
                try {
                  await api.createInvoice({
                    if (poId != null) 'purchase_order_id': poId,
                    'invoice_number': numCtrl.text.trim(),
                    'amount': double.tryParse(amountCtrl.text) ?? 0,
                    if (notesCtrl.text.isNotEmpty) 'notes': notesCtrl.text,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Borrador de ítem de OC ───────────────────────────────────────────────────
class _POItemDraft {
  String description = '';
  double quantity = 1;
  double unitPrice = 0;
}

class _POItemRow extends StatefulWidget {
  final _POItemDraft item;
  final int index;
  final VoidCallback onRemove;
  const _POItemRow({required this.item, required this.index, required this.onRemove});
  @override
  State<_POItemRow> createState() => _POItemRowState();
}

class _POItemRowState extends State<_POItemRow> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.item.description);
    _qtyCtrl = TextEditingController(text: '${widget.item.quantity.toInt()}');
    _priceCtrl = TextEditingController(text: widget.item.unitPrice > 0 ? '${widget.item.unitPrice}' : '');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción *', isDense: true),
                  onChanged: (v) => widget.item.description = v,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Cant.', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => widget.item.quantity = double.tryParse(v) ?? 1,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _priceCtrl,
                  decoration: const InputDecoration(labelText: 'P. Unit.', isDense: true, prefixText: '\$'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => widget.item.unitPrice = double.tryParse(v) ?? 0,
                ),
              ),
              IconButton(icon: const Icon(Icons.delete_outline, color: BsaTheme.error), onPressed: widget.onRemove),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─── Tab Órdenes de Compra ────────────────────────────────────────────────────
class _POTab extends StatelessWidget {
  final List<Map<String, dynamic>> pos;
  final List<Map<String, dynamic>> allPos;
  final String filterStatus;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onRefresh;
  final Function(Map<String, dynamic>) onReceive;
  final Function(Map<String, dynamic>, String) onChangeStatus;
  final Function(Map<String, dynamic>) onShowDetail;
  final AuthProvider auth;
  final bool canEdit;

  const _POTab({
    required this.pos, required this.allPos, required this.filterStatus,
    required this.onFilterChanged, required this.onRefresh,
    required this.onReceive, required this.onChangeStatus,
    required this.onShowDetail, required this.auth,
    required this.canEdit,
  });

  static const _filters = [
    ('all', 'Todas'), ('draft', 'Borrador'), ('sent', 'Enviadas'),
    ('partially_received', 'Parcial'), ('received', 'Recibidas'), ('cancelled', 'Canceladas'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filtros
        Container(
          color: Colors.white,
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: _filters.map((f) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(f.$2, style: TextStyle(fontSize: 12, color: filterStatus == f.$1 ? Colors.white : BsaTheme.textPrimary)),
                selected: filterStatus == f.$1,
                onSelected: (_) => onFilterChanged(f.$1),
                selectedColor: BsaTheme.primary,
                backgroundColor: BsaTheme.background,
                showCheckmark: false,
              ),
            )).toList(),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => onRefresh(),
            child: pos.isEmpty
                ? const Center(child: Text('No hay órdenes de compra'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: pos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _POCard(
                      po: pos[i], auth: auth,
                      onTap: () => onShowDetail(pos[i]),
                      onReceive: () => onReceive(pos[i]),
                      onSend: () => onChangeStatus(pos[i], 'sent'),
                      onCancel: () => onChangeStatus(pos[i], 'cancelled'),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _POCard extends StatelessWidget {
  final Map<String, dynamic> po;
  final AuthProvider auth;
  final VoidCallback onTap;
  final VoidCallback onReceive;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const _POCard({required this.po, required this.auth, required this.onTap,
      required this.onReceive, required this.onSend, required this.onCancel});

  Color _statusColor(String s) {
    switch (s) {
      case 'draft': return BsaTheme.textSecondary;
      case 'sent': return BsaTheme.primary;
      case 'partially_received': return BsaTheme.warning;
      case 'received': return BsaTheme.secondary;
      case 'cancelled': return BsaTheme.error;
      default: return BsaTheme.textSecondary;
    }
  }

  String _statusLabel(String s) => const {
    'draft': 'Borrador', 'sent': 'Enviada',
    'partially_received': 'Recibida Parcial', 'received': 'Recibida', 'cancelled': 'Cancelada',
  }[s] ?? s;

  @override
  Widget build(BuildContext context) {
    final status = po['status'] as String? ?? '';
    final color = _statusColor(status);
    final items = (po['items'] as List? ?? []);
    final total = po['total_amount'];
    final canReceive = auth.hasAnyRole(['admin', 'warehouse', 'purchasing']) &&
        (status == 'sent' || status == 'partially_received');
    final canSend = auth.hasAnyRole(['admin', 'purchasing']) && status == 'draft';

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('OC #${po['po_number'] ?? po['id']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: BsaTheme.textPrimary)),
                if (po['supplier_name'] != null)
                  Text(po['supplier_name'] as String, style: const TextStyle(fontSize: 13, color: BsaTheme.textSecondary)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              '${items.length} ítem${items.length != 1 ? 's' : ''}${total != null ? '  •  \$ ${(total as num).toStringAsFixed(2)}' : ''}',
              style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
            Text('Creado: ${(po['created_at'] as String? ?? '').length >= 10 ? (po['created_at'] as String).substring(0, 10) : ''}',
                style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
            // Vista previa de ítems
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...items.take(3).map((item) {
                final it = item as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(children: [
                    const Icon(Icons.circle, size: 5, color: BsaTheme.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(it['description'] as String? ?? '',
                        style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary),
                        overflow: TextOverflow.ellipsis)),
                    Text('x${(it['quantity'] as num?)?.toStringAsFixed(0) ?? '?'}',
                        style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
                  ]),
                );
              }),
              if (items.length > 3)
                Text('... y ${items.length - 3} más',
                    style: const TextStyle(fontSize: 11, color: BsaTheme.textSecondary)),
            ],
            if (canSend || canReceive) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(children: [
                if (canSend)
                  OutlinedButton.icon(
                    onPressed: onSend,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Enviar'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32)),
                  ),
                const SizedBox(width: 8),
                if (canReceive)
                  ElevatedButton.icon(
                    onPressed: onReceive,
                    icon: const Icon(Icons.move_to_inbox_rounded, size: 16),
                    label: const Text('Recibir'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      backgroundColor: BsaTheme.secondary,
                    ),
                  ),
                const Spacer(),
                Text('Toca para ver detalle',
                    style: TextStyle(fontSize: 11, color: BsaTheme.textSecondary.withValues(alpha: 0.6))),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─── Tab Proveedores ──────────────────────────────────────────────────────────
class _SuppliersTab extends StatefulWidget {
  final List<Map<String, dynamic>> suppliers;
  final VoidCallback onRefresh;
  final AuthProvider auth;
  final Function(Map<String, dynamic>) onEdit;
  final bool canEdit;

  const _SuppliersTab({required this.suppliers, required this.onRefresh,
      required this.auth, required this.onEdit, required this.canEdit});

  @override
  State<_SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends State<_SuppliersTab> {
  String _search = '';

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return widget.suppliers;
    final q = _search.toLowerCase();
    return widget.suppliers.where((s) =>
        (s['name'] as String? ?? '').toLowerCase().contains(q) ||
        (s['email'] as String? ?? '').toLowerCase().contains(q) ||
        (s['contact'] as String? ?? '').toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Buscar proveedor...',
              prefixIcon: const Icon(Icons.search, size: 20),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: BsaTheme.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: BsaTheme.border)),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => widget.onRefresh(),
            child: _filtered.isEmpty
                ? const Center(child: Text('No hay proveedores'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final s = _filtered[i];
                      final isActive = s['notes'] != null
                          ? !(s['notes'] as String).startsWith('[INACTIVO]')
                          : true;
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showDetail(context, s),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: isActive
                                    ? BsaTheme.primary.withValues(alpha: 0.1)
                                    : Colors.grey.withValues(alpha: 0.1),
                                child: Text(
                                  (s['name'] as String? ?? 'P')[0].toUpperCase(),
                                  style: TextStyle(
                                    color: isActive ? BsaTheme.primary : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(s['name'] as String? ?? '',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                                          color: isActive ? BsaTheme.textPrimary : Colors.grey))),
                                  if (!isActive) Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10)),
                                    child: const Text('Inactivo', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  ),
                                ]),
                                if (s['contact'] != null)
                                  Text(s['contact'] as String, style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
                                Wrap(spacing: 8, children: [
                                  if (s['email'] != null)
                                    _InfoBadge(icon: Icons.email_outlined, text: s['email'] as String),
                                  if (s['phone'] != null)
                                    _InfoBadge(icon: Icons.phone_outlined, text: s['phone'] as String),
                                ]),
                              ])),
                              if (widget.auth.hasAnyRole(['admin', 'purchasing', 'maintenance_manager']))
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 18),
                                  onSelected: (v) {
                                    if (v == 'edit') widget.onEdit(s);
                                    if (v == 'toggle') _toggleActive(context, s);
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'edit', child: Row(children: [
                                      Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('Editar')])),
                                    PopupMenuItem(value: 'toggle', child: Row(children: [
                                      Icon(isActive ? Icons.block_rounded : Icons.check_circle_outline,
                                          size: 16, color: isActive ? BsaTheme.error : BsaTheme.secondary),
                                      const SizedBox(width: 8),
                                      Text(isActive ? 'Dar de baja' : 'Activar',
                                          style: TextStyle(color: isActive ? BsaTheme.error : BsaTheme.secondary)),
                                    ])),
                                  ],
                                ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupplierDetailSheet(supplier: s),
    );
  }

  Future<void> _toggleActive(BuildContext context, Map<String, dynamic> s) async {
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    final currentNotes = s['notes'] as String? ?? '';
    final isActive = !currentNotes.startsWith('[INACTIVO]');
    final newNotes = isActive
        ? '[INACTIVO] $currentNotes'.trim()
        : currentNotes.replaceFirst('[INACTIVO] ', '').replaceFirst('[INACTIVO]', '').trim();
    try {
      await api.updateSupplier(s['id'] as int, {'notes': newNotes});
      widget.onRefresh();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

// ─── Tab Facturas ─────────────────────────────────────────────────────────────
class _InvoicesTab extends StatefulWidget {
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>> pos;
  final VoidCallback onRefresh;
  final AuthProvider auth;
  final bool canEdit;

  const _InvoicesTab({required this.invoices, required this.pos,
      required this.onRefresh, required this.auth, required this.canEdit});

  @override
  State<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends State<_InvoicesTab> {
  String _filterStatus = 'all';

  List<Map<String, dynamic>> get _filtered {
    if (_filterStatus == 'all') return widget.invoices;
    return widget.invoices.where((i) => i['status'] == _filterStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              ('all', 'Todas'), ('pending', 'Pendientes'), ('paid', 'Pagadas'),
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
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => widget.onRefresh(),
            child: _filtered.isEmpty
                ? const Center(child: Text('No hay facturas'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final inv = _filtered[i];
                      final status = inv['status'] as String? ?? '';
                      final isPending = status == 'pending';
                      final statusColor = isPending ? BsaTheme.warning : BsaTheme.secondary;

                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showInvoiceDetail(context, inv),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10)),
                                child: Icon(Icons.receipt_long_rounded, color: statusColor, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Factura #${inv['invoice_number']}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: BsaTheme.textPrimary)),
                                Text(
                                  '\$ ${(inv['amount'] as num? ?? 0).toStringAsFixed(2)}'
                                  '${inv['po_number'] != null ? ' · OC #${inv['po_number']}' : ''}',
                                  style: const TextStyle(fontSize: 13, color: BsaTheme.textSecondary)),
                                if (inv['due_date'] != null)
                                  Text('Vence: ${(inv['due_date'] as String).substring(0, 10)}',
                                      style: TextStyle(fontSize: 12,
                                          color: isPending ? BsaTheme.warning : BsaTheme.textSecondary)),
                              ])),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10)),
                                  child: Text(isPending ? 'Pendiente' : 'Pagada',
                                      style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
                                ),
                                if (isPending && widget.auth.hasAnyRole(['admin', 'purchasing']))
                                  TextButton(
                                    onPressed: () async {
                                      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
                                      await api.payInvoice(inv['id'] as int);
                                      widget.onRefresh();
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: BsaTheme.secondary,
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 28),
                                    ),
                                    child: const Text('Marcar pagada', style: TextStyle(fontSize: 12)),
                                  ),
                              ]),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  void _showInvoiceDetail(BuildContext context, Map<String, dynamic> inv) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _InvoiceDetailSheet(invoice: inv),
    );
  }
}

// ─── Sheet Detalle OC ─────────────────────────────────────────────────────────
class _PODetailSheet extends StatelessWidget {
  final Map<String, dynamic> po;
  final AuthProvider auth;
  final VoidCallback onReceive;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onRefresh;

  const _PODetailSheet({required this.po, required this.auth, required this.onReceive,
      required this.onSend, required this.onCancel, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final status = po['status'] as String? ?? '';
    final items = (po['items'] as List? ?? []).cast<Map<String, dynamic>>();
    final total = po['total_amount'];
    final canReceive = auth.hasAnyRole(['admin', 'warehouse', 'purchasing']) &&
        (status == 'sent' || status == 'partially_received');
    final canSend = auth.hasAnyRole(['admin', 'purchasing']) && status == 'draft';
    final canCancel = auth.hasAnyRole(['admin', 'purchasing']) &&
        (status == 'draft' || status == 'sent');

    Color statusColor(String s) => const {
      'draft': BsaTheme.textSecondary, 'sent': BsaTheme.primary,
      'partially_received': BsaTheme.warning, 'received': BsaTheme.secondary,
      'cancelled': BsaTheme.error,
    }[s] ?? BsaTheme.textSecondary;

    String statusLabel(String s) => const {
      'draft': 'Borrador', 'sent': 'Enviada',
      'partially_received': 'Recibida parcial', 'received': 'Recibida', 'cancelled': 'Cancelada',
    }[s] ?? s;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Center(child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(color: BsaTheme.border, borderRadius: BorderRadius.circular(2)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('OC #${po['po_number'] ?? po['id']}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: BsaTheme.textPrimary)),
                if (po['supplier_name'] != null)
                  Text(po['supplier_name'] as String,
                      style: const TextStyle(fontSize: 14, color: BsaTheme.textSecondary)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor(status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20)),
                child: Text(statusLabel(status),
                    style: TextStyle(color: statusColor(status), fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          if (po['notes'] != null && (po['notes'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: BsaTheme.background, borderRadius: BorderRadius.circular(8)),
                child: Text(po['notes'] as String,
                    style: const TextStyle(fontSize: 13, color: BsaTheme.textSecondary)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Ítems (${items.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: BsaTheme.textPrimary)),
              if (total != null)
                Text('Total: \$ ${(total as num).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: BsaTheme.primary)),
            ]),
          ),
          const Divider(height: 1, indent: 20, endIndent: 20),
          Expanded(
            child: ListView.separated(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final it = items[i];
                final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
                final received = (it['quantity_received'] as num?)?.toDouble() ?? 0;
                final pending = qty - received;
                final unitPrice = (it['unit_price'] as num?);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it['description'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: BsaTheme.textPrimary)),
                      if (it['spare_part_name'] != null)
                        Text('Repuesto: ${it['spare_part_name']}',
                            style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
                    ])),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Cant: $qty',
                          style: const TextStyle(fontSize: 13, color: BsaTheme.textPrimary)),
                      if (received > 0)
                        Text('Recibido: $received',
                            style: const TextStyle(fontSize: 12, color: BsaTheme.secondary)),
                      if (pending > 0)
                        Text('Pendiente: $pending',
                            style: const TextStyle(fontSize: 12, color: BsaTheme.warning)),
                      if (unitPrice != null)
                        Text('\$ ${unitPrice.toStringAsFixed(2)} c/u',
                            style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
                    ]),
                  ]),
                );
              },
            ),
          ),
          if (canSend || canReceive || canCancel)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: BsaTheme.border))),
              child: Wrap(spacing: 10, runSpacing: 8, children: [
                if (canSend)
                  OutlinedButton.icon(
                    onPressed: onSend,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Enviar al proveedor')),
                if (canReceive)
                  ElevatedButton.icon(
                    onPressed: onReceive,
                    icon: const Icon(Icons.move_to_inbox_rounded, size: 16),
                    label: const Text('Recibir mercadería'),
                    style: ElevatedButton.styleFrom(backgroundColor: BsaTheme.secondary)),
                if (canCancel)
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancelar OC'),
                    style: OutlinedButton.styleFrom(foregroundColor: BsaTheme.error,
                        side: const BorderSide(color: BsaTheme.error))),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ─── Sheet Detalle Proveedor ──────────────────────────────────────────────────
class _SupplierDetailSheet extends StatelessWidget {
  final Map<String, dynamic> supplier;
  const _SupplierDetailSheet({required this.supplier});

  @override
  Widget build(BuildContext context) {
    final s = supplier;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          width: 40, height: 4,
          decoration: BoxDecoration(color: BsaTheme.border, borderRadius: BorderRadius.circular(2)))),
        Row(children: [
          CircleAvatar(radius: 28, backgroundColor: BsaTheme.primary.withValues(alpha: 0.1),
            child: Text((s['name'] as String? ?? 'P')[0].toUpperCase(),
                style: const TextStyle(fontSize: 22, color: BsaTheme.primary, fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          Expanded(child: Text(s['name'] as String? ?? '',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: BsaTheme.textPrimary))),
        ]),
        const SizedBox(height: 20),
        if (s['contact'] != null) _DetailRow(icon: Icons.person_outline, label: 'Contacto', value: s['contact']),
        if (s['email'] != null) _DetailRow(icon: Icons.email_outlined, label: 'Email', value: s['email']),
        if (s['phone'] != null) _DetailRow(icon: Icons.phone_outlined, label: 'Teléfono', value: s['phone']),
        if (s['address'] != null) _DetailRow(icon: Icons.location_on_outlined, label: 'Dirección', value: s['address']),
        if (s['notes'] != null && (s['notes'] as String).isNotEmpty &&
            !(s['notes'] as String).startsWith('[INACTIVO]'))
          _DetailRow(icon: Icons.notes_rounded, label: 'Notas', value: s['notes']),
        const SizedBox(height: 16),
      ]),
    );
  }
}

// ─── Sheet Detalle Factura ────────────────────────────────────────────────────
class _InvoiceDetailSheet extends StatelessWidget {
  final Map<String, dynamic> invoice;
  const _InvoiceDetailSheet({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final isPending = inv['status'] == 'pending';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          width: 40, height: 4,
          decoration: BoxDecoration(color: BsaTheme.border, borderRadius: BorderRadius.circular(2)))),
        Row(children: [
          Container(width: 52, height: 52,
            decoration: BoxDecoration(
              color: (isPending ? BsaTheme.warning : BsaTheme.secondary).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.receipt_long_rounded,
                color: isPending ? BsaTheme.warning : BsaTheme.secondary, size: 28)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Factura #${inv['invoice_number']}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: BsaTheme.textPrimary)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isPending ? BsaTheme.warning : BsaTheme.secondary).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Text(isPending ? 'Pendiente de pago' : 'Pagada',
                  style: TextStyle(
                    color: isPending ? BsaTheme.warning : BsaTheme.secondary,
                    fontSize: 12, fontWeight: FontWeight.w600))),
          ])),
        ]),
        const SizedBox(height: 20),
        _DetailRow(icon: Icons.attach_money_rounded, label: 'Monto',
            value: '\$ ${(inv['amount'] as num? ?? 0).toStringAsFixed(2)}'),
        if (inv['po_number'] != null)
          _DetailRow(icon: Icons.shopping_cart_rounded, label: 'Orden de Compra',
              value: 'OC #${inv['po_number']}'),
        if (inv['due_date'] != null)
          _DetailRow(icon: Icons.calendar_today_rounded, label: 'Vencimiento',
              value: (inv['due_date'] as String).substring(0, 10)),
        if (inv['paid_at'] != null)
          _DetailRow(icon: Icons.check_circle_outline, label: 'Fecha de pago',
              value: (inv['paid_at'] as String).substring(0, 10)),
        if (inv['notes'] != null && (inv['notes'] as String).isNotEmpty)
          _DetailRow(icon: Icons.notes_rounded, label: 'Notas', value: inv['notes']),
        const SizedBox(height: 16),
      ]),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final dynamic value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: BsaTheme.textSecondary),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: BsaTheme.textSecondary,
              fontWeight: FontWeight.w600)),
          Text('$value', style: const TextStyle(fontSize: 14, color: BsaTheme.textPrimary)),
        ])),
      ]),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: BsaTheme.textSecondary),
      const SizedBox(width: 3),
      Text(text, style: const TextStyle(fontSize: 11, color: BsaTheme.textSecondary)),
    ]);
  }
}
