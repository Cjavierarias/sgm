import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      final data = await auth.apiService.getWorkOrder(widget.woId);
      if (mounted) setState(() { _wo = data; _loading = false; });
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
    if (status == 'open' || status == 'assigned')
      transitions['in_progress'] = 'Iniciar Trabajo';
    if (status == 'in_progress') transitions['waiting_parts'] = 'Esperar Repuestos';
    if (status == 'in_progress' || status == 'waiting_parts')
      transitions['closed'] = 'Cerrar OT';
    if (status != 'closed' && status != 'cancelled')
      transitions['cancelled'] = 'Cancelar';

    if (transitions.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
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
                        child: Text(e.value, style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
            ),
          ],
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
            _DetailRow(
                'Asignado a', wo['assigned_to_name'] ?? 'Sin asignar'),
            _DetailRow('Tipo',
                wo['wo_type'] == 'corrective' ? 'Correctivo' : 'Preventivo'),
            if (wo['estimated_hours'] != null)
              _DetailRow(
                  'Horas estimadas', '${wo['estimated_hours']}h'),
            if (wo['actual_hours'] != null)
              _DetailRow('Horas reales', '${wo['actual_hours']}h'),
            if (wo['due_date'] != null)
              _DetailRow('Fecha límite',
                  (wo['due_date'] as String).substring(0, 10)),
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
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
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
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
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

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color get color {
    switch (status) {
      case 'open': return const Color(0xFF2E86AB);
      case 'assigned': return const Color(0xFF8E44AD);
      case 'in_progress': return const Color(0xFFE67E22);
      case 'waiting_parts': return const Color(0xFFF39C12);
      case 'closed': return const Color(0xFF27AE60);
      default: return Colors.grey;
    }
  }

  String get label {
    const m = {
      'open': 'Abierta', 'assigned': 'Asignada',
      'in_progress': 'En Progreso', 'waiting_parts': 'Esp. Repuestos',
      'closed': 'Cerrada', 'cancelled': 'Cancelada',
    };
    return m[status] ?? status;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String priority;
  const _PriorityBadge({required this.priority});

  Color get color {
    switch (priority) {
      case 'critical': return const Color(0xFFC0392B);
      case 'high': return const Color(0xFFE67E22);
      case 'medium': return const Color(0xFF2E86AB);
      default: return Colors.grey;
    }
  }

  String get label {
    const m = {'low': 'Baja', 'medium': 'Media', 'high': 'Alta', 'critical': 'Crítica'};
    return m[priority] ?? priority;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
