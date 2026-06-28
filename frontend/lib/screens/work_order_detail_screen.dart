import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';

class WorkOrderDetailScreen extends StatefulWidget {
  final int woId;
  const WorkOrderDetailScreen({super.key, required this.woId});
  @override
  State<WorkOrderDetailScreen> createState() => _WorkOrderDetailScreenState();
}

class _WorkOrderDetailScreenState extends State<WorkOrderDetailScreen> {
  Map<String, dynamic>? _wo;
  bool _loading = true;
  final _commentCtrl = TextEditingController();
  bool _sendingComment = false;
  List<Map<String, dynamic>> _spareParts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final woData = await auth.apiService.getWorkOrder(widget.woId);
      // Cargar repuestos por separado — si falla no debe bloquear la OT
      List<Map<String, dynamic>> parts = [];
      try {
        parts = await auth.apiService.getSpareParts();
      } catch (_) {
        // Si falla la carga de repuestos, simplemente no mostramos el botón
      }
      if (mounted) {
        setState(() {
          _wo = woData;
          _spareParts = parts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeStatus(String newStatus) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await auth.apiService.updateWorkOrderStatus(widget.woId, newStatus);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sendingComment = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.apiService.addWorkOrderComment(widget.woId, text);
      _commentCtrl.clear();
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _showRequestPartForm() async {
    if (_spareParts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No hay repuestos disponibles para solicitar')));
      }
      return;
    }
    int? selectedPartId = _spareParts.first['id'] as int?;
    final qtyCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Solicitar Repuesto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedPartId,
                  decoration: const InputDecoration(labelText: 'Repuesto *'),
                  items: _spareParts
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
                    'work_order_id': widget.woId,
                    if (notesCtrl.text.isNotEmpty) 'notes': notesCtrl.text,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Pedido enviado al depósito'),
                        backgroundColor: BsaTheme.secondary,
                      ),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Enviar Pedido'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text(_wo != null ? 'OT #${_wo!['id']}' : 'Cargando...'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _wo == null
              ? const Center(child: Text('OT no encontrada'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WOHeader(wo: _wo!),
                      const SizedBox(height: 16),
                      _StatusActions(
                        wo: _wo!,
                        auth: auth,
                        onChangeStatus: _changeStatus,
                      ),
                      const SizedBox(height: 16),
                      _RequestPartsCard(
                        wo: _wo!,
                        auth: auth,
                        onRequestPart: _showRequestPartForm,
                      ),
                      const SizedBox(height: 16),
                      _WODetails(wo: _wo!),
                      const SizedBox(height: 16),
                      _CommentsSection(
                        comments: (_wo!['comments'] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            [],
                        controller: _commentCtrl,
                        sending: _sendingComment,
                        onSend: _sendComment,
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _WOHeader extends StatelessWidget {
  final Map<String, dynamic> wo;
  const _WOHeader({required this.wo});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusBadge(status: wo['status'] as String? ?? ''),
                const SizedBox(width: 8),
                _PriorityBadge(priority: wo['priority'] as String? ?? ''),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              wo['title'] as String? ?? '',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A5F),
              ),
            ),
            if (wo['description'] != null &&
                (wo['description'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                wo['description'] as String,
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusActions extends StatelessWidget {
  final Map<String, dynamic> wo;
  final AuthProvider auth;
  final Function(String) onChangeStatus;
  const _StatusActions(
      {required this.wo, required this.auth, required this.onChangeStatus});

  @override
  Widget build(BuildContext context) {
    final status = wo['status'] as String? ?? '';
    final canManage =
        auth.hasAnyRole(['admin', 'maintenance_manager', 'technician']);
    if (!canManage) return const SizedBox.shrink();

    final transitions = <String, String>{};
    i {
      us == 'open' || status == 'assigned')
      tra
    }nsitions['in_progress'] = 'Iniciar Trabajo';
    if (status == 'in_progress') {
      transitions['waiting_parts'] = 'Esperar Repuestos';
    }
    if (status == 'waiting_parts') {
      transitions['in_progress'] = 'Reanudar Trabajo';
    }
    i {
      us == 'in_progress' || status == 'wa
    }iting_parts')
      transitions['closed'] = 'Cerrar O {
       if (status != 'closed' && status != '
    }cancelled')
      transitions['cancelled'] = 'Cancelar';

    if (transitions.isEmpty) return const SizedBox.shrink();

    return Card(
      child = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cambiar Estado',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: transitions.entries
                  .map((e) => OutlinedButton(
                        onPressed: () => onChangeStatus(e.key),
                        child:
                            Text(e.value, style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestPartsCard extends StatelessWidget {
  final Map<String, dynamic> wo;
  final AuthProvider auth;
  final VoidCallback onRequestPart;
  const _RequestPartsCard({
    required this.wo,
    required this.auth,
    required this.onRequestPart,
  });

  @override
  Widget build(BuildContext context) {
    final canRequest = auth.hasAnyRole(
        ['admin', 'maintenance_manager', 'technician', 'warehouse']);
    if (!canRequest) return const SizedBox.shrink();

    final status = wo['status'] as String? ?? '';
    // Solo mostrar si la OT está en progreso o esperando repuestos
    if (status != 'in_progress' &&
        status != 'waiting_parts' &&
        status != 'open' &&
        status != 'assigned') {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Repuestos',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: const Text('Solicitar Repuesto al Depósito'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BsaTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: onRequestPart,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  String get label {
    const m = {
      'open': 'Abierta',
      'assigned': 'Asignada',
      'in_progress': 'En Progreso',
      'waiting_parts': 'Espera Repuestos',
      'closed': 'Cerrada',
      'cancelled': 'Cancelada',
    };
    return m[status] ?? status;
  }

  Color get color {
    switch (status) {
      case 'open':
        return const Color(0xFF2E86AB);
      case 'assigned':
        return const Color(0xFF8E44AD);
      case 'in_progress':
        return const Color(0xFFE67E22);
      case 'waiting_parts':
        return const Color(0xFFF39C12);
      case 'closed':
        return const Color(0xFF27AE60);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String priority;
  const _PriorityBadge({required this.priority});

  String get label {
    const m = {
      'low': 'Baja',
      'medium': 'Media',
      'high': 'Alta',
      'critical': 'Crítica',
    };
    return m[priority] ?? priority;
  }

  Color get color {
    switch (priority) {
      case 'low':
        return Colors.grey;
      case 'medium':
        return const Color(0xFF2E86AB);
      case 'high':
        return Colors.orange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _WODetails extends StatelessWidget {
  final Map<String, dynamic> wo;
  const _WODetails({required this.wo});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Detalles',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            _DetailRow('Equipo', wo['equipment_name'] ?? 'Sin equipo'),
            _DetailRow('Asignado a', wo['assigned_to_name'] ?? 'Sin asignar'),
            _DetailRow('Tipo',
                wo['wo_type'] == 'corrective' ? 'Correctivo' : 'Preventivo'),
            if (wo['estimated_hours'] != null)
              _DetailRow('Horas estimadas', '${wo['estimated_hours']}h'),
            if (wo['actual_hours'] != null)
              _DetailRow('Horas reales', '${wo['actual_hours']}h'),
            if (wo['due_date'] != null)
              _DetailRow(
                  'Fecha límite', (wo['due_date'] as String).substring(0, 10)),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _CommentsSection extends StatelessWidget {
  final List<Map<String, dynamic>> comments;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _CommentsSection({
    required this.comments,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Comentarios (${comments.length})',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            ...comments.map((c) => _CommentBubble(comment: c)),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Agregar comentario...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    minLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                sending
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton.filled(
                        onPressed: onSend,
                        icon: const Icon(Icons.send_rounded),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  final Map<String, dynamic> comment;
  const _CommentBubble({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF2E86AB),
            child: Text(
              ((comment['user_name'] as String? ?? 'U')[0]).toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment['user_name'] as String? ?? 'Usuario',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      (comment['created_at'] as String? ?? '').length >= 10
                          ? (comment['created_at'] as String).substring(0, 10)
                          : '',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment['content'] as String? ?? '',
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
