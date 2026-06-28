import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// Pantalla de calendario compartido.
/// Muestra eventos de la empresa (planes de mantenimiento sincronizados con Google Calendar).
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late ApiService _api;
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  DateTime _focusedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _api = ApiService()..setAuthToken(auth.token);
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _loading = true);
    try {
      final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
      final lastDay  = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
      _events = await _api.getCalendarEvents(
        dateFrom: '${firstDay.year}-${firstDay.month.toString().padLeft(2, '0')}-${firstDay.day.toString().padLeft(2, '0')}',
        dateTo:   '${lastDay.year}-${lastDay.month.toString().padLeft(2, '0')}-${lastDay.day.toString().padLeft(2, '0')}',
      );
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _changeMonth(int delta) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta, 1);
    });
    _loadEvents();
  }

  List<Map<String, dynamic>> _eventsForDay(int day) {
    return _events.where((e) {
      final startStr = e['start_at'] as String? ?? '';
      try {
        final dt = DateTime.parse(startStr);
        return dt.year == _focusedMonth.year && dt.month == _focusedMonth.month && dt.day == day;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isAdmin = auth.isAdmin;

    return Scaffold(
      backgroundColor: BsaTheme.background,
      appBar: AppBar(
        title: const Text('Calendario'),
        backgroundColor: BsaTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _changeMonth(-1),
          ),
          Text(
            '${_monthName(_focusedMonth.month)} ${_focusedMonth.year}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _changeMonth(1),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Grilla del calendario ──────────────────────────────────
                _buildMonthGrid(),
                const SizedBox(height: 8),
                // ── Lista de eventos del mes ───────────────────────────────
                Expanded(
                  child: _buildEventsList(),
                ),
              ],
            ),
      floatingActionButton: isAdmin ? FloatingActionButton.extended(
        onPressed: _showCreateCalendarDialog,
        icon: const Icon(Icons.sync),
        label: const Text('Sincronizar Google'),
        backgroundColor: BsaTheme.secondary,
      ) : null,
    );
  }

  Widget _buildMonthGrid() {
    final firstDay   = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay    = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final startWeekday = firstDay.weekday % 7;  // 0 = domingo

    final days = <Widget>[];
    // Headers
    for (final d in ['D', 'L', 'M', 'M', 'J', 'V', 'S']) {
      days.add(Center(
        child: Text(d, style: const TextStyle(fontWeight: FontWeight.bold, color: BsaTheme.textSecondary, fontSize: 12)),
      ));
    }
    // Espacios antes del día 1
    for (int i = 0; i < startWeekday; i++) {
      days.add(const SizedBox());
    }
    // Días del mes
    for (int day = 1; day <= lastDay.day; day++) {
      final dayEvents = _eventsForDay(day);
      days.add(Container(
        decoration: BoxDecoration(
          color: dayEvents.isNotEmpty ? BsaTheme.primary.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 12,
                fontWeight: dayEvents.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                color: dayEvents.isNotEmpty ? BsaTheme.primary : BsaTheme.textPrimary,
              ),
            ),
            if (dayEvents.isNotEmpty)
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(
                  color: BsaTheme.secondary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(8),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: days,
      ),
    );
  }

  Widget _buildEventsList() {
    if (_events.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 48, color: BsaTheme.textSecondary),
            SizedBox(height: 12),
            Text(
              'No hay eventos este mes',
              style: TextStyle(color: BsaTheme.textSecondary),
            ),
            SizedBox(height: 8),
            Text(
              'Sincronizá tus planes de mantenimiento con Google Calendar',
              style: TextStyle(color: BsaTheme.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _events.length,
      itemBuilder: (context, i) {
        final ev = _events[i];
        final synced = ev['synced'] == true;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: (BsaTheme.primary).withValues(alpha: 0.15),
              child: Icon(
                synced ? Icons.event_available : Icons.event,
                color: BsaTheme.primary,
              ),
            ),
            title: Text(ev['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${ev['start_at']}${ev['description'] != null ? '\n${ev['description']}' : ''}',
              style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: synced
                ? const Icon(Icons.cloud_done, color: BsaTheme.secondary, size: 20)
                : null,
          ),
        );
      },
    );
  }

  Future<void> _showCreateCalendarDialog() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final emailCtrl = TextEditingController(text: auth.email);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear calendario de Google'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Se creará un calendario compartido en Google Calendar para tu empresa '
              'y se compartirá con tu email. Luego podrás sincronizar planes de mantenimiento.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'Tu email de Google'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
        ],
      ),
    );
    if (result != true) return;

    try {
      await _api.createCompanyCalendar(emailCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Calendario creado. Revisá tu email de Google.'),
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
    }
  }

  String _monthName(int month) {
    const names = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                   'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return names[month - 1];
  }
}
