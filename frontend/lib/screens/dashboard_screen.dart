import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final data = await auth.apiService.getDashboardSummary();
      if (mounted) setState(() { _summary = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      backgroundColor: BsaTheme.background,
      body: RefreshIndicator(
        onRefresh: _load,
        color: BsaTheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(auth: auth),
              const SizedBox(height: 28),
              if (_loading)
                const _LoadingCards()
              else if (_error.isNotEmpty)
                _ErrorCard(error: _error, onRetry: _load)
              else if (_summary != null)
                _SummaryCards(summary: _summary!, auth: auth),
              const SizedBox(height: 28),
              _QuickActions(auth: auth),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AuthProvider auth;
  const _Header({required this.auth});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final firstName = auth.fullName.isNotEmpty
        ? auth.fullName.split(' ').first
        : 'Usuario';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0077B6), Color(0xFF005F8E)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: BsaTheme.primary.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_greeting()}, $firstName 👋',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Panel de control — ${AppConfig.companyName}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.precision_manufacturing_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final Map<String, dynamic> summary;
  final AuthProvider auth;
  const _SummaryCards({required this.summary, required this.auth});

  @override
  Widget build(BuildContext context) {
    final wo = summary['work_orders'] as Map<String, dynamic>? ?? {};
    final eq = summary['equipment'] as Map<String, dynamic>? ?? {};

    // Tarjetas base para todos
    final allCards = <_CardData>[
      _CardData(label: 'OT Abiertas', value: '${wo['open'] ?? 0}',
          icon: Icons.folder_open_rounded, color: BsaTheme.primary,
          bgColor: const Color(0xFFE8F4FB), route: '/work-orders'),
      _CardData(label: 'En Progreso', value: '${wo['in_progress'] ?? 0}',
          icon: Icons.build_rounded, color: const Color(0xFFF59E0B),
          bgColor: const Color(0xFFFFF8E8), route: '/work-orders'),
      _CardData(label: 'Esperando Repuestos', value: '${wo['waiting_parts'] ?? 0}',
          icon: Icons.inventory_2_rounded, color: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFEEAEA), route: '/spare-parts'),
      _CardData(label: 'Equipos Activos', value: '${eq['operational'] ?? 0}',
          icon: Icons.check_circle_rounded, color: BsaTheme.secondary,
          bgColor: const Color(0xFFE8F6EE), route: '/equipments'),
      _CardData(label: 'En Mantenimiento', value: '${eq['in_maintenance'] ?? 0}',
          icon: Icons.precision_manufacturing_rounded, color: const Color(0xFFD97706),
          bgColor: const Color(0xFFFFF3E0), route: '/equipments'),
      _CardData(label: 'Stock Bajo', value: '${summary['low_stock_parts'] ?? 0}',
          icon: Icons.warning_amber_rounded, color: const Color(0xFFD97706),
          bgColor: const Color(0xFFFFF3E0), route: '/spare-parts'),
      _CardData(label: 'Notificaciones', value: '${summary['unread_notifications'] ?? 0}',
          icon: Icons.notifications_active_rounded, color: const Color(0xFF7C3AED),
          bgColor: const Color(0xFFF0EAFB), route: '/notifications'),
    ];

    // Filtrar tarjetas según rol
    final List<_CardData> cards;
    if (auth.isAdmin || auth.isMaintenanceManager) {
      cards = allCards; // Admin y Jefe ven todo
    } else if (auth.isTechnician) {
      cards = allCards.where((c) =>
          c.route == '/work-orders' || c.route == '/equipments' ||
          c.route == '/notifications').toList();
    } else if (auth.isWarehouse) {
      cards = allCards.where((c) =>
          c.label == 'Stock Bajo' || c.label == 'OT Abiertas' ||
          c.label == 'Esperando Repuestos' || c.route == '/notifications').toList();
    } else if (auth.isPurchasing) {
      cards = allCards.where((c) =>
          c.label == 'Stock Bajo' || c.label == 'OT Abiertas' ||
          c.route == '/notifications').toList();
    } else {
      cards = allCards.take(4).toList(); // Viewer: primeras 4
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisExtent: 130,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: cards.length,
      itemBuilder: (context, i) => _SummaryCard(data: cards[i]),
    );
  }
}

class _CardData {
  final String label, value, route;
  final IconData icon;
  final Color color;
  final Color bgColor;
  const _CardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.route,
  });
}

class _SummaryCard extends StatelessWidget {
  final _CardData data;
  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.go(data.route),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16), // antes 18
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BsaTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38, // antes 40
                    height: 38, // antes 40
                    decoration: BoxDecoration(
                      color: data.bgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(data.icon, color: data.color, size: 19),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: BsaTheme.textSecondary.withOpacity(0.4),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                data.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 30, // antes 32
                  fontWeight: FontWeight.bold,
                  color: data.color,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2), // antes 4
              Text(
                data.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: BsaTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder animado mientras carga
class _LoadingCards extends StatelessWidget {
  const _LoadingCards();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisExtent: 130,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: BsaTheme.border,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final AuthProvider auth;
  const _QuickActions({required this.auth});

  @override
  Widget build(BuildContext context) {
    // Acciones disponibles según el rol
    final actions = <({String label, IconData icon, String route, Color? color})>[];

    if (auth.hasAnyRole(['admin', 'maintenance_manager'])) {
      actions.addAll([
        (label: 'Nueva OT', icon: Icons.add_circle_outline_rounded, route: '/work-orders', color: BsaTheme.primary),
        (label: 'Planificación', icon: Icons.calendar_month_rounded, route: '/planning', color: BsaTheme.secondary),
        (label: 'Equipos', icon: Icons.precision_manufacturing_rounded, route: '/equipments', color: null),
      ]);
    }
    if (auth.isTechnician) {
      actions.addAll([
        (label: 'Mis OT', icon: Icons.build_circle_rounded, route: '/work-orders', color: BsaTheme.primary),
        (label: 'Pedir repuesto', icon: Icons.inventory_2_rounded, route: '/spare-parts', color: BsaTheme.secondary),
      ]);
    }
    if (auth.isWarehouse) {
      actions.addAll([
        (label: 'Stock / Depósito', icon: Icons.inventory_2_rounded, route: '/spare-parts', color: BsaTheme.primary),
        (label: 'Pedidos pendientes', icon: Icons.pending_actions_rounded, route: '/spare-parts', color: const Color(0xFFD97706)),
      ]);
    }
    if (auth.isPurchasing) {
      actions.addAll([
        (label: 'Órdenes de Compra', icon: Icons.shopping_cart_rounded, route: '/purchases', color: BsaTheme.primary),
        (label: 'Proveedores', icon: Icons.business_rounded, route: '/purchases', color: null),
      ]);
    }
    if (auth.hasAnyRole(['admin', 'hr'])) {
      actions.add((label: 'Gestionar usuarios', icon: Icons.people_rounded, route: '/users', color: null));
    }
    // Siempre visible
    actions.add((label: 'Ver OT', icon: Icons.list_alt_rounded, route: '/work-orders', color: null));

    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Acciones rápidas',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                color: BsaTheme.textPrimary, letterSpacing: -0.2)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: actions.map((a) => _ActionButton(
            label: a.label, icon: a.icon,
            onTap: () => context.go(a.route),
            color: a.color,
          )).toList(),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? BsaTheme.primary;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BsaTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 15, color: c),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: BsaTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorCard({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: BsaTheme.error.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BsaTheme.error.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: BsaTheme.error, size: 36),
          const SizedBox(height: 8),
          const Text(
            'No se pudo cargar el resumen',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: BsaTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Reintentar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: BsaTheme.primary,
              side: const BorderSide(color: BsaTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
