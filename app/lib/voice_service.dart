import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tts/flutter_tts.dart';
import 'models.dart';

/// Voz de la app. Reproduce el audio NEURONAL pregenerado (offline, gratis,
/// es-MX) que corresponde a (área, texto). Si no existe el clip (p. ej. una
/// pregunta editada desde el dashboard), usa el TTS del sistema como respaldo.
///
/// Las frases de interfaz aquí deben coincidir EXACTO con tools/generate_voice.py
/// (mismo texto → mismo hash → mismo archivo).
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;
  bool habilitada = true; // se puede silenciar desde el panel admin

  static const Map<String, Map<String, String>> _ui = {
    'pediatria': {
      'welcome':
          'Antes de irse, ¿nos regala treinta segundos? Su opinión nos ayuda a cuidar mejor a cada niña y niño que atendemos. Es totalmente anónima. Toque comenzar cuando guste.',
      'thanks':
          '¡Gracias por su tiempo! Su opinión nos ayuda a brindar la mejor atención a cada niña y niño. Le deseamos una pronta recuperación a su pequeño.',
    },
    'ginecologia': {
      'welcome':
          'Antes de irte, ¿nos regalas treinta segundos? Tu opinión nos ayuda a mejorar la atención para cada mamá y bebé. Es totalmente anónima. Toca comenzar cuando quieras.',
      'thanks':
          '¡Gracias mamá! Tu voz nos ayuda a brindar una mejor experiencia a cada familia. Te deseamos lo mejor a ti y a tu bebé.',
    },
  };

  String _hash(String area, String text) =>
      sha1.convert(utf8.encode('$area|$text')).toString().substring(0, 16);

  Future<void> _decir(String area, String texto) async {
    if (!habilitada) return;
    await _player.stop();
    final rel = 'audio/${_hash(area, texto)}.mp3';
    try {
      await rootBundle.load('assets/$rel'); // ¿existe el clip?
      await _player.play(AssetSource(rel));
    } catch (_) {
      await _ttsRespaldo(texto); // sin clip → TTS del sistema
    }
  }

  Future<void> bienvenida(Departamento d) => _decir(d.key, _ui[d.key]!['welcome']!);
  Future<void> gracias(Departamento d) => _decir(d.key, _ui[d.key]!['thanks']!);
  Future<void> pregunta(Departamento d, String texto) => _decir(d.key, texto);

  Future<void> detener() async {
    await _player.stop();
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> _ttsRespaldo(String texto) async {
    if (!habilitada) return;
    try {
      if (!_ttsReady) {
        await _tts.setLanguage('es-MX');
        await _tts.setSpeechRate(0.95);
        await _tts.setPitch(1.05);
        _ttsReady = true;
      }
      await _tts.stop();
      await _tts.speak(texto);
    } catch (_) {}
  }
}
