import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show BsaTheme;
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/api_service.dart';

/// Pantalla de gestión de suscripción y pagos.
///
/// Solo visible para el administrador de la empresa.
/// Muestra:
///  - Estado actual de la suscripción
///  - Días restantes
///  - Botón de pago (redirige a Mercado Pago)
///  - Historial de facturación
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late SubscriptionProvider _subProvider;
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _subProvider = SubscriptionProvider(ApiService()..setAuthToken(auth.token));
    _subProvider.loadStatus().then((_) => _loadHistory());
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      _history = await _subProvider.loadHistory();
    } catch (_) {}
    setState(() => _loadingHistory = false);
  }

  Future<void> _openPayment(String plan) async {
    try {
      final data = await _subProvider.createCheckout(plan);
      final url = data['init_point'] as String? ?? '';
      if (url.isEmpty) throw Exception('No se recibio URL de pago');
      // Abre Mercado Pago en nueva pestana (Flutter Web usa dart:html)
      html.window.open(url, '_blank');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: BsaTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: BsaTheme.background,
      appBar: AppBar(
        title: const Text('Suscripción SGM'),
        backgroundColor: BsaTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ChangeNotifierProvider.value(
        value: _subProvider,
        child: Consumer<SubscriptionProvider>(
          builder: (context, sub, _) {
            if (sub.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (sub.error.isNotEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: BsaTheme.error, size: 48),
                    const SizedBox(height: 16),
                    Text(sub.error, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: sub.loadStatus,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              );
            }

            final info = sub.info;
            if (info == null) return const SizedBox();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Estado actual ───────────────────────────────────────
                  _StatusCard(info: info),
                  const SizedBox(height: 24),

                  // ── Planes de pago (solo admin y si no está activo) ─────
                  if (auth.isAdmin &&
                      (info.status == 'trial' ||
                          info.status == 'grace' ||
                          info.status == 'suspended')) ...[
                    _SectionTitle(icon: Icons.payment, title: 'Planes de pago'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _PlanCard(
                            title: 'Mensual',
                            price: 'USD 5',
                            period: 'por mes',
                            highlighted: false,
                            onTap: () => _openPayment('monthly'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _PlanCard(
                            title: 'Anual',
                            price: 'USD 50',
                            period: 'por año',
                            savings: '2 meses gratis',
                            highlighted: true,
                            onTap: () => _openPayment('annual'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _IncludesList(),
                    const SizedBox(height: 24),
                  ],

                  // ── Aviso de gracia / suspensión ────────────────────────
                  if (info.status == 'grace') ...[
                    _AlertBanner(
                      icon: Icons.warning_amber_rounded,
                      color: BsaTheme.warning,
                      title: 'Período de gracia activo',
                      message:
                          'Tu suscripción venció. Tus datos se conservarán hasta el '
                          '${info.graceEnd ?? "—"}. Realizá el pago para continuar '
                          'usando SGM sin interrupciones.',
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (info.status == 'suspended') ...[
                    _AlertBanner(
                      icon: Icons.block_rounded,
                      color: BsaTheme.error,
                      title: 'Cuenta suspendida',
                      message:
                          'Tu cuenta fue suspendida por falta de pago. Los datos '
                          'operativos ya no están disponibles. Para reactivar tu '
                          'cuenta contactá a soporte@bsaconsultora.com.',
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Historial ───────────────────────────────────────────
                  _SectionTitle(icon: Icons.history, title: 'Historial de pagos'),
                  const SizedBox(height: 12),
                  if (_loadingHistory)
                    const Center(child: CircularProgressIndicator())
                  else if (_history.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No hay movimientos de facturación registrados aún.',
                        style: TextStyle(color: BsaTheme.textSecondary),
                      ),
                    )
                  else
                    ..._history.map((e) => _HistoryTile(event: e)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final SubscriptionInfo info;
  const _StatusCard({required this.info});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_rounded, color: info.statusColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Estado de la suscripción',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: BsaTheme.textPrimary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoRow(label: 'Estado',   value: info.statusLabel,    color: info.statusColor),
            _InfoRow(label: 'Plan',     value: info.planLabel),
            _InfoRow(
              label: 'Vence',
              value: info.expiryDateLabel,
              color: info.daysRemaining <= 7 && info.canUsePlatform
                  ? BsaTheme.warning
                  : null,
            ),
            _InfoRow(
              label: 'Días restantes',
              value: info.canUsePlatform ? '${info.daysRemaining} días' : '—',
              color: info.daysRemaining <= 7 && info.canUsePlatform
                  ? BsaTheme.warning
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _InfoRow({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: BsaTheme.textSecondary, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: color ?? BsaTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final String? savings;
  final bool highlighted;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.period,
    this.savings,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: highlighted ? BsaTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted ? BsaTheme.primary : BsaTheme.border,
            width: highlighted ? 2 : 1,
          ),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: BsaTheme.primary.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (savings != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: BsaTheme.secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  savings!,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            if (savings != null) const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: highlighted ? Colors.white : BsaTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              price,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 28,
                color: highlighted ? Colors.white : BsaTheme.primary,
              ),
            ),
            Text(
              period,
              style: TextStyle(
                color: highlighted ? Colors.white70 : BsaTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: highlighted ? Colors.white : BsaTheme.primary,
                  foregroundColor: highlighted ? BsaTheme.primary : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Pagar con Mercado Pago'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncludesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const features = [
      '1 administrador',
      '1 empresa registrada',
      'Colaboradores ilimitados (invitados)',
      'Equipos, OT, repuestos y compras',
      'Soporte por email',
    ];
    return Card(
      color: const Color(0xFFEFF8FF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Todos los planes incluyen:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: BsaTheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: BsaTheme.secondary, size: 18),
                    const SizedBox(width: 8),
                    Text(f, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _AlertBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: color, fontSize: 14)),
                const SizedBox(height: 4),
                Text(message,
                    style: const TextStyle(fontSize: 13, color: BsaTheme.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: BsaTheme.primary, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: BsaTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> event;
  const _HistoryTile({required this.event});

  IconData get _icon {
    final t = event['event_type'] as String? ?? '';
    if (t.contains('approved')) return Icons.check_circle_rounded;
    if (t.contains('rejected') || t.contains('cancelled')) return Icons.cancel_rounded;
    if (t.contains('trial')) return Icons.hourglass_empty_rounded;
    if (t.contains('purged') || t.contains('suspended')) return Icons.delete_rounded;
    return Icons.receipt_long_rounded;
  }

  Color get _color {
    final t = event['event_type'] as String? ?? '';
    if (t.contains('approved') || t.contains('trial_started')) return BsaTheme.success;
    if (t.contains('rejected') || t.contains('cancelled') || t.contains('purged')) return BsaTheme.error;
    if (t.contains('expired')) return BsaTheme.warning;
    return BsaTheme.textSecondary;
  }

  String get _label {
    final t = event['event_type'] as String? ?? '';
    const labels = {
      'trial_started':          'Prueba gratuita iniciada',
      'trial_expired':          'Prueba vencida',
      'payment_approved':       'Pago aprobado',
      'payment_rejected':       'Pago rechazado',
      'payment_pending':        'Pago pendiente',
      'payment_cancelled':      'Pago cancelado',
      'subscription_cancelled': 'Suscripción cancelada',
      'data_purged':            'Datos purgados',
    };
    return labels[t] ?? t;
  }

  @override
  Widget build(BuildContext context) {
    final amount = event['amount_usd'];
    final date   = event['created_at'] as String? ?? '';
    final notes  = event['notes'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _color.withOpacity(0.1),
          child: Icon(_icon, color: _color, size: 20),
        ),
        title: Text(_label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          notes.isNotEmpty ? '$date\n$notes' : date,
          style: const TextStyle(fontSize: 12, color: BsaTheme.textSecondary),
        ),
        trailing: amount != null
            ? Text(
                'USD ${(amount as num).toStringAsFixed(2)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: BsaTheme.primary,
                    fontSize: 13),
              )
            : null,
      ),
    );
  }
}
