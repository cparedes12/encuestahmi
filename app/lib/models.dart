import 'package:flutter/material.dart';
import 'theme.dart';

enum Departamento {
  pediatria('pediatria', 'Pediatría', 'Pisos 5 y 6', DeptTheme.pediatria),
  ginecologia('ginecologia', 'Ginecología', 'Pisos 3 y 4', DeptTheme.ginecologia);

  final String key;
  final String nombre;
  final String pisos;
  final DeptTheme theme;
  const Departamento(this.key, this.nombre, this.pisos, this.theme);

  static Departamento fromKey(String k) =>
      values.firstWhere((d) => d.key == k, orElse: () => pediatria);
}

enum Valor {
  satisfecho('satisfecho', '😊', 'Satisfecho', Brand.good, Brand.goodBg),
  neutral('neutral', '😐', 'Neutral', Brand.mid, Brand.midBg),
  insatisfecho('insatisfecho', '☹️', 'Insatisfecho', Brand.bad, Brand.badBg);

  final String key;
  final String emoji;
  final String label;
  final Color color;
  final Color bg;
  const Valor(this.key, this.emoji, this.label, this.color, this.bg);
}

class Pregunta {
  final String id;
  final Departamento departamento;
  final int orden;
  final String texto;
  const Pregunta({
    required this.id,
    required this.departamento,
    required this.orden,
    required this.texto,
  });

  factory Pregunta.fromMap(Map<String, dynamic> m) => Pregunta(
        id: m['id'] as String,
        departamento: Departamento.fromKey(m['departamento'] as String),
        orden: m['orden'] as int,
        texto: m['texto'] as String,
      );
}

/// Preguntas semilla (fallback offline / primer arranque).
/// Coinciden con supabase/schema.sql.
const Map<Departamento, List<String>> kPreguntasSeed = {
  Departamento.pediatria: [
    '¿Considera que el motivo de atención de su paciente fue atendido adecuadamente?',
    '¿El personal médico resolvió sus dudas de manera clara?',
    '¿La atención y calidez del equipo de enfermería fue el adecuado?',
    '¿Cómo califica la comodidad de las instalaciones?',
  ],
  Departamento.ginecologia: [
    '¿Te sentiste acompañada y bien atendida durante tu estancia y recuperación?',
    '¿El personal médico resolvió tus dudas sobre tus cuidados y los de tu bebé?',
    '¿La atención y calidez del equipo de enfermería fue el adecuado?',
    '¿Consideras que tus necesidades y las de tu bebé fueron atendidas adecuadamente?',
    '¿Cómo califica la comodidad de las instalaciones?',
  ],
};

List<Pregunta> seedPreguntas(Departamento d) {
  final textos = kPreguntasSeed[d]!;
  return [
    for (var i = 0; i < textos.length; i++)
      Pregunta(
        id: 'seed-${d.key}-${i + 1}',
        departamento: d,
        orden: i + 1,
        texto: textos[i],
      ),
  ];
}

/// Una respuesta individual dentro de una sesión.
class RespuestaLocal {
  final String id;
  final String preguntaId;
  final Valor valor;
  final DateTime respondidaEn;
  RespuestaLocal({
    required this.id,
    required this.preguntaId,
    required this.valor,
    required this.respondidaEn,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'pregunta_id': preguntaId,
        'valor': valor.key,
        'respondida_en': respondidaEn.toUtc().toIso8601String(),
      };

  factory RespuestaLocal.fromMap(Map<String, dynamic> m) => RespuestaLocal(
        id: m['id'] as String,
        preguntaId: m['pregunta_id'] as String,
        valor: Valor.values.firstWhere((v) => v.key == m['valor']),
        respondidaEn: DateTime.parse(m['respondida_en'] as String),
      );
}

/// Una sesión completa de encuesta (lo que se guarda local y se sube).
/// El `id` se genera en la tablet → idempotencia offline.
class EncuestaSesion {
  final String id;
  final Departamento departamento;
  final DateTime iniciadaEn;
  DateTime? completadaEn;
  final List<RespuestaLocal> respuestas = [];

  EncuestaSesion({
    required this.id,
    required this.departamento,
    required this.iniciadaEn,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'departamento': departamento.key,
        'iniciada_en': iniciadaEn.toUtc().toIso8601String(),
        'completada_en': completadaEn?.toUtc().toIso8601String(),
        'respuestas': respuestas.map((r) => r.toMap()).toList(),
      };

  factory EncuestaSesion.fromMap(Map<String, dynamic> m) {
    final s = EncuestaSesion(
      id: m['id'] as String,
      departamento: Departamento.fromKey(m['departamento'] as String),
      iniciadaEn: DateTime.parse(m['iniciada_en'] as String),
    );
    if (m['completada_en'] != null) {
      s.completadaEn = DateTime.parse(m['completada_en'] as String);
    }
    for (final r in (m['respuestas'] as List)) {
      s.respuestas.add(RespuestaLocal.fromMap(Map<String, dynamic>.from(r)));
    }
    return s;
  }
}
