import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// Pantalla de gestión de invitaciones (solo admin/RRHH).
/// Permite enviar invitaciones por email y ver el estado de las enviadas.
class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  late ApiService _api;
  List<Map<String, dynamic>> _invitations = [];
  bool _loading = true;

  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _selectedRole = 'technician';
  bool _sending = false;

  final _allRoles = [
    {'value': 'admin', 'label': 'Administrador'},
    {'value': 'maintenance_manager', 'label': 'Jefe Mantenimiento'},
    {'value': 'technician', 'label': 'Técnico / Mecánico'},
    {'value': 'warehouse', 'label': 'Depósito'},
    {'value': 'purchasing', 'label': 'Compras'},
    {'value': 'hr', 'label': 'RRHH'},
    {'value': 'viewer', 'label': 'Solo lectura'},
  ];

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _api = ApiService()..setAuthToken(auth.token);
    _loadInvitations();
  }

  Future<void> _loadInvitations() async {
    setState(() => _loading = true);
    try {
      _invitations = await _api.getInvitations();
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _sendInvitation() async {
    if (_emailCtrl.text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _api.createInvitation(
        email: _emailCtrl.text,
        fullName: _nameCtrl.text.isNotEmpty ? _nameCtrl.text : null,
        roles: [_selectedRole],
      );
      _emailCtrl.clear();
      _nameCtrl.clear();
      await _loadInvitations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invitación enviada por email'),
            backgroundColor: BsaTheme.secondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _revoke(int id) async {
    try {
      await _api.revokeInvitation(id);
      await _loadInvitations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':  return BsaTheme.warning;
      case 'accepted': return BsaTheme.secondary;
      case 'revoked':  return BsaTheme.error;
      case 'expired':  return BsaTheme.textSecondary;
      default:         return BsaTheme.textSecondary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':  return 'Pendiente';
      case 'accepted': return 'Aceptada';
      case 'revoked':  return 'Revocada';
      case 'expired':  return 'Expirada';
      default:         return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BsaTheme.background,
      appBar: AppBar(
        title: const Text('Invitaciones'),
        backgroundColor: BsaTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Formulario de nueva invitación ─────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.person_add_rounded, color: BsaTheme.primary),
                        SizedBox(width: 8),
                        Text(
                          'Invitar colaborador',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BsaTheme.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Email del invitado',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre (opcional)',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Rol',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      items: _allRoles.map((r) => DropdownMenuItem(
                        value: r['value'],
                        child: Text(r['label']!),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedRole = v ?? 'technician'),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _sending ? null : _sendInvitation,
                        icon: _sending
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white))
                            : const Icon(Icons.send_rounded),
                        label: const Text('Enviar invitación'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Lista de invitaciones ──────────────────────────────────────
            const Text(
              'Invitaciones enviadas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BsaTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_invitations.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.inbox, color: BsaTheme.textSecondary),
                  title: Text('No hay invitaciones enviadas'),
                ),
              )
            else
              ..._invitations.map((inv) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _statusColor(inv['status'] as String).withValues(alpha: 0.15),
                    child: Icon(
                      inv['status'] == 'accepted' ? Icons.check_circle : Icons.mail,
                      color: _statusColor(inv['status'] as String),
                    ),
                  ),
                  title: Text(inv['email'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${inv['full_name'] ?? 'Sin nombre'} • ${_statusLabel(inv['status'] as String)} • Vence: ${inv['expires_at']}',
                    style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary),
                  ),
                  trailing: inv['status'] == 'pending'
                      ? IconButton(
                          icon: const Icon(Icons.cancel_outlined, color: BsaTheme.error),
                          onPressed: () => _revoke(inv['id'] as int),
                          tooltip: 'Revocar',
                        )
                      : null,
                ),
              )),
          ],
        ),
      ),
    );
  }
}
