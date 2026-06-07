import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base de datos LOCAL en la tablet (offline-first).
///   · cola_encuestas  → encuestas pendientes de subir a Supabase.
///   · preguntas_cache → último set de preguntas descargado (fallback offline).
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'encuestas.db'),
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE cola_encuestas (
            id            TEXT PRIMARY KEY,
            payload       TEXT NOT NULL,
            creado_en     TEXT NOT NULL,
            sincronizado  INTEGER NOT NULL DEFAULT 0,
            intentos      INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE preguntas_cache (
            departamento  TEXT PRIMARY KEY,
            payload       TEXT NOT NULL,
            actualizado   TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE config (
            clave  TEXT PRIMARY KEY,
            valor  TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS config (
              clave  TEXT PRIMARY KEY,
              valor  TEXT NOT NULL
            )
          ''');
        }
      },
    );
    return _db!;
  }

  // ---------- Config (key/value) ----------
  Future<void> setConfig(String clave, String valor) async {
    final db = await _database;
    await db.insert('config', {'clave': clave, 'valor': valor},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getConfig(String clave) async {
    final db = await _database;
    final rows = await db
        .query('config', where: 'clave = ?', whereArgs: [clave], limit: 1);
    return rows.isEmpty ? null : rows.first['valor'] as String;
  }

  /// Folio local incremental (cuántas encuestas se han completado en ESTA tablet).
  Future<int> incrementarFolio() async {
    final actual = int.tryParse(await getConfig('folio') ?? '0') ?? 0;
    final nuevo = actual + 1;
    await setConfig('folio', '$nuevo');
    return nuevo;
  }

  // ---------- Cola de encuestas ----------
  Future<void> encolar(String id, Map<String, dynamic> payload) async {
    final db = await _database;
    await db.insert(
      'cola_encuestas',
      {
        'id': id,
        'payload': jsonEncode(payload),
        'creado_en': DateTime.now().toUtc().toIso8601String(),
        'sincronizado': 0,
        'intentos': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> pendientes() async {
    final db = await _database;
    final rows = await db.query('cola_encuestas',
        where: 'sincronizado = 0', orderBy: 'creado_en ASC');
    return rows
        .map((r) => jsonDecode(r['payload'] as String) as Map<String, dynamic>)
        .toList();
  }

  Future<void> marcarSincronizada(String id) async {
    final db = await _database;
    await db.update('cola_encuestas', {'sincronizado': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> registrarIntento(String id) async {
    final db = await _database;
    await db.rawUpdate(
        'UPDATE cola_encuestas SET intentos = intentos + 1 WHERE id = ?', [id]);
  }

  Future<int> countPendientes() async {
    final db = await _database;
    final r = await db
        .rawQuery('SELECT COUNT(*) c FROM cola_encuestas WHERE sincronizado = 0');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  // ---------- Cache de preguntas ----------
  Future<void> guardarPreguntasCache(
      String departamento, List<Map<String, dynamic>> preguntas) async {
    final db = await _database;
    await db.insert(
      'preguntas_cache',
      {
        'departamento': departamento,
        'payload': jsonEncode(preguntas),
        'actualizado': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>?> leerPreguntasCache(
      String departamento) async {
    final db = await _database;
    final rows = await db.query('preguntas_cache',
        where: 'departamento = ?', whereArgs: [departamento], limit: 1);
    if (rows.isEmpty) return null;
    final list = jsonDecode(rows.first['payload'] as String) as List;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
