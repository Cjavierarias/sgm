// ─── DETALLE DE REPUESTO ─────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class SparePartDetailScreen extends StatefulWidget {
  final int partId;
  const SparePartDetailScreen({super.key, required this.partId});
  @override
  State<SparePartDetailScreen> createState() => _SparePartDetailScreenState();
}

class _SparePartDetailScreenState extends State<SparePartDetailScreen> {
  Map<String, dynamic>? _part;
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
      final data = await auth.apiService.getSparePart(widget.partId);
      if (mounted) setState(() { _part = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteSparePart() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Repuesto'),
        content: Text('¿Eliminar "${_part?['name']}" definitivamente?\n\nSe eliminarán también todos los movimientos y pedidos asociados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.apiService.deleteSparePart(widget.partId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editSparePart() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SparePartFormScreen(part: _part),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canEdit = auth.hasAnyRole(['admin', 'warehouse', 'maintenance_manager']);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text(_part != null ? _part!['name'] as String : 'Repuesto'),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editSparePart,
            ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSparePart,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _part == null
              ? const Center(child: Text('Repuesto no encontrado'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StockCard(part: _part!),
                      const SizedBox(height: 16),
                      _InfoCard(part: _part!),
                      const SizedBox(height: 16),
                      _MovementsCard(
                          movements: (_part!['movements'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              []),
                    ],
                  ),
                ),
    );
  }
}

class _StockCard extends StatelessWidget {
  final Map<String, dynamic> part;
  const _StockCard({required this.part});

  @override
  Widget build(BuildContext context) {
    final stock = (part['stock'] as num?)?.toDouble() ?? 0;
    final minStock = (part['min_stock'] as num?)?.toDouble() ?? 0;
    final isLow = part['is_low_stock'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isLow
                    ? Colors.orange.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isLow ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                color: isLow ? Colors.orange : Colors.green,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$stock ${part['unit'] ?? ''}',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isLow ? Colors.orange : Colors.green,
                  ),
                ),
                Text(
                  isLow ? 'STOCK BAJO (mín: $minStock)' : 'Stock disponible',
                  style: TextStyle(
                    fontSize: 13,
                    color: isLow ? Colors.orange : Colors.grey[600],
                    fontWeight: isLow ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Map<String, dynamic> part;
  const _InfoCard({required this.part});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Información',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            _Row('Código', part['code'] as String? ?? ''),
            _Row('Ubicación', part['location'] as String? ?? 'Sin ubicación'),
            if (part['sector'] != null)
              _Row('Sector', part['sector'] as String),
            if (part['equipment_name'] != null)
              _Row('Equipo asociado', part['equipment_name'] as String),
            if (part['description'] != null)
              _Row('Descripción', part['description'] as String),
            if (part['unit_cost'] != null)
              _Row('Costo unitario', '\$${part['unit_cost']}'),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _MovementsCard extends StatelessWidget {
  final List<Map<String, dynamic>> movements;
  const _MovementsCard({required this.movements});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Historial de movimientos (${movements.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            if (movements.isEmpty)
              Text('Sin movimientos registrados',
                  style: TextStyle(color: Colors.grey[600]))
            else
              ...movements.map((m) {
                final isEntry = m['movement_type'] == 'entry';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isEntry
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isEntry ? Icons.add_rounded : Icons.remove_rounded,
                          color: isEntry ? Colors.green : Colors.red,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${isEntry ? '+' : '-'}${m['quantity']} · ${m['user_name'] ?? ''}',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isEntry ? Colors.green : Colors.red),
                            ),
                            if (m['notes'] != null)
                              Text(m['notes'] as String,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      Text(
                        (m['created_at'] as String? ?? '').length >= 10
                            ? (m['created_at'] as String).substring(0, 10)
                            : '',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ─── FORMULARIO NUEVO/EDITAR REPUESTO ────────────────────────────────────────

class SparePartFormScreen extends StatefulWidget {
  final Map<String, dynamic>? part; // null = crear, != null = editar
  const SparePartFormScreen({super.key, this.part});
  @override
  State<SparePartFormScreen> createState() => _SparePartFormScreenState();
}

class _SparePartFormScreenState extends State<SparePartFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'unidad');
  final _stockCtrl = TextEditingController(text: '0');
  final _minStockCtrl = TextEditingController(text: '0');
  final _locationCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _sectorCtrl = TextEditingController();
  List<Map<String, dynamic>> _equipments = [];
  int? _equipmentId;
  bool _saving = false;
  bool _isEdit = false;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.part != null;
    if (_isEdit) {
      final p = widget.part!;
      _codeCtrl.text = p['code'] as String? ?? '';
      _nameCtrl.text = p['name'] as String? ?? '';
      _descCtrl.text = p['description'] as String? ?? '';
      _unitCtrl.text = p['unit'] as String? ?? 'unidad';
      _stockCtrl.text = ((p['stock'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
      _minStockCtrl.text = ((p['min_stock'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
      _locationCtrl.text = p['location'] as String? ?? '';
      _costCtrl.text = (p['unit_cost'] as num?)?.toString() ?? '';
      _sectorCtrl.text = p['sector'] as String? ?? '';
      _equipmentId = p['equipment_id'] as int?;
    }
    _loadEquipments();
  }

  Future<void> _loadEquipments() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      _equipments = await auth.apiService.getEquipments();
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_codeCtrl, _nameCtrl, _descCtrl, _unitCtrl,
        _stockCtrl, _minStockCtrl, _locationCtrl, _costCtrl, _sectorCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final data = {
        'code': _codeCtrl.text.trim(),
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'unit': _unitCtrl.text.trim(),
        'min_stock': double.tryParse(_minStockCtrl.text) ?? 0,
        'location': _locationCtrl.text.trim(),
        'sector': _sectorCtrl.text.trim(),
        if (_equipmentId != null) 'equipment_id': _equipmentId,
        if (_costCtrl.text.isNotEmpty)
          'unit_cost': double.tryParse(_costCtrl.text),
      };
      if (_isEdit) {
        await auth.apiService.updateSparePart(widget.part!['id'] as int, data);
      } else {
        data['stock'] = double.tryParse(_stockCtrl.text) ?? 0;
        await auth.apiService.createSparePart(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Editar Repuesto' : 'Nuevo Repuesto')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _codeCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Código *',
                            hintText: 'Ej: REP-001'),
                        validator: (v) => v!.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Nombre *',
                            hintText: 'Ej: Filtro de aceite'),
                        validator: (v) => v!.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Descripción'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _unitCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Unidad',
                                  hintText: 'unidad, litro, kg...'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _costCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Costo unitario'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (!_isEdit)
                            Expanded(
                              child: TextFormField(
                                controller: _stockCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Stock inicial'),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          if (_isEdit) const SizedBox(width: 0),
                          if (!_isEdit) const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _minStockCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Stock mínimo'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _locationCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Ubicación en depósito',
                                  hintText: 'Ej: Estante A-3'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _sectorCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Sector',
                                  hintText: 'mecánica, eléctrica...'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        initialValue: _equipmentId,
                        decoration: const InputDecoration(
                            labelText: 'Equipo asociado (opcional)'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Sin equipo')),
                          ..._equipments.map((e) => DropdownMenuItem(
                              value: e['id'] as int,
                              child: Text(e['name'] as String))),
                        ],
                        onChanged: (v) => setState(() => _equipmentId = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_isEdit ? 'Guardar Cambios' : 'Crear Repuesto'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
