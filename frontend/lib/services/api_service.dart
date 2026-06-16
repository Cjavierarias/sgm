import 'package:dio/dio.dart';
import '../config/app_config.dart';

/// Servicio HTTP centralizado para comunicarse con el API SGM.
///
/// Usa [AppConfig.apiBaseUrl] como URL base (configurable via --dart-define).
/// Maneja autenticación Bearer automáticamente con [setAuthToken].
class ApiService {
  late final Dio _dio;
  bool _initialized = false;

  ApiService() {
    _dio = Dio();
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _dio.options = BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout:
          const Duration(seconds: AppConfig.connectTimeoutSeconds),
      receiveTimeout:
          const Duration(seconds: AppConfig.receiveTimeoutSeconds),
      headers: {'Accept': 'application/json'},
    );
    _initialized = true;
  }

  void setAuthToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  /// Extrae el mensaje de error de una DioException y lanza Exception.
  Never _handleDioError(DioException e) {
    final detail = e.response?.data;
    String msg;
    if (detail is Map) {
      msg = detail['detail']?.toString() ?? 'Error del servidor';
    } else if (detail is String) {
      msg = detail;
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      msg = 'Tiempo de conexión agotado. Verificá tu red.';
    } else if (e.type == DioExceptionType.connectionError) {
      msg = 'No se pudo conectar al servidor.';
    } else {
      msg = 'Error de red: ${e.message}';
    }
    throw Exception(msg);
  }

  // ─── AUTH ────────────────────────────────────────────────────────────────

  Future<String> login(String email, String password) async {
    await _ensureInitialized();
    try {
      final response = await _dio.post(
        '/auth/login',
        data: 'username=$email&password=$password',
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final token = response.data['access_token'] as String?;
      if (token == null || token.isEmpty) throw Exception('No se recibió token');
      return token;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    await _ensureInitialized();
    final r = await _dio.get('/auth/me');
    return r.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getUsers(
      {int skip = 0, int limit = 100}) async {
    await _ensureInitialized();
    final r = await _dio.get('/auth/users',
        queryParameters: {'skip': skip, 'limit': limit});
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> data) async {
    await _ensureInitialized();
    final r = await _dio.post('/auth/users', data: data);
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateUserRoles(
      int userId, List<String> roles) async {
    await _ensureInitialized();
    final r = await _dio
        .put('/auth/users/$userId/roles', data: {'roles': roles});
    return r.data as Map<String, dynamic>;
  }

  // ─── DASHBOARD ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboardSummary() async {
    await _ensureInitialized();
    final r = await _dio.get('/dashboard/summary');
    return r.data as Map<String, dynamic>;
  }

  // ─── WORK ORDERS ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getWorkOrders(
      {int skip = 0, int limit = 100}) async {
    await _ensureInitialized();
    final r = await _dio.get('/work-orders/',
        queryParameters: {'skip': skip, 'limit': limit});
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getWorkOrder(int id) async {
    await _ensureInitialized();
    final r = await _dio.get('/work-orders/$id');
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createWorkOrder(
      Map<String, dynamic> data) async {
    await _ensureInitialized();
    final r = await _dio.post('/work-orders/', data: data);
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateWorkOrder(
      int id, Map<String, dynamic> data) async {
    await _ensureInitialized();
    final r = await _dio.put('/work-orders/$id', data: data);
    return r.data as Map<String, dynamic>;
  }

  Future<void> updateWorkOrderStatus(int id, String status,
      {String? comment}) async {
    await _ensureInitialized();
    await _dio.put('/work-orders/$id/status',
        data: {'status': status, 'comment': comment});
  }

  Future<Map<String, dynamic>> addWorkOrderComment(
      int id, String content) async {
    await _ensureInitialized();
    final r =
        await _dio.post('/work-orders/$id/comments', data: {'content': content});
    return r.data as Map<String, dynamic>;
  }

  // ─── EQUIPMENTS ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getEquipments(
      {int skip = 0, int limit = 200}) async {
    await _ensureInitialized();
    final r = await _dio.get('/equipments',
        queryParameters: {'skip': skip, 'limit': limit});
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getEquipment(int id) async {
    await _ensureInitialized();
    final r = await _dio.get('/equipments/$id');
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createEquipment(
      Map<String, dynamic> data) async {
    await _ensureInitialized();
    final r = await _dio.post('/equipments', data: data);
    return r.data as Map<String, dynamic>;
  }

  // ─── NOTIFICATIONS ───────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getNotifications() async {
    await _ensureInitialized();
    final r = await _dio.get('/notifications/');
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<void> markNotificationRead(int id) async {
    await _ensureInitialized();
    await _dio.put('/notifications/$id/read');
  }

  Future<void> markAllNotificationsRead() async {
    await _ensureInitialized();
    await _dio.put('/notifications/read-all');
  }


  // ─── SPARE PARTS ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSpareParts(
      {bool lowStockOnly = false}) async {
    await _ensureInitialized();
    final r = await _dio.get('/spare-parts/',
        queryParameters: lowStockOnly ? {'low_stock_only': true} : null);
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getSparePart(int id) async {
    await _ensureInitialized();
    final r = await _dio.get('/spare-parts/$id');
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createSparePart(
      Map<String, dynamic> data) async {
    await _ensureInitialized();
    try {
      final r = await _dio.post('/spare-parts/', data: data);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }
  Future<Map<String, dynamic>> sparePartEntry(
      int id, double qty, String? notes) async {
    await _ensureInitialized();
    final r = await _dio.post('/spare-parts/$id/entry',
        data: {'quantity': qty, if (notes != null && notes.isNotEmpty) 'notes': notes});
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sparePartExit(
      int id, double qty, String? notes) async {
    await _ensureInitialized();
    final r = await _dio.post('/spare-parts/$id/exit',
        data: {'quantity': qty, if (notes != null && notes.isNotEmpty) 'notes': notes});
    return r.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getSparePartRequests() async {
    await _ensureInitialized();
    final r = await _dio.get('/spare-part-requests/');
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createSparePartRequest(
      Map<String, dynamic> data) async {
    await _ensureInitialized();
    final r = await _dio.post('/spare-part-requests/', data: data);
    return r.data as Map<String, dynamic>;
  }

  Future<void> approveSparePartRequest(int id) async {
    await _ensureInitialized();
    await _dio.put('/spare-part-requests/$id/approve');
  }

  Future<void> deliverSparePartRequest(int id) async {
    await _ensureInitialized();
    await _dio.put('/spare-part-requests/$id/deliver');
  }

  Future<void> rejectSparePartRequest(int id) async {
    await _ensureInitialized();
    await _dio.put('/spare-part-requests/$id/reject');
  }
}