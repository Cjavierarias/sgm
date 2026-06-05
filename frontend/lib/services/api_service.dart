import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/equipment.dart';

class ApiService {
  late final Dio _dio;
  bool _initialized = false;
  
  ApiService() {
    _dio = Dio();
  }
  
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    // En Codespaces, la URL cambia. Reemplazá esto con tu URL real del puerto 8000.
    // La encontrás en la pestaña "Ports" de VS Code → puerto 8000 → Forward Address
    const baseUrl = 'https://turbo-system-v6rq95vvxwrgfpxqj-8000.app.github.dev';

    print('[ApiService] FINAL BASE URL => $baseUrl');

    _dio.options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    );

    _initialized = true;
  }

  /// Establece el token de autenticación para las solicitudes futuras.
  void setAuthToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  /// Llama al backend para iniciar sesión y obtener el token JWT.
  Future<String> login(String email, String password) async {
    await _ensureInitialized();

    try {
      print('[ApiService.login] 🔐 Attempting login for: $email');
      print('[ApiService.login] BASE URL BEFORE REQUEST => ${_dio.options.baseUrl}');
      print('[ApiService.login] FULL REQUEST URL => ${_dio.options.baseUrl}/auth/login');

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

    } on DioException catch (error) {
      print('[ApiService.login] ❌ DioException: ${error.message}');
      print('[ApiService.login] REQUEST URL => ${error.requestOptions.uri}');
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

  /// Obtiene la información del usuario actual.
  Future<Map<String, dynamic>> getCurrentUser() async {
    await _ensureInitialized();

    try {
      final response = await _dio.get('/auth/me');
      return response.data as Map<String, dynamic>;
    } on DioException catch (error) {
      final serverMessage = error.response?.data?['detail'];
      final message = serverMessage is String ? serverMessage : error.message;
      throw Exception('Error al obtener usuario: $message');
    }
  }

  /// Obtiene la lista de equipos de la empresa.
  Future<List<Equipment>> getEquipments() async {
    await _ensureInitialized();

    try {
      final response = await _dio.get('/equipments');
      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((json) => Equipment.fromJson(json as Map<String, dynamic>)).toList();
    } on DioException catch (error) {
      final serverMessage = error.response?.data?['detail'];
      final message = serverMessage is String ? serverMessage : error.message;
      throw Exception('Error al obtener equipos: $message');
    }
  }

  /// Obtiene un equipo por su ID.
  Future<Equipment> getEquipmentById(int equipmentId) async {
    await _ensureInitialized();

    try {
      final response = await _dio.get('/equipments/$equipmentId');
      return Equipment.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      final serverMessage = error.response?.data?['detail'];
      final message = serverMessage is String ? serverMessage : error.message;
      throw Exception('Error al obtener equipo: $message');
    }
  }
}
