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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text(_part != null ? _part!['name'] as String : 'Repuesto'),
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
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.green.withOpacity(0.1),
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
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
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

// ─── FORMULARIO NUEVO REPUESTO ────────────────────────────────────────────────

class SparePartFormScreen extends StatefulWidget {
  const SparePartFormScreen({super.key});
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
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_codeCtrl, _nameCtrl, _descCtrl, _unitCtrl,
        _stockCtrl, _minStockCtrl, _locationCtrl, _costCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.apiService.createSparePart({
        'code': _codeCtrl.text.trim(),
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'unit': _unitCtrl.text.trim(),
        'stock': double.tryParse(_stockCtrl.text) ?? 0,
        'min_stock': double.tryParse(_minStockCtrl.text) ?? 0,
        'location': _locationCtrl.text.trim(),
        if (_costCtrl.text.isNotEmpty)
          'unit_cost': double.tryParse(_costCtrl.text),
      });
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
      appBar: AppBar(title: const Text('Nuevo Repuesto')),
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
                          Expanded(
                            child: TextFormField(
                              controller: _stockCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Stock inicial'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
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
                      TextFormField(
                        controller: _locationCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Ubicación en depósito',
                            hintText: 'Ej: Estante A-3'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _saving
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _save,
                      child: const Text('Guardar Repuesto'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
