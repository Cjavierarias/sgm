import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Estado de la suscripción de la empresa.
class SubscriptionInfo {
  final int companyId;
  final String status; // trial | active | grace | suspended | cancelled
  final String? plan;  // monthly | annual
  final String? trialEnd;
  final String? currentPeriodEnd;
  final String? graceEnd;
  final int daysRemaining;
  final bool canUsePlatform;
  final String mpPublicKey;

  const SubscriptionInfo({
    required this.companyId,
    required this.status,
    this.plan,
    this.trialEnd,
    this.currentPeriodEnd,
    this.graceEnd,
    required this.daysRemaining,
    required this.canUsePlatform,
    required this.mpPublicKey,
  });

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionInfo(
      companyId:         json['company_id'] as int,
      status:            json['status'] as String,
      plan:              json['plan'] as String?,
      trialEnd:          json['trial_end'] as String?,
      currentPeriodEnd:  json['current_period_end'] as String?,
      graceEnd:          json['grace_end'] as String?,
      daysRemaining:     json['days_remaining'] as int,
      canUsePlatform:    json['can_use_platform'] as bool,
      mpPublicKey:       json['mp_public_key'] as String? ?? '',
    );
  }

  /// Texto descriptivo del estado
  String get statusLabel {
    switch (status) {
      case 'trial':
        return 'Período de prueba';
      case 'active':
        return 'Activo';
      case 'grace':
        return 'Vencido — período de gracia';
      case 'suspended':
        return 'Suspendido';
      case 'cancelled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  String get planLabel {
    if (plan == 'monthly') return 'Mensual — USD 5/mes';
    if (plan == 'annual')  return 'Anual — USD 50/año';
    return '—';
  }

  /// Color del badge de estado
  Color get statusColor {
    switch (status) {
      case 'trial':
        return const Color(0xFF0077B6);
      case 'active':
        return const Color(0xFF2D9F5E);
      case 'grace':
        return const Color(0xFFF59E0B);
      case 'suspended':
      case 'cancelled':
        return const Color(0xFFD32F2F);
      default:
        return const Color(0xFF5A7184);
    }
  }

  String get expiryDateLabel {
    if (status == 'trial')  return trialEnd ?? '—';
    if (status == 'active') return currentPeriodEnd ?? '—';
    if (status == 'grace')  return graceEnd ?? '—';
    return '—';
  }
}

/// Provider que gestiona el estado de suscripción.
class SubscriptionProvider extends ChangeNotifier {
  final ApiService _api;

  SubscriptionInfo? _info;
  bool _isLoading = false;
  String _error = '';

  SubscriptionInfo? get info      => _info;
  bool get isLoading              => _isLoading;
  String get error                => _error;
  bool get canUsePlatform         => _info?.canUsePlatform ?? true;

  SubscriptionProvider(this._api);

  Future<void> loadStatus() async {
    _isLoading = true;
    _error = '';
    notifyListeners();
    try {
      final data = await _api.getBillingStatus();
      _info = SubscriptionInfo.fromJson(data);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createCheckout(String plan) async {
    return await _api.createBillingCheckout(plan);
  }

  Future<Map<String, dynamic>> createSubscription(String plan, String email) async {
    return await _api.createBillingSubscription(plan, email);
  }

  Future<List<Map<String, dynamic>>> loadHistory() async {
    return await _api.getBillingHistory();
  }
}
