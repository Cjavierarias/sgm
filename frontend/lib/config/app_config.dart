/// Configuración centralizada de la aplicación SGM — BSA Consultora.
///
/// La URL base del API se configura mediante --dart-define en el build:
///   flutter run --dart-define=API_URL=http://192.168.1.10:8000
///   flutter build apk --dart-define=API_URL=https://api.tudominio.com
///
/// Si no se define, usa localhost:8000 como fallback para desarrollo.
library;

class AppConfig {
  AppConfig._();

  /// URL base del backend. Configurable con --dart-define=API_URL=...
  static const String apiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// Nombre de la aplicación
  static const String appName = 'SGM — BSA Consultora';

  /// Versión de la app
  static const String appVersion = '2.2.0';

  /// Nombre de la consultora
  static const String companyName = 'BSA Consultora';

  /// Timeouts de red en segundos
  static const int connectTimeoutSeconds = 15;
  static const int receiveTimeoutSeconds = 30;
}
