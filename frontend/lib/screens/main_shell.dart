import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  final List<String> allowedRoles; // empty = todos

  const _NavItem({
    required this.label,
    required this.icon,
    required this.route,
    this.allowedRoles = const [],
  });
}

const _allNavItems = [
  _NavItem(
    label: 'Dashboard',
    icon: Icons.dashboard_rounded,
    route: '/dashboard',
    allowedRoles: ['admin', 'maintenance_manager', 'viewer'],
  ),
  _NavItem(
    label: 'Órdenes de Trabajo',
    icon: Icons.build_circle_rounded,
    route: '/work-orders',
    allowedRoles: [],
  ),
  _NavItem(
    label: 'Planificación',
    icon: Icons.calendar_month_rounded,
    route: '/planning',
    allowedRoles: ['admin', 'maintenance_manager', 'technician'],
  ),
  _NavItem(
    label: 'Equipos',
    icon: Icons.precision_manufacturing_rounded,
    route: '/equipments',
    allowedRoles: ['admin', 'maintenance_manager', 'technician', 'viewer'],
  ),
  _NavItem(
    label: 'Depósito / Stock',
    icon: Icons.inventory_2_rounded,
    route: '/spare-parts',
    allowedRoles: ['admin', 'maintenance_manager', 'technician', 'warehouse', 'purchasing'],
  ),
  _NavItem(
    label: 'Compras',
    icon: Icons.shopping_cart_rounded,
    route: '/purchases',
    allowedRoles: ['admin', 'purchasing', 'maintenance_manager'],
  ),
  _NavItem(
    label: 'Usuarios',
    icon: Icons.people_rounded,
    route: '/users',
    allowedRoles: ['admin', 'hr'],
  ),
  _NavItem(
    label: 'Notificaciones',
    icon: Icons.notifications_rounded,
    route: '/notifications',
    allowedRoles: [],
  ),
  _NavItem(
    label: 'Suscripción',
    icon: Icons.credit_card_rounded,
    route: '/subscription',
    allowedRoles: ['admin'],
  ),
];

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  List<_NavItem> _visibleItems(AuthProvider auth) {
    return _allNavItems.where((item) {
      if (item.allowedRoles.isEmpty) return true;
      return item.allowedRoles.any((r) => auth.hasRole(r));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final items = _visibleItems(auth);
    final location = GoRouterState.of(context).matchedLocation;
    final isWide = MediaQuery.of(context).size.width >= 800;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _SideBar(items: items, location: location, auth: auth),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    // Mobile: bottom nav or drawer
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [BsaTheme.primary, BsaTheme.primaryDark],
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(
                Icons.precision_manufacturing_rounded,
                color: Colors.white,
                size: 15,
              ),
            ),
            const SizedBox(width: 10),
            const Text('SGM'),
          ],
        ),
        actions: [
          _NotifBadge(),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        child: _SideBar(items: items, location: location, auth: auth),
      ),
      body: child,
    );
  }
}

class _SideBar extends StatelessWidget {
  final List<_NavItem> items;
  final String location;
  final AuthProvider auth;

  const _SideBar(
      {required this.items, required this.location, required this.auth});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        gradient: BsaTheme.sidebarGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          // ── Header BSA ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                // Logo BSA mini
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.2)),
                  ),
                  child: const Icon(
                    Icons.precision_manufacturing_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SGM',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      AppConfig.companyName,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── Usuario actual ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: BsaTheme.secondary,
                    child: Text(
                      _initials(auth),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.fullName.isNotEmpty
                              ? auth.fullName
                              : auth.email,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _roleLabel(auth.roles),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'MENÚ PRINCIPAL',
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // ── Ítems de navegación ─────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: items.map((item) {
                final isActive = location.startsWith(item.route);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        context.go(item.route);
                        if (Scaffold.of(context).isDrawerOpen) {
                          Navigator.pop(context);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isActive
                              ? BsaTheme.secondary.withOpacity(0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: isActive
                              ? Border.all(
                                  color: BsaTheme.secondary.withOpacity(0.4))
                              : null,
                        ),
                        child: Row(
                          children: [
                            // Indicador lateral activo
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 3,
                              height: 20,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? BsaTheme.secondary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              item.icon,
                              color: isActive
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  color: isActive
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.65),
                                  fontSize: 13.5,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isActive)
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: BsaTheme.secondary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // ── Footer ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Divider(
                color: Colors.white.withOpacity(0.12), height: 1),
          ),
          const SizedBox(height: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                await auth.logout();
                if (context.mounted) context.go('/login');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded,
                        color: Colors.white.withOpacity(0.45), size: 18),
                    const SizedBox(width: 12),
                    Text(
                      'Cerrar sesión',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 4),
            child: Text(
              'v${AppConfig.appVersion}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.2),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(AuthProvider auth) {
    final name = auth.fullName.isNotEmpty ? auth.fullName : auth.email;
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  String _roleLabel(List<String> roles) {
    if (roles.isEmpty) return 'Sin rol';
    const labels = {
      'admin': 'Administrador',
      'maintenance_manager': 'Jefe Mantenimiento',
      'technician': 'Técnico',
      'warehouse': 'Depósito',
      'purchasing': 'Compras',
      'hr': 'RRHH',
      'viewer': 'Visualizador',
    };
    return roles.map((r) => labels[r] ?? r).join(', ');
  }
}

class _NotifBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.notifications_outlined),
      tooltip: 'Notificaciones',
      onPressed: () => context.go('/notifications'),
    );
  }
}
