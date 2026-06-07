import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta de marca del Patronato (idéntica al demo aprobado).
class Brand {
  // Rosa (Ginecología)
  static const rose = Color(0xFFE89BB0);
  static const roseDeep = Color(0xFFD97A96);
  static const roseSoft = Color(0xFFFCE4EA);
  static const roseBg = Color(0xFFFDF1F4);

  // Teal (Pediatría)
  static const teal = Color(0xFF5EC5D6);
  static const tealDeep = Color(0xFF3BB4C8);
  static const tealSoft = Color(0xFFD5EFF4);
  static const tealBg = Color(0xFFECF8FA);

  // Tinta / neutros
  static const ink = Color(0xFF3A3A4A);
  static const inkSoft = Color(0xFF6A6A78);
  static const inkMute = Color(0xFF9A9AA6);
  static const line = Color(0xFFF0E6E9);

  // Semánticos (satisfacción)
  static const good = Color(0xFF2F8F5F);
  static const goodBg = Color(0xFFE6F2EB);
  static const mid = Color(0xFFD8A23A);
  static const midBg = Color(0xFFF7ECD1);
  static const bad = Color(0xFFC44A3F);
  static const badBg = Color(0xFFF6DCD8);
}

/// Identidad visual por departamento (color de acento + fondo).
/// `secondary` = el color de la onda opuesta (en el demo, Pediatría usa onda
/// teal arriba-izq + onda rosa abajo-der; Ginecología al revés).
class DeptTheme {
  final Color accent;
  final Color accentDeep;
  final Color soft;
  final Color bg;
  final Color secondary;
  const DeptTheme(
      this.accent, this.accentDeep, this.soft, this.bg, this.secondary);

  static const pediatria = DeptTheme(
      Brand.teal, Brand.tealDeep, Brand.tealSoft, Brand.tealBg, Brand.rose);
  static const ginecologia = DeptTheme(
      Brand.rose, Brand.roseDeep, Brand.roseSoft, Brand.roseBg, Brand.teal);
}

/// Fuentes del demo: Quicksand (display) + Nunito (texto).
TextStyle display(double size,
        {FontWeight weight = FontWeight.w600, Color color = Brand.ink}) =>
    GoogleFonts.quicksand(fontSize: size, fontWeight: weight, color: color);

TextStyle body(double size,
        {FontWeight weight = FontWeight.w600, Color color = Brand.ink}) =>
    GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFFDF6F8),
      colorScheme: ColorScheme.fromSeed(seedColor: Brand.teal),
      textTheme: GoogleFonts.nunitoTextTheme(),
    );
