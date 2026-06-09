/// Configuración inyectada en build con --dart-define (no se hardcodea nada).
///
/// Ejemplo:
///   flutter run --dart-define=SUPABASE_URL=https://encuestas-api.tudominio.com \
///               --dart-define=SUPABASE_ANON_KEY=eyJ... \
///               --dart-define=DEPARTAMENTO=pediatria \
///               --dart-define=DISPOSITIVO_ID=uuid-registrado
class Config {
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Departamento que atiende esta tablet: 'pediatria' | 'ginecologia'.
  static const departamento =
      String.fromEnvironment('DEPARTAMENTO', defaultValue: 'pediatria');

  /// UUID del dispositivo (registrado en tabla `dispositivos`). Opcional.
  static const dispositivoId =
      String.fromEnvironment('DISPOSITIVO_ID', defaultValue: '');

  /// PIN para el panel de administrador (cambiar de encuesta). Configurable
  /// por dispositivo: --dart-define=ADMIN_PIN=1234
  static const adminPin =
      String.fromEnvironment('ADMIN_PIN', defaultValue: '2468');

  /// Detección de presencia (cámara frontal + ML Kit) para iniciar la voz al
  /// acercarse alguien. Opt-in por dispositivo: --dart-define=PRESENCIA=1
  /// No guarda imágenes; solo detecta si hay un rostro.
  static const presenciaActiva =
      bool.fromEnvironment('PRESENCIA', defaultValue: false);

  static const appVersion = '1.0.0';

  static bool get supabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String? get dispositivoIdOrNull =>
      dispositivoId.isEmpty ? null : dispositivoId;
}
