import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/equipment.dart';

class ApiService {
  final Dio _dio;
  String? _token;

  ApiService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: _resolveBaseUrl(dotenv.env['API_BASE_URL']),
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
  }

  /// Actualiza el token usado en el interceptor para todas las solicitudes.
  void setAuthToken(String? token) {
    _token = token;
  }

  static String _resolveBaseUrl(String? envUrl) {
    final fallback = 'http://localhost:8000';
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }

    if (kIsWeb) {
      final current = Uri.base;
      if (current.host.isNotEmpty && current.host != 'localhost' && current.host != '127.0.0.1') {
        final scheme = current.scheme == 'https' ? 'https' : 'http';
        if (current.host.endsWith('.app.github.dev')) {
          final backendHost = current.host.replaceFirst(
            RegExp(r'-\d+\.app\.github\.dev\$'),
            '-8000.app.github.dev',
          );
          return Uri(scheme: scheme, host: backendHost).toString();
        }
        return Uri(scheme: scheme, host: current.host, port: 8000).toString();
      }
    }
    return fallback;
  }

  /// Llama al backend para iniciar sesión y obtener el token JWT.
  Future<String> login(String email, String password) async {
    try {
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
        throw Exception('No se recibió token del servidor.');
      }
      return token;
    } on DioError catch (error) {
      final serverMessage = error.response?.data?['detail'];
      final message = serverMessage is String ? serverMessage : error.message;
      throw Exception('Error de login: $message');
    }
  }

  /// Obtiene la lista de equipos para la compañía del usuario autenticado.
  Future<List<Equipment>> getEquipments() async {
    try {
      final response = await _dio.get('/equipments');
      final payload = response.data as List<dynamic>;
      return payload
          .map((item) => Equipment.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } on DioError catch (error) {
      final serverMessage = error.response?.data?['detail'];
      final message = serverMessage is String ? serverMessage : error.message;
      throw Exception('Error cargando equipos: $message');
    }
  }

  /// Obtiene el detalle de un equipo por su ID.
  Future<Equipment> getEquipmentById(int equipmentId) async {
    try {
      final response = await _dio.get('/equipments/$equipmentId');
      return Equipment.fromJson(Map<String, dynamic>.from(response.data as Map));
    } on DioError catch (error) {
      final serverMessage = error.response?.data?['detail'];
      final message = serverMessage is String ? serverMessage : error.message;
      throw Exception('Error cargando el equipo: $message');
    }
  }

  /// Obtiene el perfil del usuario actual usando el token Bearer.
  Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      final response = await _dio.get('/auth/me');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioError catch (error) {
      final serverMessage = error.response?.data?['detail'];
      final message = serverMessage is String ? serverMessage : error.message;
      throw Exception('No se pudo cargar el usuario: $message');
    }
  }
}
