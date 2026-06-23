import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/main_shell.dart';
import 'screens/dashboard_screen.dart';
import 'screens/work_orders_screen.dart';
import 'screens/work_order_detail_screen.dart';
import 'screens/equipments_screen.dart';
import 'screens/users_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/spare_parts_screen.dart';
import 'screens/purchases_screen.dart';
import 'screens/planning_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/accept_invitation_screen.dart';
import 'screens/invitations_screen.dart';
import 'screens/calendar_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Orientación preferida: portrait + landscape en tablet/desktop
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final authProvider = AuthProvider();
  await authProvider.refreshToken();
  runApp(
    ChangeNotifierProvider<AuthProvider>.value(
      value: authProvider,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: true);

    final router = GoRouter(
      initialLocation: '/login',
      refreshListenable: auth,
      redirect: (context, state) {
        final loggedIn = auth.isAuthenticated;
        final loggingIn = state.matchedLocation == '/login';
        final acceptingInv = state.matchedLocation.startsWith('/accept-invitation');
        if (acceptingInv) return null;  // ruta pública
        if (!loggedIn && !loggingIn) return '/login';
        final registering = state.matchedLocation == '/register';
        if (loggedIn && loggingIn) return '/dashboard';
        if (!loggedIn && registering) return null;
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (_, __) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/accept-invitation',
          builder: (_, state) => AcceptInvitationScreen(
            token: state.uri.queryParameters['token'] ?? '',
          ),
        ),
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (_, __) => const DashboardScreen(),
            ),
            GoRoute(
              path: '/work-orders',
              builder: (_, __) => const WorkOrdersScreen(),
            ),
            GoRoute(
              path: '/work-orders/:id',
              builder: (_, state) => WorkOrderDetailScreen(
                  woId: int.parse(state.pathParameters['id']!)),
            ),
            GoRoute(
              path: '/equipments',
              builder: (_, __) => const EquipmentsScreen(),
            ),
            GoRoute(
              path: '/users',
              builder: (_, __) => const UsersScreen(),
            ),
            GoRoute(
              path: '/notifications',
              builder: (_, __) => const NotificationsScreen(),
            ),
            GoRoute(
              path: '/spare-parts',
              builder: (_, __) => const SparePartsScreen(),
            ),
            GoRoute(
              path: '/purchases',
              builder: (_, __) => const PurchasesScreen(),
            ),
            GoRoute(
              path: '/planning',
              builder: (_, __) => const PlanningScreen(),
            ),
            GoRoute(
              path: '/subscription',
              builder: (_, __) => const SubscriptionScreen(),
            ),
            GoRoute(
              path: '/invitations',
              builder: (_, __) => const InvitationsScreen(),
            ),
            GoRoute(
              path: '/calendar',
              builder: (_, __) => const CalendarScreen(),
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: BsaTheme.build(),
      routerConfig: router,
    );
  }
}

/// ─── Paleta y tema oficial BSA Consultora ────────────────────────────────────
///
/// Primario  : Celeste BSA  #0077B6  (azul celeste)
/// Secundario: Verde BSA    #2D9F5E  (verde)
/// Superficie: Blanco       #FFFFFF
/// Fondo     : Gris claro   #F0F4F8
/// Texto     : Gris oscuro  #1A2E44
abstract class BsaTheme {
  // Colores de marca BSA
  static const Color primary = Color(0xFF0077B6);     // Celeste BSA
  static const Color primaryDark = Color(0xFF005F8E); // Celeste oscuro (hover)
  static const Color secondary = Color(0xFF2D9F5E);   // Verde BSA
  static const Color secondaryDark = Color(0xFF1E7A45);
  static const Color surface = Colors.white;
  static const Color background = Color(0xFFF0F4F8);
  static const Color textPrimary = Color(0xFF1A2E44);
  static const Color textSecondary = Color(0xFF5A7184);
  static const Color border = Color(0xFFD8E3ED);
  static const Color error = Color(0xFFD32F2F);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF2D9F5E);

  // Gradiente de fondo del sidebar
  static const LinearGradient sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF005F8E), Color(0xFF003A5C)],
  );

  static ThemeData build() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        error: error,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: background,
      // ── AppBar ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: border,
        titleTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: textPrimary, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      // ── Cards ────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
        color: surface,
        clipBehavior: Clip.antiAlias,
      ),
      // ── Botones primarios ─────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFB0CCDD),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          minimumSize: const Size.fromHeight(46),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      // ── Botones outline ───────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          minimumSize: const Size.fromHeight(46),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // ── Botones texto ─────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // ── Inputs ───────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: error),
        ),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        hintStyle: TextStyle(
            color: textSecondary.withOpacity(0.6), fontSize: 14),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),
      // ── Chips ────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: background,
        selectedColor: primary,
        disabledColor: background,
        labelStyle: const TextStyle(fontSize: 12, color: textPrimary),
        secondaryLabelStyle:
            const TextStyle(fontSize: 12, color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),
      // ── TabBar ───────────────────────────────────────────────────────
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 13),
        dividerColor: border,
      ),
      // ── ListTile ─────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      // ── Divider ──────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      // ── SnackBar ─────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle:
            const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      // ── FloatingActionButton ─────────────────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: CircleBorder(),
      ),
      // ── DialogTheme ──────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        titleTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
