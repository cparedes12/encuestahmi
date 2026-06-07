import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'db.dart';
import 'models.dart';

/// Orquesta el flujo offline-first:
///   1. Guardar encuesta SIEMPRE en SQLite (no se pierde nada).
///   2. Intentar subir a Supabase.
///   3. Reintentar automáticamente cuando vuelve la conexión.
class EncuestaRepository {
  EncuestaRepository._();
  static final EncuestaRepository instance = EncuestaRepository._();

  final _db = LocalDb.instance;
  StreamSubscription? _connSub;
  bool _sincronizando = false;

  SupabaseClient? get _client =>
      Config.supabaseConfigured ? Supabase.instance.client : null;

  /// Llamar una vez al arrancar la app.
  void iniciar() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final hayRed = results.any((r) => r != ConnectivityResult.none);
      if (hayRed) sincronizar();
    });
    // Intento inicial por si quedaron pendientes de una sesión previa.
    sincronizar();
  }

  void detener() => _connSub?.cancel();

  // ---------- Preguntas (remoto → cache → seed) ----------
  Future<List<Pregunta>> cargarPreguntas(Departamento depto) async {
    final client = _client;
    if (client != null) {
      try {
        final data = await client
            .from('preguntas')
            .select('id, departamento, orden, texto')
            .eq('departamento', depto.key)
            .eq('activa', true)
            .order('orden');
        final preguntas = (data as List)
            .map((m) => Pregunta.fromMap(Map<String, dynamic>.from(m)))
            .toList();
        if (preguntas.isNotEmpty) {
          await _db.guardarPreguntasCache(
              depto.key, preguntas.map(_preguntaToMap).toList());
          return preguntas;
        }
      } catch (_) {
        // Sin red o error → caemos al cache/seed abajo.
      }
    }
    try {
      final cache = await _db.leerPreguntasCache(depto.key);
      if (cache != null && cache.isNotEmpty) {
        return cache.map((m) => Pregunta.fromMap(m)).toList();
      }
    } catch (_) {/* web / sin SQLite → usamos semilla */}
    return seedPreguntas(depto);
  }

  Map<String, dynamic> _preguntaToMap(Pregunta p) => {
        'id': p.id,
        'departamento': p.departamento.key,
        'orden': p.orden,
        'texto': p.texto,
      };

  int _folioMemoria = 0;

  // ---------- Guardar encuesta ----------
  /// Devuelve el folio local (n.º de encuesta de esta tablet) para la pantalla
  /// de gracias.
  Future<int> guardarEncuesta(EncuestaSesion sesion) async {
    int folio;
    try {
      await _db.encolar(sesion.id, sesion.toMap()); // persistir SIEMPRE
      folio = await _db.incrementarFolio();
    } catch (_) {
      // Web / sin SQLite: folio en memoria (solo preview).
      folio = ++_folioMemoria;
    }
    unawaited(sincronizar()); // subir sin bloquear la UI
    return folio;
  }

  // ---------- Sync ----------
  Future<void> sincronizar() async {
    final client = _client;
    if (client == null || _sincronizando) return;
    _sincronizando = true;
    try {
      final pendientes = await _db.pendientes();
      for (final payload in pendientes) {
        final sesion = EncuestaSesion.fromMap(payload);
        try {
          await _subir(client, sesion);
          await _db.marcarSincronizada(sesion.id);
        } catch (_) {
          await _db.registrarIntento(sesion.id);
          // Dejamos el resto para el próximo intento (red intermitente).
          break;
        }
      }
    } finally {
      _sincronizando = false;
    }
  }

  Future<void> _subir(SupabaseClient client, EncuestaSesion s) async {
    // upsert → idempotente: reintentos no duplican (PK = uuid del cliente).
    await client.from('encuestas').upsert({
      'id': s.id,
      'departamento': s.departamento.key,
      'dispositivo_id': Config.dispositivoIdOrNull,
      'iniciada_en': s.iniciadaEn.toUtc().toIso8601String(),
      'completada_en': s.completadaEn?.toUtc().toIso8601String(),
      'completada': s.completadaEn != null,
      'app_version': Config.appVersion,
    }, onConflict: 'id');

    if (s.respuestas.isNotEmpty) {
      await client.from('respuestas').upsert([
        for (final r in s.respuestas)
          {
            'id': r.id,
            'encuesta_id': s.id,
            'pregunta_id': r.preguntaId,
            'departamento': s.departamento.key,
            'valor': r.valor.key,
            'respondida_en': r.respondidaEn.toUtc().toIso8601String(),
          }
      ], onConflict: 'id');
    }
  }

  Future<int> pendientesCount() => _db.countPendientes();

  // ---------- Departamento elegido por el admin (persistente) ----------
  /// Departamento guardado localmente; si no hay, usa el de --dart-define.
  Future<Departamento> departamentoActual() async {
    try {
      final guardado = await _db.getConfig('departamento');
      if (guardado != null) return Departamento.fromKey(guardado);
    } catch (_) {/* web / sin db → cae al default */}
    return Departamento.fromKey(Config.departamento);
  }

  Future<void> fijarDepartamento(Departamento d) async {
    try {
      await _db.setConfig('departamento', d.key);
    } catch (_) {/* web sin db: queda solo en memoria */}
  }
}
