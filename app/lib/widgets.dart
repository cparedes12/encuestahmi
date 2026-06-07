import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';

// ============================================================================
//  ENTRADA ESCALONADA · aparece desvaneciéndose y subiendo (con delay)
// ============================================================================
class FadeInUp extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offset;
  const FadeInUp(
      {super.key,
      required this.child,
      this.delay = Duration.zero,
      this.offset = 16});
  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, child) => Opacity(
          opacity: _a.value,
          child: Transform.translate(
              offset: Offset(0, widget.offset * (1 - _a.value)), child: child),
        ),
        child: widget.child,
      );
}

// ============================================================================
//  FONDO DE MARCA · ondas de color flotando lentamente
// ============================================================================
class BrandBackground extends StatefulWidget {
  final DeptTheme t;
  final Widget child;
  const BrandBackground({super.key, required this.t, required this.child});
  @override
  State<BrandBackground> createState() => _BrandBackgroundState();
}

class _BrandBackgroundState extends State<BrandBackground>
    with TickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 20))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Stack(
      children: [
        // Malla degradada animada: los colores mutan suavemente en bucle.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final p = Curves.easeInOut.transform(_c.value);
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1 + 2 * p, -1),
                    end: Alignment(1 - 2 * p, 1),
                    colors: [
                      Color.lerp(t.bg, t.soft, .35 + .4 * p)!,
                      Color.lerp(t.bg, t.secondary, .10 + .08 * p)!,
                      Color.lerp(t.bg, t.soft, .55 - .3 * p)!,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _blob(t.accent.withValues(alpha: .45), 360,
            const Offset(-120, -120), 0, const Offset(40, -30)),
        _blob(t.secondary.withValues(alpha: .40), 380,
            const Offset(-120, -140), .5, const Offset(-30, 40),
            fromBottomRight: true),
        _blob(t.accent.withValues(alpha: .18), 240,
            const Offset(80, -60), .25, const Offset(20, 30),
            fromTopRight: true),
        // Campo de partículas (bokeh) flotando — toque premium en todas las pantallas
        Positioned.fill(child: ParticleField(color: t.accentDeep)),
        Positioned.fill(child: widget.child),
      ],
    );
  }

  Widget _blob(Color color, double size, Offset base, double phase,
      Offset drift,
      {bool fromBottomRight = false, bool fromTopRight = false}) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final p = (math.sin((_c.value + phase) * 2 * math.pi) + 1) / 2;
        final dx = base.dx + drift.dx * p;
        final dy = base.dy + drift.dy * p;
        final scale = 1 + .06 * p;
        Widget blob = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: size,
              height: size,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        );
        if (fromBottomRight) {
          return Positioned(bottom: dy, right: dx, child: blob);
        } else if (fromTopRight) {
          return Positioned(top: dy, right: dx, child: blob);
        }
        return Positioned(top: dy, left: dx, child: blob);
      },
    );
  }
}

// ============================================================================
//  CAMPO DE PARTÍCULAS (bokeh) · suben y derivan lentamente, en bucle
// ============================================================================
class ParticleField extends StatefulWidget {
  final Color color;
  final int count;
  const ParticleField({super.key, required this.color, this.count = 26});
  @override
  State<ParticleField> createState() => _ParticleFieldState();
}

class _ParticleFieldState extends State<ParticleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))
        ..repeat();
  late final List<_Dot> _dots;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(21);
    _dots = List.generate(widget.count, (i) {
      return _Dot(
        x: rnd.nextDouble(),
        y0: rnd.nextDouble(),
        size: 2 + rnd.nextDouble() * 6,
        speed: .3 + rnd.nextDouble() * .8,
        phase: rnd.nextDouble(),
        opacity: .06 + rnd.nextDouble() * .16,
        sway: .01 + rnd.nextDouble() * .03,
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            size: Size.infinite,
            painter: _ParticlePainter(_dots, _c.value, widget.color),
          ),
        ),
      );
}

class _Dot {
  final double x, y0, size, speed, phase, opacity, sway;
  _Dot({
    required this.x,
    required this.y0,
    required this.size,
    required this.speed,
    required this.phase,
    required this.opacity,
    required this.sway,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Dot> dots;
  final double t;
  final Color color;
  _ParticlePainter(this.dots, this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in dots) {
      var y = (d.y0 - t * d.speed) % 1.0;
      if (y < 0) y += 1;
      final x = (d.x + math.sin((t + d.phase) * 2 * math.pi) * d.sway) % 1.0;
      final paint = Paint()
        ..color = color.withValues(alpha: d.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(x * size.width, y * size.height), d.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => old.t != t;
}

// ============================================================================
//  REVELADO DE TEXTO palabra por palabra (estilo GSAP SplitText)
// ============================================================================
class WordReveal extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Duration startDelay;
  final int perWordMs;
  const WordReveal({
    super.key,
    required this.text,
    required this.style,
    this.startDelay = Duration.zero,
    this.perWordMs = 55,
  });

  @override
  Widget build(BuildContext context) {
    final words = text.split(' ');
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 2,
      children: [
        for (var i = 0; i < words.length; i++)
          FadeInUp(
            delay: startDelay + Duration(milliseconds: i * perWordMs),
            offset: 20,
            child: Text(words[i], style: style),
          ),
      ],
    );
  }
}

// ============================================================================
//  FOCO (idea) · rebota, glow pulsante, rayos que laten, destellos orbitando
// ============================================================================
class BulbLogo extends StatefulWidget {
  final Color color;
  final double size;
  const BulbLogo({super.key, required this.color, this.size = 130});
  @override
  State<BulbLogo> createState() => _BulbLogoState();
}

class _BulbLogoState extends State<BulbLogo> with TickerProviderStateMixin {
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))
        ..repeat(reverse: true);
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..repeat(reverse: true);
  late final AnimationController _orbit =
      AnimationController(vsync: this, duration: const Duration(seconds: 7))
        ..repeat();

  @override
  void dispose() {
    _bob.dispose();
    _pulse.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: Listenable.merge([_bob, _pulse, _orbit]),
        builder: (_, __) {
          final bob = -8 * Curves.easeInOut.transform(_bob.value);
          final pulse = _pulse.value; // 0..1
          return Transform.translate(
            offset: Offset(0, bob),
            child: Stack(alignment: Alignment.center, children: [
              // Glow pulsante
              Transform.scale(
                scale: .9 + .25 * pulse,
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      widget.color.withValues(alpha: .25 + .25 * pulse),
                      widget.color.withValues(alpha: 0),
                    ], stops: const [0, .65]),
                  ),
                ),
              ),
              CustomPaint(
                  size: Size(s, s),
                  painter: _BulbPainter(widget.color, .55 + .45 * pulse)),
              ..._sparks(s),
            ]),
          );
        },
      ),
    );
  }

  List<Widget> _sparks(double s) {
    const items = ['✨', '⭐', '✨', '💕'];
    final r = s * 0.46;
    return [
      for (var i = 0; i < items.length; i++)
        Builder(builder: (_) {
          final dir = i.isEven ? 1 : -1;
          final ang = (_orbit.value * dir + i / items.length) * 2 * math.pi;
          return Transform.translate(
            offset: Offset(r * math.cos(ang), r * math.sin(ang)),
            child: Text(items[i], style: TextStyle(fontSize: 11 + (i % 2) * 4)),
          );
        }),
    ];
  }
}

class _BulbPainter extends CustomPainter {
  final Color color;
  final double rayOpacity;
  _BulbPainter(this.color, this.rayOpacity);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 120.0;
    canvas.scale(s, s);

    // Rayos (laten en opacidad)
    final rays = Paint()
      ..color = color.withValues(alpha: rayOpacity.clamp(0, 1))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    const ray = [
      [60.0, 6.0, 60.0, 16.0],
      [98.0, 22.0, 91.0, 29.0],
      [114.0, 60.0, 104.0, 60.0],
      [98.0, 98.0, 91.0, 91.0],
      [22.0, 98.0, 29.0, 91.0],
      [6.0, 60.0, 16.0, 60.0],
      [22.0, 22.0, 29.0, 29.0],
    ];
    for (final r in ray) {
      canvas.drawLine(Offset(r[0], r[1]), Offset(r[2], r[3]), rays);
    }

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.5;
    final bulb = Path()
      ..moveTo(60, 28)
      ..cubicTo(45, 28, 36, 40, 36, 52)
      ..cubicTo(36, 62, 42, 68, 46, 74)
      ..lineTo(46, 84)
      ..lineTo(74, 84)
      ..lineTo(74, 74)
      ..cubicTo(78, 68, 84, 62, 84, 52)
      ..cubicTo(84, 40, 75, 28, 60, 28)
      ..close();
    canvas.drawPath(bulb, stroke);

    stroke.strokeWidth = 3;
    for (final x in [52.0, 60.0, 68.0]) {
      canvas.drawLine(Offset(x, 84), Offset(x, 92), stroke);
    }
    canvas.drawLine(const Offset(54, 98), const Offset(66, 98), stroke);
  }

  @override
  bool shouldRepaint(covariant _BulbPainter old) =>
      old.color != color || old.rayOpacity != rayOpacity;
}

// ============================================================================
//  BOTÓN COMENZAR · respira + brillo que recorre
// ============================================================================
class AnimatedStartButton extends StatefulWidget {
  final Color color, colorDeep;
  final VoidCallback onTap;
  const AnimatedStartButton(
      {super.key,
      required this.color,
      required this.colorDeep,
      required this.onTap});
  @override
  State<AnimatedStartButton> createState() => _AnimatedStartButtonState();
}

class _AnimatedStartButtonState extends State<AnimatedStartButton>
    with TickerProviderStateMixin {
  late final AnimationController _breathe =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3500))
        ..repeat(reverse: true);
  late final AnimationController _shine =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..repeat();
  bool _down = false;

  @override
  void dispose() {
    _breathe.dispose();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breathe, _shine]),
      builder: (_, __) {
        final lift = -3 * Curves.easeInOut.transform(_breathe.value);
        return Transform.translate(
          offset: Offset(0, _down ? 0 : lift),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _down = true),
            onTapUp: (_) => setState(() => _down = false),
            onTapCancel: () => setState(() => _down = false),
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onTap();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                decoration: BoxDecoration(
                  gradient:
                      LinearGradient(colors: [widget.color, widget.colorDeep]),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                        color: widget.color.withValues(alpha: .45),
                        blurRadius: 30,
                        offset: const Offset(0, 10)),
                  ],
                ),
                child: Stack(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 56, vertical: 20),
                    child: Text('Comenzar',
                        style: body(18,
                            weight: FontWeight.w700, color: Colors.white)),
                  ),
                  // Brillo diagonal que recorre
                  Positioned.fill(
                    child: FractionallySizedBox(
                      widthFactor: .35,
                      alignment:
                          Alignment(-1.6 + 3.2 * _shine.value, 0),
                      child: Transform.rotate(
                        angle: .35,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: .35),
                              Colors.white.withValues(alpha: 0),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
//  BARRA DE PROGRESO con gradiente
// ============================================================================
class GradientProgress extends StatelessWidget {
  final double value;
  final Color from, to;
  const GradientProgress(
      {super.key, required this.value, required this.from, required this.to});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 8,
        color: Colors.black.withValues(alpha: .06),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => FractionallySizedBox(
              widthFactor: v == 0 ? 0.001 : v,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [from, to]),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  CORAZÓN QUE LATE + anillos expansivos (pantalla de gracias)
// ============================================================================
class BeatingHeart extends StatefulWidget {
  final Color ringColor;
  const BeatingHeart({super.key, required this.ringColor});
  @override
  State<BeatingHeart> createState() => _BeatingHeartState();
}

class _BeatingHeartState extends State<BeatingHeart>
    with TickerProviderStateMixin {
  late final AnimationController _beat =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat();
  late final AnimationController _rings =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..repeat();
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
        ..forward();

  double _beatScale(double t) {
    // keyframes: 0%1, 15%1.15, 30%1, 45%1.1, 60%1
    if (t < .15) return 1 + (.15) * (t / .15);
    if (t < .30) return 1.15 - .15 * ((t - .15) / .15);
    if (t < .45) return 1 + .10 * ((t - .30) / .15);
    if (t < .60) return 1.10 - .10 * ((t - .45) / .15);
    return 1;
  }

  @override
  void dispose() {
    _beat.dispose();
    _rings.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: AnimatedBuilder(
        animation: Listenable.merge([_beat, _rings, _intro]),
        builder: (_, __) {
          final intro = Curves.elasticOut.transform(_intro.value);
          return Transform.scale(
            scale: intro,
            child: Stack(alignment: Alignment.center, children: [
              _ring(_rings.value),
              _ring((_rings.value + .5) % 1),
              Transform.scale(
                scale: _beatScale(_beat.value),
                child: const Text('💝', style: TextStyle(fontSize: 90)),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _ring(double t) {
    return Opacity(
      opacity: (1 - t) * .6,
      child: Transform.scale(
        scale: .7 + t * .9,
        child: Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: widget.ringColor, width: 2),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  CONFETI · estalla al completar
// ============================================================================
class Confetti extends StatefulWidget {
  const Confetti({super.key});
  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  static const _colors = [
    Brand.rose, Brand.teal, Brand.tealDeep, Brand.roseDeep,
    Brand.roseSoft, Brand.tealSoft,
  ];
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3500))
        ..forward();
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    _pieces = List.generate(60, (i) {
      return _Piece(
        color: _colors[i % _colors.length],
        startX: rnd.nextDouble(), // a todo lo ancho
        drift: (rnd.nextDouble() - .5) * .25,
        delay: rnd.nextDouble() * .5, // caen escalonadas
        rot: rnd.nextDouble() * 6,
        size: 7 + rnd.nextDouble() * 8,
        round: rnd.nextBool(),
        spin: (rnd.nextBool() ? 1 : -1) * (2 + rnd.nextDouble() * 4),
        speed: .85 + rnd.nextDouble() * .4,
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_pieces, _c.value),
        ),
      ),
    );
  }
}

class _Piece {
  final Color color;
  final double startX, drift, delay, rot, size, spin, speed;
  final bool round;
  _Piece({
    required this.color,
    required this.startX,
    required this.drift,
    required this.delay,
    required this.rot,
    required this.size,
    required this.round,
    required this.spin,
    required this.speed,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double t;
  _ConfettiPainter(this.pieces, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final lt = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (lt <= 0) continue;
      // Cae desde ARRIBA, a todo lo ancho, con leve deriva horizontal.
      final fall = (lt * p.speed).clamp(0.0, 1.0);
      final x = p.startX * size.width + p.drift * size.width * lt;
      final y = -20 + fall * (size.height + 40);
      final opacity = lt > .85 ? (1 - lt) / .15 : 1.0;
      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity.clamp(0, 1));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rot + p.spin * lt * math.pi);
      final r = Rect.fromCenter(
          center: Offset.zero, width: p.size, height: p.size);
      if (p.round) {
        canvas.drawOval(r, paint);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(2)), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

// ============================================================================
//  CORAZONES FLOTANTES · suben al completar
// ============================================================================
class FloatingHearts extends StatefulWidget {
  const FloatingHearts({super.key});
  @override
  State<FloatingHearts> createState() => _FloatingHeartsState();
}

class _FloatingHeartsState extends State<FloatingHearts>
    with SingleTickerProviderStateMixin {
  static const _emojis = ['❤️', '💕', '🌸', '✨', '💖'];
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
        ..forward();
  late final List<_Heart> _hearts;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(13);
    _hearts = List.generate(10, (i) {
      return _Heart(
        emoji: _emojis[i % _emojis.length],
        x: .25 + rnd.nextDouble() * .5,
        delay: i * .12,
        drift: (rnd.nextDouble() - .5) * .1,
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (_, box) => AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            return Stack(
              children: [
                for (final h in _hearts) _build(h, box),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _build(_Heart h, BoxConstraints box) {
    final lt = ((_c.value - h.delay) / (1 - h.delay)).clamp(0.0, 1.0);
    if (lt <= 0) return const SizedBox.shrink();
    final bottom = box.maxHeight * .22 + lt * box.maxHeight * .5;
    final opacity = lt < .2 ? lt / .2 : (1 - lt);
    return Positioned(
      left: box.maxWidth * (h.x + h.drift * lt),
      bottom: bottom,
      child: Opacity(
        opacity: opacity.clamp(0, 1),
        child: Transform.scale(
          scale: .6 + lt * .7,
          child: Text(h.emoji, style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }
}

class _Heart {
  final String emoji;
  final double x, delay, drift;
  _Heart(
      {required this.emoji,
      required this.x,
      required this.delay,
      required this.drift});
}

// ============================================================================
//  PALOMITA QUE SE DIBUJA (círculo + check con trazo animado)
// ============================================================================
class DrawnCheck extends StatefulWidget {
  final Color color;
  final double size;
  final double strokeWidth;
  const DrawnCheck(
      {super.key, required this.color, this.size = 24, this.strokeWidth = 2.5});
  @override
  State<DrawnCheck> createState() => _DrawnCheckState();
}

class _DrawnCheckState extends State<DrawnCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
        ..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _CheckPainter(widget.color, _c.value, widget.strokeWidth),
        ),
      );
}

class _CheckPainter extends CustomPainter {
  final Color color;
  final double t;
  final double strokeWidth;
  _CheckPainter(this.color, this.t, this.strokeWidth);

  Path _partial(Path path, double frac) {
    final out = Path();
    for (final m in path.computeMetrics()) {
      out.addPath(m.extractPath(0, m.length * frac.clamp(0, 1)), Offset.zero);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth;

    // Círculo (se dibuja primero, 0..0.6)
    final circle = Path()
      ..addArc(
          Rect.fromCircle(
              center: Offset(s / 2, s / 2), radius: s * 0.44),
          -math.pi / 2,
          2 * math.pi);
    final circleFrac = (t / .6).clamp(0.0, 1.0);
    canvas.drawPath(_partial(circle, circleFrac), paint);

    // Check (se dibuja después, 0.4..1)
    final check = Path()
      ..moveTo(s * .28, s * .52)
      ..lineTo(s * .44, s * .68)
      ..lineTo(s * .73, s * .34);
    final checkFrac = ((t - .4) / .6).clamp(0.0, 1.0);
    canvas.drawPath(_partial(check, checkFrac), paint);
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) => old.t != t;
}

// ============================================================================
//  CONTADOR ANIMADO (los números suben hasta el valor)
// ============================================================================
class AnimatedCounter extends StatelessWidget {
  final int value;
  final TextStyle style;
  final String prefix;
  final Duration duration;
  const AnimatedCounter({
    super.key,
    required this.value,
    required this.style,
    this.prefix = '',
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text('$prefix${v.round()}', style: style),
      );
}
