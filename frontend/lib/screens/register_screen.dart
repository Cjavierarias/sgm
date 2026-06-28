import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';

/// Pantalla de registro de nueva empresa (flujo SaaS).
/// Al completar: crea Company + User admin y hace login automático.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _companyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;
  String _error = '';

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = ''; });
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      // Paso 1: Registrar empresa + admin
      await auth.apiService.register(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        fullName: _nameCtrl.text.trim(),
        companyName: _companyCtrl.text.trim(),
      );
      // Paso 2: Auto-login con las mismas credenciales
      await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
      if (mounted && auth.isAuthenticated) {
        context.go('/dashboard');
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _error = msg.contains('registrado')
            ? 'Ese email ya tiene una cuenta. Usá "Iniciar sesión".'
            : msg;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      body: isWide ? _buildWide() : _buildNarrow(),
    );
  }

  Widget _buildWide() {
    return Row(
      children: [
        // Panel izquierdo branding
        Expanded(
          flex: 4,
          child: Container(
            decoration: const BoxDecoration(gradient: BsaTheme.sidebarGradient),
            padding: const EdgeInsets.all(48),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BrandLogo(),
                  const Spacer(),
                  const Text(
                    'Registrá\ntu empresa',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'En minutos tendrás tu sistema de\nmantenimiento industrial listo para usar.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 40),
                  const _StepBadge(n: '1', text: 'Completá los datos'),
                  const SizedBox(height: 12),
                  const _StepBadge(n: '2', text: 'Accedés como Administrador'),
                  const SizedBox(height: 12),
                  const _StepBadge(n: '3', text: 'Invitás a tu equipo'),
                  const Spacer(),
                  Text('© ${DateTime.now().year} ${AppConfig.companyName}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
        // Formulario
        Expanded(
          flex: 5,
          child: Container(
            color: BsaTheme.background,
            child: Center(child: _buildForm()),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF005F8E), Color(0xFF003A5C)],
          stops: [0.0, 0.32],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 36, 32, 24),
                child: Column(children: [
                  _BrandLogo(),
                  const SizedBox(height: 16),
                  const Text('Registrá tu empresa',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: BsaTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF003A5C).withValues(alpha: 0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8))
                  ],
                ),
                child: _buildForm(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Crear cuenta',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: BsaTheme.textPrimary,
                      letterSpacing: -0.4)),
              const SizedBox(height: 4),
              const Text('Registrá tu empresa para empezar',
                  style: TextStyle(
                      fontSize: 13, color: BsaTheme.textSecondary)),
              const SizedBox(height: 24),

              // Empresa
              const _SectionLabel(label: '🏢 Datos de la empresa'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _companyCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la empresa *',
                  prefixIcon: Icon(Icons.business_rounded),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 20),

              // Admin
              const _SectionLabel(label: '👤 Administrador'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if (!v.contains('@')) return 'Email inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscure1,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Contraseña *',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure1
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requerido';
                  if (v.length < 8) return 'Mínimo 8 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass2Ctrl,
                obscureText: _obscure2,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Repetir contraseña *',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure2
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                  ),
                ),
                validator: (v) {
                  if (v != _passCtrl.text) return 'Las contraseñas no coinciden';
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),

              // 🆕 Trial info banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2D9F5E).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.card_giftcard_rounded, color: Color(0xFF2D9F5E), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('30 días gratis',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E7A45),
                                  fontSize: 14)),
                          SizedBox(height: 2),
                          Text(
                            'Después: USD 5/mes o USD 50/año. Sin límite de colaboradores. Cancelá cuando quieras.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF3E8E5C)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Error inline
              if (_error.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: BsaTheme.error.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: BsaTheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: BsaTheme.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error,
                          style: const TextStyle(
                              color: BsaTheme.error, fontSize: 13)),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // Botón registrar
              SizedBox(
                height: 48,
                child: _loading
                    ? const Center(
                        child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2.5)))
                    : ElevatedButton(
                        onPressed: _submit,
                        child: const Text('Crear empresa y cuenta'),
                      ),
              ),
              const SizedBox(height: 16),

              // Ir a login
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('¿Ya tenés cuenta?',
                    style: TextStyle(
                        fontSize: 13, color: BsaTheme.textSecondary)),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Iniciar sesión',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: const Icon(Icons.precision_manufacturing_rounded,
            color: Colors.white, size: 22),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('SGM',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        Text(AppConfig.companyName,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
                letterSpacing: 0.3)),
      ]),
    ]);
  }
}

class _StepBadge extends StatelessWidget {
  final String n;
  final String text;
  const _StepBadge({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: BsaTheme.secondary,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(n,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ),
      const SizedBox(width: 12),
      Text(text,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14)),
    ]);
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: BsaTheme.textSecondary));
  }
}
