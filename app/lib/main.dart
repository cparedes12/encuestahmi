import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'theme.dart';
import 'models.dart';
import 'config.dart';
import 'repository.dart';
import 'update_service.dart';
import 'voice_service.dart';
import 'widgets.dart';

const _uuid = Uuid();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Kiosko: mantener la pantalla SIEMPRE encendida mientras la app esté activa.
  WakelockPlus.enable();

  if (Config.supabaseConfigured) {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      // Self-hosted usa el anon key (JWT). El warning de deprecación aplica al
      // nuevo formato de llaves de Supabase Cloud; aquí es intencional.
      // ignore: deprecated_member_use
      anonKey: Config.supabaseAnonKey,
    );
  }
  EncuestaRepository.instance.iniciar();

  runApp(const EncuestaApp());
}

class EncuestaApp extends StatelessWidget {
  const EncuestaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Encuesta de Salida · Patronato',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const SurveyFlow(),
      );
}

class SurveyFlow extends StatefulWidget {
  const SurveyFlow({super.key});
  @override
  State<SurveyFlow> createState() => _SurveyFlowState();
}

class _SurveyFlowState extends State<SurveyFlow> {
  final _repo = EncuestaRepository.instance;
  Departamento depto = Departamento.fromKey(Config.departamento);
  List<Pregunta> preguntas = [];
  int step = 0; // 0 = bienvenida, 1..n = preguntas, n+1 = gracias
  EncuestaSesion? _sesion;
  int? _folio;

  @override
  void initState() {
    super.initState();
    preguntas = seedPreguntas(depto);
    _inicializar();
  }

  Future<void> _inicializar() async {
    // Departamento persistente (elegido por el admin) → luego preguntas.
    final d = await _repo.departamentoActual();
    if (mounted) setState(() => depto = d);
    await _cargarPreguntas();
    _hablar(); // bienvenida hablada al iniciar
    _chequeoActualizacionSilencioso();
  }

  /// Reproduce la voz de la pantalla actual (clip neuronal o TTS de respaldo).
  void _hablar() {
    if (step == 0) {
      VoiceService.instance.bienvenida(depto);
    } else if (step <= preguntas.length) {
      VoiceService.instance.pregunta(depto, preguntas[step - 1].texto);
    } else {
      VoiceService.instance.gracias(depto);
    }
  }

  /// Al iniciar: si hay versión nueva, descarga e instala (silencioso con Knox).
  Future<void> _chequeoActualizacionSilencioso() async {
    try {
      final info = await UpdateService.instance.buscarActualizacion();
      if (info == null) return;
      final path = await UpdateService.instance.descargar(info);
      await UpdateService.instance.instalar(path);
    } catch (_) {/* sin red / error → se reintenta en el próximo arranque */}
  }

  Future<void> _cargarPreguntas() async {
    final ps = await _repo.cargarPreguntas(depto);
    if (mounted) setState(() => preguntas = ps);
  }

  void _start() {
    setState(() {
      _folio = null;
      _sesion = EncuestaSesion(
        id: _uuid.v4(),
        departamento: depto,
        iniciadaEn: DateTime.now(),
      );
      step = 1;
    });
    _hablar();
  }

  void _answer(Valor v) {
    final p = preguntas[step - 1];
    _sesion?.respuestas.add(RespuestaLocal(
      id: _uuid.v4(),
      preguntaId: p.id,
      valor: v,
      respondidaEn: DateTime.now(),
    ));
    if (step == preguntas.length && _sesion != null) {
      _sesion!.completadaEn = DateTime.now();
      _sesion!.evaluarCalidad(preguntas.length); // anti-trampa
      _repo.guardarEncuesta(_sesion!).then((folio) {
        if (mounted) setState(() => _folio = folio);
      });
    }
    setState(() => step++);
    _hablar();
  }

  void _reset() {
    setState(() {
      _sesion = null;
      step = 0;
    });
    _hablar();
  }

  // ----- Admin: cambiar de encuesta (protegido por PIN) -----
  Future<void> _abrirAdmin() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _PinDialog(),
    );
    if (ok != true || !mounted) return;
    final res = await showDialog<Object>(
      context: context,
      builder: (_) => _AdminPanel(actual: depto),
    );
    if (!mounted) return;
    if (res == 'update') {
      await showDialog(
          context: context, builder: (_) => const _UpdateDialog());
    } else if (res is Departamento && res != depto) {
      await _repo.fijarDepartamento(res);
      setState(() {
        depto = res;
        preguntas = seedPreguntas(res);
        _sesion = null;
        step = 0;
      });
      _cargarPreguntas();
      _hablar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = depto.theme;
    Widget child;
    if (step == 0) {
      child = WelcomeScreen(
          key: const ValueKey('welcome'),
          depto: depto,
          total: preguntas.length,
          onStart: _start);
    } else if (step <= preguntas.length) {
      final p = preguntas[step - 1];
      child = QuestionScreen(
          key: ValueKey('q${p.orden}'),
          depto: depto,
          pregunta: p,
          index: step,
          total: preguntas.length,
          onAnswer: _answer);
    } else {
      child = ThanksScreen(
          key: const ValueKey('thanks'),
          depto: depto,
          folio: _folio,
          onReset: _reset);
    }

    return Scaffold(
      body: BrandBackground(
        t: t,
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(depto: depto, onAdmin: _abrirAdmin, onRepeat: _hablar),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (c, a) {
                    final scale =
                        Tween(begin: .92, end: 1.0).animate(a);
                    final blur = Tween(begin: 8.0, end: 0.0).animate(a);
                    return FadeTransition(
                      opacity: a,
                      child: AnimatedBuilder(
                        animation: a,
                        builder: (_, child) => ImageFiltered(
                          imageFilter: ImageFilter.blur(
                              sigmaX: blur.value, sigmaY: blur.value),
                          child: Transform.scale(scale: scale.value, child: child),
                        ),
                        child: c,
                      ),
                    );
                  },
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final Departamento depto;
  final VoidCallback onAdmin;
  final VoidCallback onRepeat;
  const _TopBar(
      {required this.depto, required this.onAdmin, required this.onRepeat});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .65),
        border: const Border(bottom: BorderSide(color: Brand.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Long-press en el título = acceso oculto al panel de admin.
          Flexible(
            child: GestureDetector(
              onLongPress: onAdmin,
              behavior: HitTestBehavior.opaque,
              child: Text('Patronato · Hospital Materno Infantil',
                  overflow: TextOverflow.ellipsis,
                  style: display(15, weight: FontWeight.w700)),
            ),
          ),
          IconButton(
            onPressed: onRepeat,
            tooltip: 'Escuchar de nuevo',
            icon: Icon(Icons.volume_up_rounded, color: depto.theme.accentDeep),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Brand.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: depto.theme.accent, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text('${depto.nombre} · ${depto.pisos}',
                  style:
                      body(12, weight: FontWeight.w700, color: Brand.inkSoft)),
            ]),
          ),
        ],
      ),
    );
  }
}

// ============================ BIENVENIDA ============================
class WelcomeScreen extends StatelessWidget {
  final Departamento depto;
  final int total;
  final VoidCallback onStart;
  const WelcomeScreen({
    super.key,
    required this.depto,
    required this.total,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final t = depto.theme;
    final esGine = depto == Departamento.ginecologia;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeInUp(child: BulbLogo(color: t.accentDeep, size: 128)),
              const SizedBox(height: 20),
              FadeInUp(
                delay: const Duration(milliseconds: 120),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: display(30, weight: FontWeight.w600),
                    children: [
                      TextSpan(
                          text: esGine
                              ? 'Antes de irte, ¿nos regalas '
                              : 'Antes de irse, ¿nos regala '),
                      TextSpan(
                          text: '30 segundos',
                          style: display(30,
                              weight: FontWeight.w700, color: t.accentDeep)),
                      const TextSpan(text: '?'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FadeInUp(
                delay: const Duration(milliseconds: 220),
                child: Text(
                  esGine
                      ? 'Tu opinión nos ayuda a mejorar la atención para cada mamá y bebé. Es totalmente anónima.'
                      : 'Su opinión nos ayuda a cuidar mejor a cada niña y niño que atendemos. Es totalmente anónima.',
                  textAlign: TextAlign.center,
                  style:
                      body(16, weight: FontWeight.w500, color: Brand.inkSoft),
                ),
              ),
              const SizedBox(height: 24),
              FadeInUp(
                delay: const Duration(milliseconds: 320),
                child: Wrap(spacing: 22, children: [
                  _meta('⏱ $total preguntas'),
                  _meta('🔒 100% anónima'),
                ]),
              ),
              const SizedBox(height: 28),
              FadeInUp(
                delay: const Duration(milliseconds: 420),
                child: AnimatedStartButton(
                    color: t.accent, colorDeep: t.accentDeep, onTap: onStart),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(String s) =>
      Text(s, style: body(13, weight: FontWeight.w700, color: Brand.inkMute));
}

// ============================ PREGUNTA ============================
class QuestionScreen extends StatelessWidget {
  final Departamento depto;
  final Pregunta pregunta;
  final int index, total;
  final ValueChanged<Valor> onAnswer;
  const QuestionScreen({
    super.key,
    required this.depto,
    required this.pregunta,
    required this.index,
    required this.total,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final t = depto.theme;
    // Layout optimizado para la Galaxy Tab (~11", 16:10, horizontal):
    // contenido centrado y con anchos acotados para no estirarse de borde a borde.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 22, 40, 34),
          child: Column(
            children: [
              // Barra de progreso (todo el ancho del contenido)
              Row(children: [
                Text('PREGUNTA $index DE $total',
                    style:
                        body(11, weight: FontWeight.w700, color: Brand.inkMute)),
                const SizedBox(width: 18),
                Expanded(
                  child: GradientProgress(
                      value: index / total, from: t.accent, to: t.accentDeep),
                ),
                const SizedBox(width: 18),
                Text('$index/$total',
                    style:
                        body(11, weight: FontWeight.w700, color: Brand.inkMute)),
              ]),
              // Pregunta centrada vertical y horizontalmente
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: WordReveal(
                      text: pregunta.texto,
                      startDelay: const Duration(milliseconds: 120),
                      style: display(30, weight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              // Botones de respuesta: centrados, ancho acotado, equiespaciados
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: Row(
                  children: [
                    for (var i = 0; i < Valor.values.length; i++) ...[
                      Expanded(
                        child: FadeInUp(
                          delay: Duration(milliseconds: 250 + i * 100),
                          child: _EmojiButton(
                              valor: Valor.values[i],
                              index: i,
                              onTap: () => onAnswer(Valor.values[i])),
                        ),
                      ),
                      if (i < Valor.values.length - 1)
                        const SizedBox(width: 20),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiButton extends StatefulWidget {
  final Valor valor;
  final int index;
  final VoidCallback onTap;
  const _EmojiButton(
      {required this.valor, required this.index, required this.onTap});
  @override
  State<_EmojiButton> createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<_EmojiButton>
    with TickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat(reverse: true);
  late final AnimationController _sel =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  bool _selected = false;

  @override
  void initState() {
    super.initState();
    // Desfase del flotar según la posición (no flotan al unísono).
    Future.delayed(Duration(milliseconds: widget.index * 350), () {
      if (mounted) _float.forward(from: widget.index / 3);
    });
  }

  @override
  void dispose() {
    _float.dispose();
    _sel.dispose();
    super.dispose();
  }

  void _onTap() {
    if (_selected) return;
    HapticFeedback.mediumImpact();
    setState(() => _selected = true);
    _sel.forward(from: 0).then((_) {
      if (mounted) widget.onTap();
    });
  }

  /// Gesto por emoción: (escala, ángulo, dx, dy).
  (double, double, double, double) _emote(double v) {
    final pop = math.sin(v * math.pi); // 0→1→0
    switch (widget.valor) {
      case Valor.satisfecho: // 😊 salta de alegría
        final scale = v < .5 ? 1 + .8 * (v / .5) : 1.4 - .25 * ((v - .5) / .5);
        final angle = (v < .5 ? -.17 * (v / .5) : -.17 * (1 - (v - .5) / .5));
        final dy = -22 * pop; // brinco
        return (scale, angle, 0, dy);
      case Valor.neutral: // 😐 se encoge / duda (wiggle)
        final scale = 1 + .12 * pop;
        final angle = math.sin(v * math.pi * 3) * .12 * (1 - v);
        return (scale, angle, 0, 2 * pop);
      case Valor.insatisfecho: // ☹️ niega con la cabeza (shake)
        final scale = 1 + .08 * pop;
        final dx = math.sin(v * math.pi * 6) * 12 * (1 - v);
        return (scale, 0, dx, 4 * pop);
    }
  }

  /// Onda de choque que se expande al seleccionar.
  Widget _shockwave(double s, Color color) {
    return Opacity(
      opacity: ((1 - s) * .6).clamp(0, 1),
      child: Transform.scale(
        scale: .3 + s * 2.2,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.5),
          ),
        ),
      ),
    );
  }

  /// Destellos que salen disparados (solo en "Satisfecho").
  List<Widget> _sparkles(double s) {
    final dist = 46 * Curves.easeOut.transform(s);
    return [
      for (var k = 0; k < 6; k++)
        Transform.translate(
          offset: Offset(
            math.cos(k / 6 * 2 * math.pi) * dist,
            math.sin(k / 6 * 2 * math.pi) * dist - 8 * s,
          ),
          child: Opacity(
            opacity: (1 - s).clamp(0, 1),
            child: const Text('✨', style: TextStyle(fontSize: 14)),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.valor;
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 178),
        padding: const EdgeInsets.fromLTRB(12, 26, 12, 18),
        decoration: BoxDecoration(
          color: _selected ? v.bg : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: _selected ? v.color : Colors.transparent, width: 2),
          boxShadow: [
            BoxShadow(
                color: _selected
                    ? v.color.withValues(alpha: .28)
                    : const Color(0x14322832),
                blurRadius: _selected ? 22 : 14,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_float, _sel]),
              builder: (_, __) {
                final floatY = -4 * Curves.easeInOut.transform(_float.value);
                var scale = 1.0, angle = 0.0, dx = 0.0, dy = floatY;
                final s = _sel.value;
                if (s > 0) {
                  final e = _emote(s);
                  scale = e.$1;
                  angle = e.$2;
                  dx = e.$3;
                  dy = e.$4;
                }
                final emoji = Transform.translate(
                  offset: Offset(dx, dy),
                  child: Transform.rotate(
                    angle: angle,
                    child: Transform.scale(
                      scale: scale,
                      child: Text(v.emoji, style: const TextStyle(fontSize: 64)),
                    ),
                  ),
                );
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    if (s > 0 && s < 1) _shockwave(s, v.color),
                    if (s > 0 && v == Valor.satisfecho) ..._sparkles(s),
                    emoji,
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Text(v.label,
                style: body(15, weight: FontWeight.w700, color: Brand.inkSoft)),
          ],
        ),
      ),
    );
  }
}

// ============================ GRACIAS ============================
class ThanksScreen extends StatefulWidget {
  final Departamento depto;
  final int? folio;
  final VoidCallback onReset;
  const ThanksScreen(
      {super.key, required this.depto, this.folio, required this.onReset});
  @override
  State<ThanksScreen> createState() => _ThanksScreenState();
}

class _ThanksScreenState extends State<ThanksScreen> {
  int _n = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_n <= 1) {
        _timer?.cancel();
        widget.onReset();
      } else {
        setState(() => _n--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esGine = widget.depto == Departamento.ginecologia;
    final t = widget.depto.theme;
    return Stack(
      children: [
        // Centro: corazón latiendo + mensajes escalonados
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BeatingHeart(ringColor: t.accent),
                  const SizedBox(height: 16),
                  FadeInUp(
                    delay: const Duration(milliseconds: 300),
                    child: Text(
                        esGine ? '¡Gracias mamá!' : '¡Gracias por su tiempo!',
                        textAlign: TextAlign.center,
                        style: display(32, weight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 12),
                  FadeInUp(
                    delay: const Duration(milliseconds: 480),
                    child: Text(
                      esGine
                          ? 'Tu voz nos ayuda a brindar una mejor experiencia a cada familia. ¡Te deseamos lo mejor a ti y a tu bebé! 👶'
                          : 'Su opinión nos ayuda a brindar la mejor atención a cada niña y niño. ¡Le deseamos una pronta recuperación a su pequeño!',
                      textAlign: TextAlign.center,
                      style:
                          body(15, weight: FontWeight.w600, color: Brand.inkSoft),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (widget.folio != null)
                    FadeInUp(
                      delay: const Duration(milliseconds: 620),
                      child: _RegistradaBadge(
                          folio: widget.folio!, accent: t.accentDeep),
                    ),
                  const SizedBox(height: 18),
                  FadeInUp(
                    delay: const Duration(milliseconds: 760),
                    child: Text('Regresando al inicio en $_n…',
                        style: body(12,
                            weight: FontWeight.w700, color: Brand.inkMute)),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Overlays de celebración
        const Positioned.fill(child: Confetti()),
        const Positioned.fill(child: FloatingHearts()),
      ],
    );
  }
}

class _RegistradaBadge extends StatelessWidget {
  final int folio;
  final Color accent;
  const _RegistradaBadge({required this.folio, required this.accent});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Brand.line),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14322832), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DrawnCheck(color: accent, size: 20),
          const SizedBox(width: 8),
          Text('Respuesta',
              style: body(12, weight: FontWeight.w700, color: Brand.inkSoft)),
          const SizedBox(width: 5),
          AnimatedCounter(
              value: folio,
              prefix: '#',
              style: display(15, weight: FontWeight.w700, color: accent)),
          const SizedBox(width: 6),
          Text('registrada',
              style: body(12, weight: FontWeight.w700, color: Brand.inkSoft)),
        ],
      ),
    );
  }
}

// ============================ ADMIN ============================
class _PinDialog extends StatefulWidget {
  const _PinDialog();
  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  void _validar() {
    if (_ctrl.text == Config.adminPin) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'PIN incorrecto');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Acceso de administrador', style: display(18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Ingresa el PIN para cambiar la encuesta.',
              style: body(13, weight: FontWeight.w500, color: Brand.inkSoft)),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            obscureText: true,
            autofocus: true,
            textAlign: TextAlign.center,
            style: display(24, weight: FontWeight.w700),
            decoration: InputDecoration(
              counterText: '',
              errorText: _error,
              border: const OutlineInputBorder(),
              hintText: '••••',
            ),
            onSubmitted: (_) => _validar(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _validar, child: const Text('Entrar')),
      ],
    );
  }
}

class _AdminPanel extends StatelessWidget {
  final Departamento actual;
  const _AdminPanel({required this.actual});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Configuración de la tablet', style: display(18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ENCUESTA ACTIVA',
              style: body(11, weight: FontWeight.w700, color: Brand.inkMute)),
          const SizedBox(height: 8),
          RadioGroup<Departamento>(
            groupValue: actual,
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in Departamento.values)
                  RadioListTile<Departamento>(
                    value: d,
                    activeColor: d.theme.accentDeep,
                    title:
                        Text(d.nombre, style: body(15, weight: FontWeight.w700)),
                    subtitle: Text(d.pisos, style: body(12, color: Brand.inkMute)),
                  ),
              ],
            ),
          ),
          const Divider(height: 24),
          FutureBuilder<int>(
            future: EncuestaRepository.instance.pendientesCount(),
            builder: (_, snap) => Row(
              children: [
                const Icon(Icons.cloud_upload_outlined,
                    size: 18, color: Brand.inkMute),
                const SizedBox(width: 8),
                Text('Pendientes de sincronizar: ${snap.data ?? '—'}',
                    style:
                        body(12, weight: FontWeight.w600, color: Brand.inkSoft)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'update'),
              icon: const Icon(Icons.system_update_alt, size: 18),
              label: const Text('Buscar actualizaciones'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    );
  }
}

// ============================ ACTUALIZACIÓN (OTA) ============================
class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  String _estado = 'Buscando actualización…';
  double? _progreso;
  bool _terminado = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final info = await UpdateService.instance.buscarActualizacion();
      if (info == null) {
        _set('Ya tienes la última versión. ✅', terminado: true);
        return;
      }
      _set('Descargando versión ${info.version}…', progreso: 0);
      final path = await UpdateService.instance.descargar(
        info,
        onProgress: (r, t) {
          if (t > 0) _set('Descargando versión ${info.version}…', progreso: r / t);
        },
      );
      _set('Instalando…');
      final ok = await UpdateService.instance.instalar(path);
      _set(ok ? 'Instalación iniciada. ✅' : 'No se pudo instalar.',
          terminado: true);
    } catch (e) {
      _set('Error al actualizar. Revisa la conexión.', terminado: true);
    }
  }

  void _set(String estado, {double? progreso, bool terminado = false}) {
    if (!mounted) return;
    setState(() {
      _estado = estado;
      _progreso = progreso;
      _terminado = terminado;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Actualización', style: display(18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_estado,
              style: body(14, weight: FontWeight.w600, color: Brand.inkSoft)),
          if (_progreso != null) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(value: _progreso),
            const SizedBox(height: 6),
            Text('${(_progreso! * 100).round()}%',
                style: body(11, weight: FontWeight.w700, color: Brand.inkMute)),
          ] else if (!_terminado) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
      actions: [
        if (_terminado)
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
      ],
    );
  }
}
