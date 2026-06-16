import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});
  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _equipments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        api.getMaintenancePlans(),
        api.getUpcomingPlans(days: 60),
        api.getEquipments(),
      ]);
      if (mounted) {
        setState(() {
          _plans = results[0];
          _upcoming = results[1];
          _equipments = results[2];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canManage = auth.hasAnyRole(['admin', 'maintenance_manager']);
    final overdueCount = _upcoming.where((p) => p['is_overdue'] == true).length;

    return Scaffold(
      backgroundColor: BsaTheme.background,
      appBar: AppBar(
        title: const Text('Planificación Preventiva'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded, size: 18),
                const SizedBox(width: 6),
                const Text('Próximos'),
                if (overdueCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: BsaTheme.error, borderRadius: BorderRadius.circular(8)),
                    child: Text('$overdueCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
            ),
            const Tab(icon: Icon(Icons.calendar_month_rounded), text: 'Todos los planes'),
          ],
        ),
        actions: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo plan'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () => _showPlanForm(context),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _UpcomingTab(
                  plans: _upcoming,
                  onRefresh: _load,
                  onExecute: (p) => _showExecuteDialog(context, p),
                  auth: auth,
                ),
                _AllPlansTab(
                  plans: _plans,
                  onRefresh: _load,
                  onExecute: (p) => _showExecuteDialog(context, p),
                  onEdit: (p) => _showPlanForm(context, plan: p),
                  onDelete: _deletePlan,
                  auth: auth,
                ),
              ],
            ),
    );
  }

  Future<void> _showPlanForm(BuildContext context, {Map<String, dynamic>? plan}) async {
    int? equipmentId = plan?['equipment_id'] as int?;
    final titleCtrl = TextEditingController(text: plan?['title'] ?? '');
    final descCtrl = TextEditingController(text: plan?['description'] ?? '');
    String frequency = plan?['frequency'] ?? 'monthly';
    final freqValueCtrl = TextEditingController(text: '${plan?['frequency_value'] ?? 1}');
    DateTime? nextDue = plan?['next_due'] != null
        ? DateTime.tryParse(plan!['next_due'] as String)
        : DateTime.now().add(const Duration(days: 30));

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(plan == null ? 'Nuevo Plan Preventivo' : 'Editar Plan'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int?>(
                  value: equipmentId,
                  decoration: const InputDecoration(labelText: 'Equipo *'),
                  items: _equipments.map((e) => DropdownMenuItem(
                      value: e['id'] as int,
                      child: Text('${e['code']} - ${e['name']}', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setD(() => equipmentId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Título *')),
                const SizedBox(height: 12),
                TextFormField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Descripción'), maxLines: 2),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: frequency,
                      decoration: const InputDecoration(labelText: 'Frecuencia'),
                      items: const [
                        DropdownMenuItem(value: 'daily', child: Text('Diario')),
                        DropdownMenuItem(value: 'weekly', child: Text('Semanal')),
                        DropdownMenuItem(value: 'monthly', child: Text('Mensual')),
                        DropdownMenuItem(value: 'quarterly', child: Text('Trimestral')),
                        DropdownMenuItem(value: 'yearly', child: Text('Anual')),
                        DropdownMenuItem(value: 'by_hours', child: Text('Por horas')),
                      ],
                      onChanged: (v) => setD(() => frequency = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: freqValueCtrl,
                      decoration: const InputDecoration(labelText: 'Cada'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: nextDue ?? DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 1825)),
                    );
                    if (picked != null) setD(() => nextDue = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Próximo vencimiento', suffixIcon: Icon(Icons.calendar_today)),
                    child: Text(
                      nextDue != null ? '${nextDue!.day}/${nextDue!.month}/${nextDue!.year}' : 'Seleccionar fecha',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (equipmentId == null || titleCtrl.text.isEmpty) return;
                final api = Provider.of<AuthProvider>(context, listen: false).apiService;
                final data = {
                  'equipment_id': equipmentId,
                  'title': titleCtrl.text.trim(),
                  if (descCtrl.text.isNotEmpty) 'description': descCtrl.text.trim(),
                  'frequency': frequency,
                  'frequency_value': int.tryParse(freqValueCtrl.text) ?? 1,
                  if (nextDue != null) 'next_due': nextDue!.toIso8601String(),
                };
                try {
                  if (plan == null) {
                    await api.createMaintenancePlan(data);
                  } else {
                    await api.updateMaintenancePlan(plan['id'] as int, data);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: Text(plan == null ? 'Crear Plan' : 'Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExecuteDialog(BuildContext context, Map<String, dynamic> plan) async {
    final notesCtrl = TextEditingController();
    final hoursCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar ejecución'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BsaTheme.secondary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, color: BsaTheme.secondary),
                const SizedBox(width: 8),
                Expanded(child: Text(plan['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: hoursCtrl,
              decoration: const InputDecoration(labelText: 'Horas reales (opcional)', suffixText: 'hs'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Observaciones'),
              maxLines: 3,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Confirmar ejecución'),
            style: ElevatedButton.styleFrom(backgroundColor: BsaTheme.secondary),
            onPressed: () async {
              final api = Provider.of<AuthProvider>(context, listen: false).apiService;
              try {
                await api.executeMaintenancePlan(
                  plan['id'] as int,
                  notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null,
                  actualHours: double.tryParse(hoursCtrl.text),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('✅ Mantenimiento registrado. Próximo vencimiento actualizado.'),
                    backgroundColor: BsaTheme.secondary,
                  ));
                }
              } catch (e) {
                if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deletePlan(Map<String, dynamic> plan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar plan'),
        content: Text('¿Eliminar el plan "${plan['title']}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: BsaTheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final api = Provider.of<AuthProvider>(context, listen: false).apiService;
      await api.deleteMaintenancePlan(plan['id'] as int);
      _load();
    }
  }
}

// ─── Tab Próximos vencimientos ────────────────────────────────────────────────
class _UpcomingTab extends StatelessWidget {
  final List<Map<String, dynamic>> plans;
  final VoidCallback onRefresh;
  final Function(Map<String, dynamic>) onExecute;
  final AuthProvider auth;

  const _UpcomingTab({required this.plans, required this.onRefresh, required this.onExecute, required this.auth});

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, size: 56, color: BsaTheme.secondary),
          SizedBox(height: 12),
          Text('Sin mantenimientos próximos', style: TextStyle(color: BsaTheme.textSecondary, fontSize: 16)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: plans.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) => _PlanCard(
          plan: plans[i], auth: auth, onExecute: () => onExecute(plans[i]),
          showEquipment: true,
        ),
      ),
    );
  }
}

// ─── Tab Todos los planes ─────────────────────────────────────────────────────
class _AllPlansTab extends StatelessWidget {
  final List<Map<String, dynamic>> plans;
  final VoidCallback onRefresh;
  final Function(Map<String, dynamic>) onExecute;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onDelete;
  final AuthProvider auth;

  const _AllPlansTab({required this.plans, required this.onRefresh, required this.onExecute, required this.onEdit, required this.onDelete, required this.auth});

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return const Center(child: Text('No hay planes configurados'));
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: plans.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) => _PlanCard(
          plan: plans[i], auth: auth, onExecute: () => onExecute(plans[i]),
          showEquipment: true,
          onEdit: auth.hasAnyRole(['admin', 'maintenance_manager']) ? () => onEdit(plans[i]) : null,
          onDelete: auth.hasAnyRole(['admin', 'maintenance_manager']) ? () => onDelete(plans[i]) : null,
        ),
      ),
    );
  }
}

// ─── Card de plan ─────────────────────────────────────────────────────────────
class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final AuthProvider auth;
  final VoidCallback onExecute;
  final bool showEquipment;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _PlanCard({
    required this.plan, required this.auth, required this.onExecute,
    this.showEquipment = false, this.onEdit, this.onDelete,
  });

  String _freqLabel(String f, int v) {
    final labels = {'daily': 'día', 'weekly': 'semana', 'monthly': 'mes', 'quarterly': 'trimestre', 'yearly': 'año', 'by_hours': 'hora'};
    return 'Cada $v ${labels[f] ?? f}${v > 1 ? 's' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final isOverdue = plan['is_overdue'] as bool? ?? false;
    final daysUntil = plan['days_until_due'] as int?;
    final isActive = plan['is_active'] as bool? ?? true;
    final freq = plan['frequency'] as String? ?? '';
    final freqVal = plan['frequency_value'] as int? ?? 1;

    Color urgencyColor = BsaTheme.secondary;
    String urgencyLabel = '';
    if (isOverdue) {
      urgencyColor = BsaTheme.error;
      urgencyLabel = 'VENCIDO hace ${daysUntil?.abs() ?? 0} días';
    } else if (daysUntil != null && daysUntil <= 7) {
      urgencyColor = BsaTheme.warning;
      urgencyLabel = daysUntil == 0 ? 'Vence HOY' : 'Vence en $daysUntil días';
    } else if (daysUntil != null) {
      urgencyLabel = 'En $daysUntil días';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: urgencyColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.build_circle_rounded, color: urgencyColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(plan['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: BsaTheme.textPrimary)),
              if (showEquipment && plan['equipment_name'] != null)
                Text('${plan['equipment_code']} — ${plan['equipment_name']}',
                    style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary)),
            ])),
            if (!isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: const Text('Inactivo', style: TextStyle(color: Colors.grey, fontSize: 11)),
              ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _Tag(label: _freqLabel(freq, freqVal), color: BsaTheme.primary),
            if (urgencyLabel.isNotEmpty)
              _Tag(label: urgencyLabel, color: urgencyColor),
            if (plan['last_done'] != null)
              _Tag(
                label: 'Último: ${(plan['last_done'] as String).substring(0, 10)}',
                color: BsaTheme.textSecondary,
              ),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (onEdit != null)
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text('Editar'),
                style: TextButton.styleFrom(foregroundColor: BsaTheme.textSecondary),
              ),
            if (onDelete != null)
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 15),
                label: const Text('Eliminar'),
                style: TextButton.styleFrom(foregroundColor: BsaTheme.error),
              ),
            const Spacer(),
            if (auth.hasAnyRole(['admin', 'maintenance_manager', 'technician']))
              ElevatedButton.icon(
                onPressed: onExecute,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Registrar ejecución'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BsaTheme.secondary,
                  minimumSize: const Size(0, 34),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
