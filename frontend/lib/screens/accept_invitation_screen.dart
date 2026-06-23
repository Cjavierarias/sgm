import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// Pantalla de aceptación de invitación.
/// Se accede vía link /#/accept-invitation?token=XXX
class AcceptInvitationScreen extends StatefulWidget {
  final String token;
  const AcceptInvitationScreen({super.key, required this.token});

  @override
  State<AcceptInvitationScreen> createState() => _AcceptInvitationScreenState();
}

class _AcceptInvitationScreenState extends State<AcceptInvitationScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _submitting = false;
  String _error = '';
  Map<String, dynamic>? _invitation;

  final _passwordCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _checkToken();
  }

  Future<void> _checkToken() async {
    try {
      final data = await _api.checkInvitationToken(widget.token);
      setState(() {
        _invitation = data;
        _loading = false;
        if (!data['valid']) {
          _error = data['message'] ?? 'Invitación inválida';
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    if (_passwordCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La contraseña debe tener al menos 6 caracteres')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final data = await _api.acceptInvitation(
        token: widget.token,
        password: _passwordCtrl.text,
        fullName: _fullNameCtrl.text.isNotEmpty ? _fullNameCtrl.text : null,
        phone: _phoneCtrl.text.isNotEmpty ? _phoneCtrl.text : null,
        position: _positionCtrl.text.isNotEmpty ? _positionCtrl.text : null,
      );
      // Auto-login
      final token = data['access_token'] as String;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.setTokenAndLoad(token);
      if (mounted) context.go('/dashboard');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BsaTheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _buildContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Verificando invitación...'),
        ],
      );
    }

    if (_error.isNotEmpty || _invitation == null || _invitation!['valid'] != true) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: BsaTheme.error, size: 48),
          const SizedBox(height: 16),
          Text(
            _error.isNotEmpty ? _error : 'Invitación inválida',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: BsaTheme.textPrimary),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/login'),
            child: const Text('Ir al login'),
          ),
        ],
      );
    }

    final companyName = _invitation!['company_name'] as String? ?? 'la empresa';
    final email = _invitation!['email'] as String? ?? '';
    final roles = (_invitation!['roles'] as List?)?.cast<String>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: BsaTheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Icon(Icons.mail_outline, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              const Text(
                '¡Bienvenido a SGM!',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Te invitaron a $companyName',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _InfoRow(label: 'Email', value: email),
        if (roles.isNotEmpty) ...[
          const SizedBox(height: 8),
          _InfoRow(label: 'Roles', value: roles.join(', ')),
        ],
        const SizedBox(height: 24),
        TextField(
          controller: _fullNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre completo',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          decoration: const InputDecoration(
            labelText: 'Teléfono (opcional)',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _positionCtrl,
          decoration: const InputDecoration(
            labelText: 'Cargo (opcional)',
            prefixIcon: Icon(Icons.work_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _submitting ? null : _accept,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: BsaTheme.secondary,
          ),
          child: _submitting
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
              : const Text('Aceptar invitación y crear cuenta'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(color: BsaTheme.textSecondary, fontSize: 13)),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
      ],
    );
  }
}
