// ─── USERS SCREEN ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final data = await auth.apiService.getUsers();
      if (mounted) setState(() { _users = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _roleLabel(String r) {
    const m = {
      'admin': 'Admin',
      'maintenance_manager': 'Jefe Mant.',
      'technician': 'Técnico',
      'warehouse': 'Depósito',
      'purchasing': 'Compras',
      'hr': 'RRHH',
      'viewer': 'Visualizador',
    };
    return m[r] ?? r;
  }

  Color _roleColor(String r) {
    const m = {
      'admin': Color(0xFF1E3A5F),
      'maintenance_manager': Color(0xFF8E44AD),
      'technician': Color(0xFF2E86AB),
      'warehouse': Color(0xFFE67E22),
      'purchasing': Color(0xFF27AE60),
      'hr': Color(0xFFC0392B),
      'viewer': Colors.grey,
    };
    return m[r] ?? Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canCreate = auth.hasAnyRole(['admin', 'hr']);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Usuarios'),
        actions: [
          if (canCreate)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Nuevo'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () async {
                  await _showUserForm(context);
                  _load();
                },
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _users.isEmpty
                  ? const Center(child: Text('No hay usuarios'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final u = _users[i];
                        final roles = (u['roles'] as List?)
                                ?.map((r) => r.toString())
                                .toList() ??
                            [];
                        final isActive = u['is_active'] as bool? ?? true;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF1E3A5F),
                              child: Text(
                                ((u['full_name'] as String? ??
                                            u['email'] as String? ??
                                            'U')[0])
                                    .toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              u['full_name'] as String? ?? u['email'] as String? ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isActive ? null : Colors.grey,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u['email'] as String? ?? '',
                                    style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 4,
                                  children: roles
                                      .map((r) => Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _roleColor(r).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              _roleLabel(r),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: _roleColor(r),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: isActive
                                ? const Icon(Icons.check_circle,
                                    color: Color(0xFF27AE60), size: 18)
                                : const Icon(Icons.cancel,
                                    color: Colors.grey, size: 18),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Future<void> _showUserForm(BuildContext ctx) async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final posCtrl = TextEditingController();
    final selectedRoles = <String>['technician'];
    final formKey = GlobalKey<FormState>();

    const allRoles = [
      ('admin', 'Admin'),
      ('maintenance_manager', 'Jefe Mantenimiento'),
      ('technician', 'Técnico'),
      ('warehouse', 'Depósito'),
      ('purchasing', 'Compras'),
      ('hr', 'RRHH'),
      ('viewer', 'Visualizador'),
    ];

    await showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDState) => AlertDialog(
          title: const Text('Nuevo Usuario'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email *'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v!.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre completo'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: passCtrl,
                    decoration: const InputDecoration(labelText: 'Contraseña *'),
                    obscureText: true,
                    validator: (v) =>
                        v!.length < 6 ? 'Mínimo 6 caracteres' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: posCtrl,
                    decoration: const InputDecoration(labelText: 'Cargo'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Roles:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ...allRoles.map((r) => CheckboxListTile(
                        dense: true,
                        title: Text(r.$2, style: const TextStyle(fontSize: 13)),
                        value: selectedRoles.contains(r.$1),
                        onChanged: (v) => setDState(() {
                          if (v!) {
                            selectedRoles.add(r.$1);
                          } else {
                            selectedRoles.remove(r.$1);
                          }
                        }),
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final auth = Provider.of<AuthProvider>(ctx, listen: false);
                await auth.apiService.createUser({
                  'email': emailCtrl.text.trim(),
                  'full_name': nameCtrl.text.trim(),
                  'password': passCtrl.text,
                  'position': posCtrl.text.trim(),
                  'roles': selectedRoles,
                });
                if (dCtx.mounted) Navigator.pop(dCtx);
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }
}
