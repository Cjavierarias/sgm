import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/equipment.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  String _token = '';
  String _email = '';
  int? _companyId;
  bool _isLoading = false;
  String _errorMessage = '';

  String get token => _token;
  String get email => _email;
  int? get companyId => _companyId;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  bool get isAuthenticated => _token.isNotEmpty;

  AuthProvider() {
    _apiService.setAuthToken(_token);
  }

  /// Inicia sesión y guarda el token en almacenamiento local.
  Future<void> login(String email, String password) async {
    _setLoading(true);
    _setError('');

    try {
      final token = await _apiService.login(email, password);
      _token = token;
      _apiService.setAuthToken(_token);
      await _saveToken(_token);
      await _loadUserInfo();
    } catch (error) {
      _setError(error.toString().replaceFirst('Exception: ', ''));
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Limpia el estado de autenticación y el token guardado.
  Future<void> logout() async {
    _clearAuth();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    notifyListeners();
  }

  /// Recarga el token guardado y verifica si sigue siendo válido.
  Future<void> refreshToken() async {
    _setLoading(true);
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString('auth_token') ?? '';

    if (storedToken.isEmpty) {
      _setLoading(false);
      return;
    }

    _token = storedToken;
    _apiService.setAuthToken(_token);

    try {
      await _loadUserInfo();
    } catch (_) {
      await logout();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadUserInfo() async {
    final userData = await _apiService.getCurrentUser();
    _email = userData['email'] as String? ?? '';
    _companyId = userData['company_id'] is int
        ? userData['company_id'] as int
        : int.tryParse(userData['company_id']?.toString() ?? '');
    notifyListeners();
  }

  Future<List<Equipment>> fetchEquipments() async {
    if (!isAuthenticated) {
      throw Exception('Usuario no autenticado');
    }
    return _apiService.getEquipments();
  }

  Future<Equipment> fetchEquipmentById(int equipmentId) async {
    if (!isAuthenticated) {
      throw Exception('Usuario no autenticado');
    }
    return _apiService.getEquipmentById(equipmentId);
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _clearAuth() {
    _token = '';
    _email = '';
    _companyId = null;
    _errorMessage = '';
    _apiService.setAuthToken(null);
  }
}
