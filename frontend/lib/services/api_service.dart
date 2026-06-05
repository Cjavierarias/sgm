import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'env_helper.dart' show getPlatformEnv;

import '../models/equipment.dart';

class ApiService {
  final Dio _dio;
  String? _token;

  ApiService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: '',
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            headers: {'Content-Type': 'application/json'},
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null && _token!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          handler.next(options);
        },
      ),
    );

    // Inicializa baseUrl en background (no bloquea el constructor).
    _initBaseUrl();
  }

  /// Actualiza el token usado en el interceptor para todas las solicitudes.
  void setAuthToken(String? token) {
    _token = token;
  }

  Future<void> _initBaseUrl() async {
    try {
      // Intentar cargar desde la raíz y luego desde web/.env (fallback para Flutter Web).
      await dotenv.load(fileName: '.env');
      print('[ApiService] ✓ Loaded .env from root');
    } catch (e) {
      print('[ApiService] ⚠ Could not load .env from root: $e');
    }
    try {
      await dotenv.load(fileName: 'web/.env');
      print('[ApiService] ✓ Loaded web/.env');
    } catch (e) {
      print('[ApiService] ⚠ Could not load web/.env: $e');
    }

    final envUrl = dotenv.env['API_BASE_URL'] ?? getPlatformEnv('API_BASE_URL');
    print('[ApiService] 📌 API_BASE_URL from dotenv/platform: "$envUrl"');

    final resolved = _resolveBaseUrl(envUrl);
    print('[ApiService] ✅ Resolved baseUrl: "$resolved"');
    if (kIsWeb) {
      print('[ApiService] 🌐 Running on Web - Uri.base: ${Uri.base}');
    } else {
      print('[ApiService] 📱 Running on Mobile/Desktop');
    }

    _dio.options.baseUrl = resolved;
  }

  static String _resolveBaseUrl(String? envUrl) {
    // Preferir valor explícito de env si está presente.
    if (envUrl != null && envUrl.isNotEmpty) {
      var candidate = envUrl.trim();
      if (!candidate.startsWith(RegExp(r'https?://'))) {
        candidate = 'https://$candidate';
      }
      print('[ApiService._resolveBaseUrl] Using envUrl: $candidate');
      return candidate;
    }

    // Si estamos en web, intentar deducir la URL del host de Codespaces.
    if (kIsWeb) {
      final current = Uri.base;
      print('[ApiService._resolveBaseUrl] Web mode detected. Uri.base: $current');
      print('[ApiService._resolveBaseUrl] current.host: ${current.host}');
      
      if (current.host.isNotEmpty && current.host != 'localhost' && current.host != '127.0.0.1') {
        // Priorizar https
        final scheme = 'https';

        // Detecta hosts como: <code>-8080.app.github.dev o <code>-8000.app.github.dev
        final host = current.host;
        print('[ApiService._resolveBaseUrl] Detected non-localhost host: $host');
        
        // Reemplaza el sufijo -<puerto>.app.github.dev por -8000.app.github.dev
        final backendHost = host.replaceFirst(RegExp(r'-\d+\.app\.github\.dev\$'), '-8000.app.github.dev');
        if (backendHost != host) {
          final result = Uri(scheme: scheme, host: backendHost).toString();
          print('[ApiService._resolveBaseUrl] Matched Codespaces pattern. Result: $result');
          return result;
        }

        // Si termina en .app.github.dev pero no contiene -<num>, añadir -8000
        if (host.endsWith('.app.github.dev')) {
          final maybe = host.replaceFirst('.app.github.dev', '-8000.app.github.dev');
          final result = Uri(scheme: scheme, host: maybe).toString();
          print('[ApiService._resolveBaseUrl] Added -8000 to .app.github.dev host. Result: $result');
          return result;
        }

        // Fallback: usar el mismo host pero puerto 8000
        final result = Uri(scheme: scheme, host: host, port: 8000).toString();
        print('[ApiService._resolveBaseUrl] Using same host with port 8000. Result: $result');
        return result;
      } else {
        print('[ApiService._resolveBaseUrl] Host is localhost or empty, using HTTPS fallback');
      }
    } else {
      print('[ApiService._resolveBaseUrl] Not web mode, using localhost fallback');
    }

    // Último recurso: localhost a través de Nginx en /api.
    const fallback = 'http://localhost/api';
    print('[ApiService._resolveBaseUrl] Using fallback: $fallback');
    return fallback;
  }

  /// Llama al backend para iniciar sesión y obtener el token JWT.
  Future<String> login(String email, String password) async {
    try {
      print('[ApiService.login] 🔐 Attempting login for: $email');
      print('[ApiService.login] Using baseUrl: ${_dio.options.baseUrl}');
      final response = await _dio.post(
        '/auth/login',
        data: 'username=$email&password=$password',
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final token = data['access_token'] as String?;
      if (token == null || token.isEmpty) {
        print('[ApiService.login] ❌ No access_token received from server');
        throw Exception('No se recibió token del servidor.');
      }
      print('[ApiService.login] ✅ Login successful, token received');
      return token;
    } on DioError catch (error) {
      print('[ApiService.login] ❌ DioError: ${error.message}');
      print('[ApiService.login] Response status: ${error.response?.statusCode}');
      print('[ApiService.login] Response data: ${error.response?.data}');
      final serverMessage = error.response?.data?['detail'];
      final message = serverMessage is String ? serverMessage : error.message;
      throw Exception('Error de login: $message');
    } catch (e) {
      print('[ApiService.login] ❌ Unexpected error: $e');
      rethrow;
    }
  }

  /// Obtiene la lista de equipos para la compañía del usuario autenticado.
  Future<List<Equipment>> getEquipments() async {
    try {
      print('[ApiService.getEquipments] 📦 Fetching equipments...');
      final response = await _dio.get('/equipments');
      final payload = response.data as List<dynamic>;
      print('[ApiService.getEquipments] ✅ Got ${payload.length} equipments');
      return payload
          .map((item) => Equipment.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } on DioError catch (error) {
      print('[ApiService.getEquipments] ❌ DioError: ${error.message}');
      print('[ApiService.getEquipments] Response status: ${error.response?.statusCode}');
      final serverMessage = error.response?.data?['detail'];
      final message = serverMessage is String ? serverMessage : error.message;
      throw Exception('Error cargando equipos: $message');
    }
  }

  /// Obtiene el detalle de un equipo por su ID.
  Future<Equipment> getEquipmentById(int equipmentId) async {
    try {
      print('[ApiService.getEquipmentById] 🔍 Fetching equipment $equipmentId...');
      final response = await _dio.get('/equipments/$equipmentId');
      print('[ApiService.getEquipmentById] ✅ Equipment $equipmentId loaded');
      return Equipment.fromJson(Map<String, dynamic>.from(response.data as Map));
    } on DioError catch (error) {
      print('[ApiService.getEquipmentById] ❌ DioError: ${error.message}');
      final serverMessage = error.response?.data?['detail'];
      final message = serverMessage is String ? serverMessage : error.message;
      throw Exception('Error cargando el equipo: $message');
    }
  }

  /// Obtiene el perfil del usuario actual usando el token Bearer.
  Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      print('[ApiService.getCurrentUser] 👤 Fetching current user...');
      final response = await _dio.get('/auth/me');
      print('[ApiService.getCurrentUser] ✅ Current user loaded');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioError catch (error) {
      print('[ApiService.getCurrentUser] ❌ DioError: ${error.message}');
      final serverMessage = error.response?.data?['detail'];
      final message = serverMessage is String ? serverMessage : error.message;
      throw Exception('No se pudo cargar el usuario: $message');
    }
  }
}
