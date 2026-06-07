import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

class UpdateInfo {
  final String version;
  final String storagePath;
  final String? notas;
  UpdateInfo(this.version, this.storagePath, this.notas);
}

/// OTA privado: consulta la versión publicada en Supabase, descarga el APK del
/// bucket PRIVADO con URL firmada (no pública) e instala (silencioso con Knox).
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  final Dio _dio = Dio();
  static const _channel =
      MethodChannel('mx.org.patronato.encuestas_salida/installer');
  static const _bucket = 'app-releases';

  SupabaseClient? get _client =>
      Config.supabaseConfigured ? Supabase.instance.client : null;

  Future<String> versionActual() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '0.0.0';
    }
  }

  /// Devuelve la actualización disponible, o null si ya está al día / sin red.
  Future<UpdateInfo?> buscarActualizacion() async {
    final client = _client;
    if (client == null || kIsWeb) return null;
    try {
      final data = await client
          .from('app_release')
          .select('version, storage_path, notas')
          .eq('activo', true)
          .order('publicado_en', ascending: false)
          .limit(1);
      final rows = data as List;
      if (rows.isEmpty) return null;
      final r = Map<String, dynamic>.from(rows.first);
      final latest = r['version'] as String;
      if (_comparar(latest, await versionActual()) > 0) {
        return UpdateInfo(
            latest, r['storage_path'] as String, r['notas'] as String?);
      }
    } catch (_) {/* sin red / error → no hay update */}
    return null;
  }

  /// Descarga el APK con URL firmada (válida 10 min) del bucket privado.
  Future<String> descargar(UpdateInfo info,
      {void Function(int received, int total)? onProgress}) async {
    final client = Supabase.instance.client;
    final url =
        await client.storage.from(_bucket).createSignedUrl(info.storagePath, 600);
    final dir =
        await getExternalStorageDirectory() ?? await getApplicationSupportDirectory();
    final filePath = '${dir.path}/update.apk';
    await _dio.download(
      url,
      filePath,
      onReceiveProgress: onProgress,
      options: Options(
        receiveTimeout: const Duration(minutes: 10),
        followRedirects: true,
      ),
    );
    return filePath;
  }

  /// Instala el APK (silencioso si la tablet es Device Owner vía Knox).
  Future<bool> instalar(String filePath) async {
    try {
      final res = await _channel.invokeMethod('installApk', {'filePath': filePath});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  int _comparar(String a, String b) {
    List<int> partes(String v) => v
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final pa = partes(a), pb = partes(b);
    while (pa.length < 3) {
      pa.add(0);
    }
    while (pb.length < 3) {
      pb.add(0);
    }
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i] - pb[i];
    }
    return 0;
  }
}
