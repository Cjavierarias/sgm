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
                  auth: auth,
                ),
                _SuppliersTab(
                  suppliers: _suppliers,
                  onRefresh: _load,
                  auth: auth,
                  onEdit: (s) => _showSupplierForm(context, supplier: s),
                ),
                _InvoicesTab(
                  invoices: _invoices,
                  pos: _pos,
                  onRefresh: _load,
                  auth: auth,
                ),
              ],
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
                    value: supplierId,
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
                final api = Provider.of<AuthProvider>(context, listen: false).apiService;
                try {
                  await api.createPurchaseOrder({
                    if (supplierId != null) 'supplier_id': supplierId,
                    if (poNumCtrl.text.isNotEmpty) 'po_number': poNumCtrl.text,
                    if (notesCtrl.text.isNotEmpty) 'notes': notesCtrl.text,
                    'items': items
                        .where((i) => i.description.isNotEmpty)
                        .map((i) => {
                              'description': i.description,
                              'quantity': i.quantity,
                              if (i.unitPrice > 0) 'unit_price': i.unitPrice,
                            })
                        .toList(),
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
                  value: poId,
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
  final AuthProvider auth;

  const _POTab({
    required this.pos, required this.allPos, required this.filterStatus,
    required this.onFilterChanged, required this.onRefresh,
    required this.onReceive, required this.onChangeStatus, required this.auth,
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
  final VoidCallback onReceive;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const _POCard({required this.po, required this.auth, required this.onReceive, required this.onSend, required this.onCancel});

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
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          Text('${items.length} ítem${items.length != 1 ? 's' : ''}${total != null ? '  •  \$ ${total.toStringAsFixed(2)}' : ''}',
              style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
          Text('Creado: ${(po['created_at'] as String? ?? '').length >= 10 ? (po['created_at'] as String).substring(0, 10) : ''}',
              style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
          if (canSend || canReceive) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(children: [
              if (canSend)
                OutlinedButton.icon(
                  onPressed: onSend,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Enviar al proveedor'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32)),
                ),
              const SizedBox(width: 8),
              if (canReceive)
                ElevatedButton.icon(
                  onPressed: onReceive,
                  icon: const Icon(Icons.move_to_inbox_rounded, size: 16),
                  label: const Text('Recibir mercadería'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    backgroundColor: BsaTheme.secondary,
                  ),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ─── Tab Proveedores ──────────────────────────────────────────────────────────
class _SuppliersTab extends StatelessWidget {
  final List<Map<String, dynamic>> suppliers;
  final VoidCallback onRefresh;
  final AuthProvider auth;
  final Function(Map<String, dynamic>) onEdit;

  const _SuppliersTab({required this.suppliers, required this.onRefresh, required this.auth, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: suppliers.isEmpty
          ? const Center(child: Text('No hay proveedores registrados'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: suppliers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final s = suppliers[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: BsaTheme.primary.withOpacity(0.1),
                      child: Text(
                        (s['name'] as String? ?? 'P')[0].toUpperCase(),
                        style: const TextStyle(color: BsaTheme.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(s['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      if (s['contact'] != null) s['contact'],
                      if (s['email'] != null) s['email'],
                      if (s['phone'] != null) s['phone'],
                    ].join(' • '), style: const TextStyle(fontSize: 12)),
                    trailing: auth.hasAnyRole(['admin', 'purchasing', 'maintenance_manager'])
                        ? IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => onEdit(s),
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }
}

// ─── Tab Facturas ─────────────────────────────────────────────────────────────
class _InvoicesTab extends StatelessWidget {
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>> pos;
  final VoidCallback onRefresh;
  final AuthProvider auth;

  const _InvoicesTab({required this.invoices, required this.pos, required this.onRefresh, required this.auth});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: invoices.isEmpty
          ? const Center(child: Text('No hay facturas registradas'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: invoices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final inv = invoices[i];
                final status = inv['status'] as String? ?? '';
                final isPending = status == 'pending';
                final statusColor = isPending ? BsaTheme.warning : BsaTheme.secondary;

                return Card(
                  child: ListTile(
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.receipt_long_rounded, color: statusColor, size: 20),
                    ),
                    title: Text('Factura #${inv['invoice_number']}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(
                      [
                        '\$ ${(inv['amount'] as num? ?? 0).toStringAsFixed(2)}',
                        if (inv['po_number'] != null) 'OC #${inv['po_number']}',
                        if (inv['due_date'] != null)
                          'Vence: ${(inv['due_date'] as String).substring(0, 10)}',
                      ].join(' • '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isPending ? 'Pendiente' : 'Pagada',
                          style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isPending && auth.hasAnyRole(['admin', 'purchasing'])) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline, color: BsaTheme.secondary, size: 20),
                          tooltip: 'Marcar como pagada',
                          onPressed: () async {
                            final api = Provider.of<AuthProvider>(context, listen: false).apiService;
                            await api.payInvoice(inv['id'] as int);
                            onRefresh();
                          },
                        ),
                      ],
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
