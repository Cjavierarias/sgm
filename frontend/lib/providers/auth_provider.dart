import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  String _token = '';
  String _email = '';
  String _fullName = '';
  int? _companyId;
  List<String> _roles = [];
  bool _isLoading = false;
  String _errorMessage = '';

  String get token => _token;
  String get email => _email;
  String get fullName => _fullName;
  int? get companyId => _companyId;
  List<String> get roles => _roles;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  bool get isAuthenticated => _token.isNotEmpty;

  // Helpers de roles
  bool get isAdmin => _roles.contains('admin');
  bool get isMaintenanceManager => _roles.contains('maintenance_manager');
  bool get isTechnician => _roles.contains('technician');
  bool get isWarehouse => _roles.contains('warehouse');
  bool get isPurchasing => _roles.contains('purchasing');
  bool get isHR => _roles.contains('hr');

  bool hasRole(String role) => _roles.contains(role);
  bool hasAnyRole(List<String> checkRoles) =>
      checkRoles.any((r) => _roles.contains(r));

  AuthProvider() {
    _apiService.setAuthToken(_token);
  }

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

  /// Login / registro con Google Sign-In.
  Future<void> loginWithGoogle({String? companyName}) async {
    _setLoading(true);
    _setError('');
    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );
      final account = await googleSignIn.signIn();
      if (account == null) {
        _setError('Inicio de sesión cancelado');
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        _setError('No se pudo obtener token de Google');
        return;
      }
      final token = await _apiService.loginWithGoogle(
        idToken,
        companyName: companyName,
      );
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

  Future<void> logout() async {
    _clearAuth();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    notifyListeners();
  }

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
    _fullName = userData['full_name'] as String? ?? _email;
    _companyId = userData['company_id'] is int
        ? userData['company_id'] as int
        : int.tryParse(userData['company_id']?.toString() ?? '');
    final rolesRaw = userData['roles'];
    if (rolesRaw is List) {
      _roles = rolesRaw.map((r) => r.toString()).toList();
    }
    notifyListeners();
  }

  /// Setea un token externo (ej: tras aceptar invitación) y carga el usuario.
  Future<void> setTokenAndLoad(String token) async {
    _token = token;
    _apiService.setAuthToken(_token);
    await _saveToken(_token);
    await _loadUserInfo();
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
    _fullName = '';
    _companyId = null;
    _roles = [];
    _errorMessage = '';
    _apiService.setAuthToken(null);
  }

  ApiService get apiService => _apiService;
}
