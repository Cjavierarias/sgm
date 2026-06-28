// ─── USERS SCREEN ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
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
      if (mounted)
        setState(() {
          _users = data;
          _loading = false;
        });
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

  String _searchQuery = '';

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _users;
    final q = _searchQuery.toLowerCase();
    return _users
        .where((u) =>
            (u['full_name'] as String? ?? '').toLowerCase().contains(q) ||
            (u['email'] as String? ?? '').toLowerCase().contains(q) ||
            (u['position'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canManage = auth.hasAnyRole(['admin', 'hr']);

    return Scaffold(
      backgroundColor: BsaTheme.background,
      appBar: AppBar(
        title: const Text('Usuarios'),
        actions: [
          if (canManage)
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
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, email o cargo...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: BsaTheme.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: BsaTheme.border)),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? const Center(child: Text('No hay usuarios'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final u = _filtered[i];
                              final roles = (u['roles'] as List?)
                                      ?.map((r) => r.toString())
                                      .toList() ??
                                  [];
                              final isActive = u['is_active'] as bool? ?? true;
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: isActive
                                          ? BsaTheme.primary
                                          : Colors.grey,
                                      child: Text(
                                        ((u['full_name'] as String? ??
                                                u['email'] as String? ??
                                                'U')[0])
                                            .toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Row(children: [
                                            Expanded(
                                                child: Text(
                                              u['full_name'] as String? ??
                                                  u['email'] as String? ??
                                                  '',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  color: isActive
                                                      ? BsaTheme.textPrimary
                                                      : Colors.grey),
                                            )),
                                            if (!isActive)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                    color: Colors.grey
                                                        .withValues(
                                                            alpha: 0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10)),
                                                child: const Text('Inactivo',
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.grey)),
                                              ),
                                          ]),
                                          Text(u['email'] as String? ?? '',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      BsaTheme.textSecondary)),
                                          if (u['position'] != null &&
                                              (u['position'] as String)
                                                  .isNotEmpty)
                                            Text(u['position'] as String,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: BsaTheme
                                                        .textSecondary)),
                                          const SizedBox(height: 6),
                                          Wrap(
                                              spacing: 4,
                                              runSpacing: 4,
                                              children: roles
                                                  .map((r) => Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 7,
                                                                vertical: 2),
                                                        decoration: BoxDecoration(
                                                            color: _roleColor(r)
                                                                .withValues(
                                                                    alpha: 0.1),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10)),
                                                        child: Text(
                                                            _roleLabel(r),
                                                            style: TextStyle(
                                                                fontSize: 11,
                                                                color:
                                                                    _roleColor(
                                                                        r),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600)),
                                                      ))
                                                  .toList()),
                                        ])),
                                    if (canManage)
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert,
                                            size: 18,
                                            color: BsaTheme.textSecondary),
                                        onSelected: (action) async {
                                          if (action == 'edit') {
                                            await _showUserForm(context,
                                                user: u);
                                            _load();
                                          } else if (action == 'roles') {
                                            await _showRolesForm(context, u);
                                            _load();
                                          } else if (action == 'toggle') {
                                            await _toggleActive(u);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(children: [
                                                Icon(Icons.edit_outlined,
                                                    size: 16),
                                                SizedBox(width: 8),
                                                Text('Editar datos')
                                              ])),
                                          const PopupMenuItem(
                                              value: 'roles',
                                              child: Row(children: [
                                                Icon(
                                                    Icons
                                                        .manage_accounts_rounded,
                                                    size: 16),
                                                SizedBox(width: 8),
                                                Text('Cambiar roles')
                                              ])),
                                          PopupMenuItem(
                                              value: 'toggle',
                                              child: Row(children: [
                                                Icon(
                                                    isActive
                                                        ? Icons.block_rounded
                                                        : Icons
                                                            .check_circle_outline,
                                                    size: 16,
                                                    color: isActive
                                                        ? BsaTheme.error
                                                        : BsaTheme.secondary),
                                                const SizedBox(width: 8),
                                                Text(
                                                    isActive
                                                        ? 'Desactivar'
                                                        : 'Activar',
                                                    style: TextStyle(
                                                        color: isActive
                                                            ? BsaTheme.error
                                                            : BsaTheme
                                                                .secondary)),
                                              ])),
                                        ],
                                      ),
                                  ]),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> u) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isActive = u['is_active'] as bool? ?? true;
    try {
      await auth.apiService
          .updateUser(u['id'] as int, {'is_active': !isActive});
      _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showRolesForm(
      BuildContext context, Map<String, dynamic> u) async {
    final currentRoles =
        (u['roles'] as List?)?.map((r) => r.toString()).toList() ?? [];
    final selected = <String>[...currentRoles];

    const allRoles = [
      ('admin', 'Administrador'),
      ('maintenance_manager', 'Jefe Mantenimiento'),
      ('technician', 'Técnico'),
      ('warehouse', 'Depósito'),
      ('purchasing', 'Compras'),
      ('hr', 'RRHH'),
      ('viewer', 'Visualizador'),
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Roles de ${u['full_name'] ?? u['email']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: allRoles
                .map((r) => CheckboxListTile(
                      dense: true,
                      title: Text(r.$2, style: const TextStyle(fontSize: 14)),
                      value: selected.contains(r.$1),
                      activeColor: BsaTheme.primary,
                      onChanged: (v) => setD(() {
                        if (v!)
                          selected.add(r.$1);
                        else
                          selected.remove(r.$1);
                      }),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (selected.isEmpty) return;
                final auth = Provider.of<AuthProvider>(context, listen: false);
                try {
                  await auth.apiService
                      .updateUserRoles(u['id'] as int, selected);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted)
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const Text('Guardar roles'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUserForm(BuildContext ctx,
      {Map<String, dynamic>? user}) async {
    final emailCtrl = TextEditingController(text: user?['email'] ?? '');
    final nameCtrl = TextEditingController(text: user?['full_name'] ?? '');
    final passCtrl = TextEditingController();
    final posCtrl = TextEditingController(text: user?['position'] ?? '');
    final selectedRoles = <String>[
      ...(user?['roles'] as List?)?.map((r) => r.toString()).toList() ??
          ['technician']
    ];
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
          title: Text(user == null ? 'Nuevo Usuario' : 'Editar Usuario'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
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
                      enabled: user == null, // No editable si ya existe
                      validator: (v) => v!.isEmpty ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: nameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Nombre completo'),
                    ),
                    const SizedBox(height: 8),
                    if (user == null) // Solo al crear
                      TextFormField(
                        controller: passCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Contraseña *'),
                        obscureText: true,
                        validator: (v) => user == null && v!.length < 6
                            ? 'Mínimo 6 caracteres'
                            : null,
                      ),
                    if (user == null) const SizedBox(height: 8),
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
                          title:
                              Text(r.$2, style: const TextStyle(fontSize: 13)),
                          value: selectedRoles.contains(r.$1),
                          activeColor: BsaTheme.primary,
                          onChanged: (v) => setDState(() {
                            if (v!)
                              selectedRoles.add(r.$1);
                            else
                              selectedRoles.remove(r.$1);
                          }),
                        )),
                  ],
                ),
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
                try {
                  if (user == null) {
                    // Crear nuevo usuario
                    await auth.apiService.createUser({
                      'email': emailCtrl.text.trim(),
                      'full_name': nameCtrl.text.trim(),
                      'password': passCtrl.text,
                      'position': posCtrl.text.trim(),
                      'roles': selectedRoles,
                    });
                  } else {
                    // Editar usuario existente
                    await auth.apiService.updateUser(user['id'] as int, {
                      if (nameCtrl.text.isNotEmpty)
                        'full_name': nameCtrl.text.trim(),
                      if (posCtrl.text.isNotEmpty)
                        'position': posCtrl.text.trim(),
                    });
                    // Actualizar roles si cambiaron
                    await auth.apiService
                        .updateUserRoles(user['id'] as int, selectedRoles);
                  }
                  if (dCtx.mounted) Navigator.pop(dCtx);
                } catch (e) {
                  if (dCtx.mounted)
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: Text(user == null ? 'Crear' : 'Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}
