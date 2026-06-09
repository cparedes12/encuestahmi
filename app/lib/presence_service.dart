import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'config.dart';

/// Detección de PRESENCIA con privacidad: usa la cámara frontal para ver si hay
/// un rostro y disparar la voz de bienvenida al acercarse alguien.
///
/// PRIVACIDAD: toma un cuadro de baja resolución, lo analiza y lo BORRA de
/// inmediato. No se guarda ni se sube ninguna imagen — solo un booleano.
/// Opt-in por dispositivo con --dart-define=PRESENCIA=1.
class PresenceService {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  CameraController? _cam;
  FaceDetector? _detector;
  Timer? _loop;
  bool _procesando = false;
  bool _presente = false;
  VoidCallback? _onLlega;

  bool get activa => Config.presenciaActiva && !kIsWeb;

  /// [onPresencia] se llama cuando alguien aparece tras estar ausente.
  Future<void> iniciar({required VoidCallback onPresencia}) async {
    if (!activa) return;
    _onLlega = onPresencia;
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return;
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      _cam = CameraController(front, ResolutionPreset.low,
          enableAudio: false);
      await _cam!.initialize();
      _detector = FaceDetector(
          options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
      _loop = Timer.periodic(const Duration(milliseconds: 1500), (_) => _tick());
    } catch (_) {
      // Sin cámara/permiso → se desactiva silenciosamente (la app sigue normal).
      await detener();
    }
  }

  Future<void> _tick() async {
    if (_procesando || _cam == null || !(_cam!.value.isInitialized)) return;
    _procesando = true;
    XFile? shot;
    try {
      shot = await _cam!.takePicture();
      final faces =
          await _detector!.processImage(InputImage.fromFilePath(shot.path));
      final hay = faces.isNotEmpty;
      if (hay && !_presente) {
        _presente = true;
        _onLlega?.call();
      } else if (!hay) {
        _presente = false;
      }
    } catch (_) {
      // ignorar errores de cuadro suelto
    } finally {
      // BORRAR SIEMPRE la imagen (no se guarda nada).
      if (shot != null) {
        try {
          await File(shot.path).delete();
        } catch (_) {}
      }
      _procesando = false;
    }
  }

  Future<void> detener() async {
    _loop?.cancel();
    _loop = null;
    try {
      await _cam?.dispose();
    } catch (_) {}
    try {
      await _detector?.close();
    } catch (_) {}
    _cam = null;
    _detector = null;
  }
}
