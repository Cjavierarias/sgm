import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    FocusScope.of(context).unfocus();
    try {
      await authProvider.login(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (authProvider.isAuthenticated && mounted) {
        context.go('/dashboard');
      }
    } catch (_) {
      // El error ya se muestra inline desde authProvider.errorMessage
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      body: isWide ? _buildWideLayout(auth) : _buildNarrowLayout(auth),
    );
  }

  /// Layout tablet/desktop: panel izquierdo de marca + formulario derecho
  Widget _buildWideLayout(AuthProvider auth) {
    return Row(
      children: [
        // Panel izquierdo BSA
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF005F8E), Color(0xFF003A5C)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo BSA
                    const _BsaLogo(size: 56),
                    const Spacer(),
                    const Text(
                      'Sistema de Gestión\nde Mantenimiento',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Gestioná equipos, órdenes de trabajo, repuestos\ny notificaciones desde un solo lugar.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 48),
                    const _FeatureBadge(
                        icon: Icons.build_circle_outlined,
                        text: 'Órdenes de trabajo'),
                    const SizedBox(height: 12),
                    const _FeatureBadge(
                        icon: Icons.inventory_2_outlined,
                        text: 'Control de stock'),
                    const SizedBox(height: 12),
                    const _FeatureBadge(
                        icon: Icons.people_outline, text: 'Multi-rol y multi-empresa'),
                    const Spacer(),
                    Text(
                      '© ${DateTime.now().year} BSA Consultora',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Panel derecho: formulario
        Expanded(
          flex: 4,
          child: Container(
            color: BsaTheme.background,
            child: Center(child: _buildForm(auth)),
          ),
        ),
      ],
    );
  }

  /// Layout móvil: pantalla completa
  Widget _buildNarrowLayout(AuthProvider auth) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF005F8E), Color(0xFF003A5C)],
          stops: [0.0, 0.38],
        ),
        color: BsaTheme.background,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header con logo
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
                child: Column(
                  children: [
                    const _BsaLogo(size: 52),
                    const SizedBox(height: 20),
                    const Text(
                      'SGM',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppConfig.companyName,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              // Card formulario
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: BsaTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF003A5C).withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: _buildForm(auth),
              ),
              const SizedBox(height: 32),
              Text(
                'SGM v${AppConfig.appVersion}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(AuthProvider auth) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Bienvenido',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: BsaTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Iniciá sesión para continuar',
                style: TextStyle(
                  fontSize: 14,
                  color: BsaTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              // Campo email
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  hintText: 'usuario@empresa.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresá tu email';
                  if (!v.contains('@')) return 'Email inválido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Campo contraseña
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: BsaTheme.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingresá tu contraseña' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              // Error inline
              if (auth.errorMessage.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: BsaTheme.error.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: BsaTheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: BsaTheme.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          auth.errorMessage,
                          style: const TextStyle(
                              color: BsaTheme.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Botón ingresar
              SizedBox(
                height: 48,
                child: auth.isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: _submit,
                        child: const Text('Ingresar'),
                      ),
              ),
              const SizedBox(height: 20),

              // Separador "o"
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('o',
                      style: TextStyle(
                          fontSize: 13,
                          color: BsaTheme.textSecondary.withValues(alpha: 0.6))),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 16),

              // Botón Google
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: auth.isLoading ? null : _loginGoogle,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: BsaTheme.border, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    backgroundColor: Colors.white,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo Google SVG inline como texto (compatible web)
                      _GoogleIcon(),
                      const SizedBox(width: 10),
                      const Text(
                        'Continuar con Google',
                        style: TextStyle(
                          color: BsaTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Ir a registro
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('¿No tenés cuenta?',
                    style: TextStyle(
                        fontSize: 13, color: BsaTheme.textSecondary)),
                TextButton(
                  onPressed: () => context.go('/register'),
                  child: const Text('Registrá tu empresa',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),

              const SizedBox(height: 8),
              // Versión
              const Text(
                AppConfig.companyName,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11, color: BsaTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loginGoogle() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await auth.loginWithGoogle();
      if (auth.isAuthenticated && mounted) {
        context.go('/dashboard');
      }
    } catch (_) {
      // error ya está en auth.errorMessage
    }
  }
}

/// Ícono de Google dibujado con Canvas (sin dependencia de imagen externa)
class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Simplificado: letras G en color Google
    final paint = Paint()..style = PaintingStyle.fill;

    // Rojo
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), -0.52, 1.57, true, paint);

    // Amarillo
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), 1.05, 1.57, true, paint);

    // Verde
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), 2.62, 1.57, true, paint);

    // Azul
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), -2.09, 1.57, true, paint);

    // Círculo blanco del centro
    paint.color = Colors.white;
    canvas.drawCircle(Offset(s / 2, s / 2), s * 0.35, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Logo BSA: icono de engranaje con acento verde
class _BsaLogo extends StatelessWidget {
  final double size;
  const _BsaLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(size * 0.25),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Icon(
            Icons.precision_manufacturing_rounded,
            color: Colors.white,
            size: size * 0.55,
          ),
        ),
        // Punto verde (acento de la marca)
        Positioned(
          bottom: -3,
          right: -3,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              color: BsaTheme.secondary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: BsaTheme.secondary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: BsaTheme.secondary, size: 17),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}