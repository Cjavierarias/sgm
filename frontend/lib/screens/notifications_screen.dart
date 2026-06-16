import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
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
      final data = await auth.apiService.getNotifications();
      if (mounted) setState(() { _items = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.apiService.markAllNotificationsRead();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((n) => n['is_read'] == false).length;
    return Scaffold(
      backgroundColor: BsaTheme.background,
      appBar: AppBar(
        title: Text('Notificaciones${unread > 0 ? ' ($unread)' : ''}'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Marcar todas leídas'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_off_outlined,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('No hay notificaciones',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, i) {
                        final n = _items[i];
                        final isRead = n['is_read'] as bool? ?? false;
                        return Card(
                          color: isRead ? Colors.white : const Color(0xFFE8F4FB),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isRead
                                    ? BsaTheme.border
                                    : BsaTheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                Icons.notifications_rounded,
                                color: isRead
                                    ? BsaTheme.textSecondary
                                    : BsaTheme.primary,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              n['title'] as String? ?? '',
                              style: TextStyle(
                                fontWeight: isRead
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n['message'] as String? ?? '',
                                    style: const TextStyle(fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(
                                  (n['created_at'] as String? ?? '').length >= 10
                                      ? (n['created_at'] as String)
                                          .substring(0, 10)
                                      : '',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            onTap: () async {
                              if (!isRead) {
                                final auth = Provider.of<AuthProvider>(context,
                                    listen: false);
                                await auth.apiService.markNotificationRead(
                                    n['id'] as int);
                                _load();
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
