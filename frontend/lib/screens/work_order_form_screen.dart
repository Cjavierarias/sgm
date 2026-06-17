import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class WorkOrderFormScreen extends StatefulWidget {
  const WorkOrderFormScreen({super.key});
  @override
  State<WorkOrderFormScreen> createState() => _WorkOrderFormScreenState();
}

class _WorkOrderFormScreenState extends State<WorkOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  String _priority = 'medium';
  String _type = 'corrective';
  int? _equipmentId;
  int? _assignedToId;
  DateTime? _dueDate;
  List<Map<String, dynamic>> _equipments = [];
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final eq = await auth.apiService.getEquipments();
      final us = await auth.apiService.getUsers();
      if (mounted) setState(() { _equipments = eq; _users = us; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.apiService.createWorkOrder({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'priority': _priority,
        'wo_type': _type,
        if (_equipmentId != null) 'equipment_id': _equipmentId,
        if (_assignedToId != null) 'assigned_to_id': _assignedToId,
        if (_dueDate != null) 'due_date': _dueDate!.toIso8601String(),
        if (_hoursCtrl.text.isNotEmpty)
          'estimated_hours': double.tryParse(_hoursCtrl.text),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva OT')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                              controller: _titleCtrl,
                              decoration: const InputDecoration(labelText: 'Título *'),
                              validator: (v) => v!.isEmpty ? 'Requerido' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _descCtrl,
                              decoration: const InputDecoration(labelText: 'Descripción'),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _priority,
                              decoration: const InputDecoration(labelText: 'Prioridad'),
                              items: const [
                                DropdownMenuItem(value: 'low', child: Text('Baja')),
                                DropdownMenuItem(value: 'medium', child: Text('Media')),
                                DropdownMenuItem(value: 'high', child: Text('Alta')),
                                DropdownMenuItem(value: 'critical', child: Text('Crítica')),
                              ],
                              onChanged: (v) => setState(() => _priority = v!),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _type,
                              decoration: const InputDecoration(labelText: 'Tipo'),
                              items: const [
                                DropdownMenuItem(value: 'corrective', child: Text('Correctivo')),
                                DropdownMenuItem(value: 'preventive', child: Text('Preventivo')),
                                DropdownMenuItem(value: 'predictive', child: Text('Predictivo')),
                              ],
                              onChanged: (v) => setState(() => _type = v!),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int?>(
                              value: _equipmentId,
                              decoration: const InputDecoration(labelText: 'Equipo (opcional)'),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Sin equipo')),
                                ..._equipments.map((e) => DropdownMenuItem(
                                    value: e['id'] as int,
                                    child: Text(e['name'] as String? ?? ''))),
                              ],
                              onChanged: (v) => setState(() => _equipmentId = v),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int?>(
                              value: _assignedToId,
                              decoration: const InputDecoration(labelText: 'Asignar a (opcional)'),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Sin asignar')),
                                ..._users.map((u) => DropdownMenuItem(
                                    value: u['id'] as int,
                                    child: Text(u['full_name'] as String? ?? u['email'] as String? ?? ''))),
                              ],
                              onChanged: (v) => setState(() => _assignedToId = v),
                            ),
                            const SizedBox(height: 12),
                            // Fecha límite
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 7)),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (picked != null) setState(() => _dueDate = picked);
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Fecha límite (opcional)',
                                  suffixIcon: Icon(Icons.calendar_today),
                                ),
                                child: Text(
                                  _dueDate != null
                                      ? '${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}'
                                      : 'Seleccionar fecha',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _hoursCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Horas estimadas (opcional)',
                                suffixText: 'hs',
                              ),
                              keyboardType: TextInputType.number,
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
                            child: const Text('Crear Orden de Trabajo'),
                          ),
                  ],
                ),
              ),
            ),
    );
  }
}
