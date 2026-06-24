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

  /// Registra nueva empresa + admin. Devuelve el token para auto-login.
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
    required String companyName,
  }) async {
    await _ensureInitialized();
    try {
      await _dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'full_name': fullName,
        'company_name': companyName,
      });
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  /// Login con Google usando el id_token obtenido por google_sign_in.
  Future<String> loginWithGoogle(String idToken, {String? companyName}) async {
    await _ensureInitialized();
    try {
      final response = await _dio.post('/auth/google', data: {
        'id_token': idToken,
        if (companyName != null) 'company_name': companyName,
      });
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
    final r =
        await _dio.put('/auth/users/$userId/roles', data: {'roles': roles});
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateUser(
      int userId, Map<String, dynamic> data) async {
    await _ensureInitialized();
    try {
      final r = await _dio.put('/auth/users/$userId', data: data);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
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
    try {
      final r = await _dio.post('/equipments', data: data);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> updateEquipment(
      int id, Map<String, dynamic> data) async {
    await _ensureInitialized();
    try {
      final r = await _dio.put('/equipments/$id', data: data);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
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
    try {
      final r = await _dio.post('/spare-part-requests/', data: data);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
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

  // ─── SUPPLIERS ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSuppliers() async {
    await _ensureInitialized();
    final r = await _dio.get('/suppliers/');
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createSupplier(Map<String, dynamic> data) async {
    await _ensureInitialized();
    try {
      final r = await _dio.post('/suppliers/', data: data);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> updateSupplier(int id, Map<String, dynamic> data) async {
    await _ensureInitialized();
    final r = await _dio.put('/suppliers/$id', data: data);
    return r.data as Map<String, dynamic>;
  }

  Future<void> deleteSupplier(int id) async {
    await _ensureInitialized();
    await _dio.delete('/suppliers/$id');
  }

  // ─── PURCHASE ORDERS ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPurchaseOrders(
      {String? status, int skip = 0, int limit = 100}) async {
    await _ensureInitialized();
    final r = await _dio.get('/purchase-orders/', queryParameters: {
      if (status != null) 'status': status,
      'skip': skip,
      'limit': limit,
    });
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getPurchaseOrder(int id) async {
    await _ensureInitialized();
    final r = await _dio.get('/purchase-orders/$id');
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createPurchaseOrder(Map<String, dynamic> data) async {
    await _ensureInitialized();
    try {
      final r = await _dio.post('/purchase-orders/', data: data);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<void> updatePOStatus(int id, String status) async {
    await _ensureInitialized();
    await _dio.put('/purchase-orders/$id/status', data: {'status': status});
  }

  Future<Map<String, dynamic>> receivePurchaseOrder(
      int id, List<Map<String, dynamic>> items) async {
    await _ensureInitialized();
    try {
      final r = await _dio
          .post('/purchase-orders/$id/receive', data: {'items': items});
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  // ─── INVOICES ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getInvoices() async {
    await _ensureInitialized();
    final r = await _dio.get('/invoices/');
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createInvoice(Map<String, dynamic> data) async {
    await _ensureInitialized();
    try {
      final r = await _dio.post('/invoices/', data: data);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<void> payInvoice(int id) async {
    await _ensureInitialized();
    await _dio.put('/invoices/$id/pay');
  }

  // ─── MAINTENANCE PLANS ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMaintenancePlans(
      {bool activeOnly = false}) async {
    await _ensureInitialized();
    final r = await _dio.get('/maintenance-plans/', queryParameters: {
      if (activeOnly) 'active_only': true,
    });
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getUpcomingPlans({int days = 30}) async {
    await _ensureInitialized();
    final r = await _dio.get('/maintenance-plans/upcoming',
        queryParameters: {'days': days});
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createMaintenancePlan(
      Map<String, dynamic> data) async {
    await _ensureInitialized();
    try {
      final r = await _dio.post('/maintenance-plans/', data: data);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> updateMaintenancePlan(
      int id, Map<String, dynamic> data) async {
    await _ensureInitialized();
    final r = await _dio.put('/maintenance-plans/$id', data: data);
    return r.data as Map<String, dynamic>;
  }

  Future<void> deleteMaintenancePlan(int id) async {
    await _ensureInitialized();
    await _dio.delete('/maintenance-plans/$id');
  }

  Future<Map<String, dynamic>> executeMaintenancePlan(int id,
      {String? notes, double? actualHours}) async {
    await _ensureInitialized();
    final r = await _dio.post('/maintenance-plans/$id/execute', data: {
      if (notes != null) 'notes': notes,
      if (actualHours != null) 'actual_hours': actualHours,
    });
    return r.data as Map<String, dynamic>;
  }

  // ─── BILLING / SUSCRIPCIÓN ───────────────────────────────────────────────

  Future<Map<String, dynamic>> getBillingStatus() async {
    await _ensureInitialized();
    try {
      final r = await _dio.get('/billing/status');
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> createBillingCheckout(String plan) async {
    await _ensureInitialized();
    try {
      final r = await _dio.post('/billing/checkout', data: {'plan': plan});
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> createBillingSubscription(
      String plan, String payerEmail) async {
    await _ensureInitialized();
    try {
      final r = await _dio.post('/billing/subscribe',
          data: {'plan': plan, 'payer_email': payerEmail});
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getBillingHistory() async {
    await _ensureInitialized();
    try {
      final r = await _dio.get('/billing/history');
      return (r.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  // ─── INVITATIONS ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createInvitation({
    required String email,
    String? fullName,
    List<String> roles = const ['technician'],
  }) async {
    await _ensureInitialized();
    try {
      final r = await _dio.post('/invitations', data: {
        'email': email,
        if (fullName != null) 'full_name': fullName,
        'roles': roles,
      });
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getInvitations() async {
    await _ensureInitialized();
    try {
      final r = await _dio.get('/invitations');
      return (r.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<void> revokeInvitation(int id) async {
    await _ensureInitialized();
    await _dio.post('/invitations/$id/revoke');
  }

  Future<Map<String, dynamic>> checkInvitationToken(String token) async {
    await _ensureInitialized();
    final r = await _dio.get('/invitations/$token');
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> acceptInvitation({
    required String token,
    required String password,
    String? fullName,
    String? phone,
    String? position,
  }) async {
    await _ensureInitialized();
    final r = await _dio.post('/invitations/$token/accept', data: {
      'password': password,
      if (fullName != null) 'full_name': fullName,
      if (phone != null) 'phone': phone,
      if (position != null) 'position': position,
    });
    return r.data as Map<String, dynamic>;
  }

  // ─── CALENDAR ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCalendarEvents({
    String? dateFrom,
    String? dateTo,
  }) async {
    await _ensureInitialized();
    final r = await _dio.get('/calendar/events', queryParameters: {
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createCompanyCalendar(String adminEmail) async {
    await _ensureInitialized();
    final r = await _dio.post('/calendar/company', data: {'admin_email': adminEmail});
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> syncPlanToCalendar(int planId) async {
    await _ensureInitialized();
    final r = await _dio.post('/maintenance-plans/$planId/sync');
    return r.data as Map<String, dynamic>;
  }

  Future<void> deleteCalendarEvent(int id) async {
    await _ensureInitialized();
    await _dio.delete('/calendar/events/$id');
  }

  // ─── EXPORT TO SHEETS ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> exportToSheets(String module) async {
    await _ensureInitialized();
    final r = await _dio.post('/export/$module/sheets');
    return r.data as Map<String, dynamic>;
  }

  // ─── QUOTE REQUESTS ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getQuoteRequests({String? status}) async {
    await _ensureInitialized();
    final r = await _dio.get('/quote-requests/',
        queryParameters: status != null ? {'status': status} : null);
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createQuoteRequest(
      Map<String, dynamic> data) async {
    await _ensureInitialized();
    try {
      final r = await _dio.post('/quote-requests/', data: data);
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _handleDioError(e);
    }
  }

  Future<Map<String, dynamic>> quoteQuoteRequest(
      int id, double price, String? notes) async {
    await _ensureInitialized();
    final r = await _dio.put('/quote-requests/$id/quote',
        data: {'quoted_price': price, if (notes != null) 'notes': notes});
    return r.data as Map<String, dynamic>;
  }

  Future<void> approveQuoteRequest(int id) async {
    await _ensureInitialized();
    await _dio.put('/quote-requests/$id/approve');
  }

  Future<void> rejectQuoteRequest(int id) async {
    await _ensureInitialized();
    await _dio.put('/quote-requests/$id/reject');
  }

  Future<Map<String, dynamic>> convertQuoteRequest(int id) async {
    await _ensureInitialized();
    final r = await _dio.post('/quote-requests/$id/convert');
    return r.data as Map<String, dynamic>;
  }
}