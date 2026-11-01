import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Palet default halaman awal PhotoBooth (biru malam + emas hangat).
class LandingPalette {
  const LandingPalette._();

  static const Color navyDeep = Color(0xFF0A1B33);
  static const Color navy = Color(0xFF123A66);
  static const Color blue = Color(0xFF215A97);
  static const Color amber = Color(0xFFF59A27);
  static const Color gold = Color(0xFFFFC156);
  static const Color ink = Color(0xFF1E2A3B);
  static const Color inkSoft = Color(0xFF5B6B80);
}

/// Latar default: gradasi biru malam, cahaya hangat di bawah, dan bokeh
/// lembut yang bergerak pelan. Dipakai bila operator belum mengunggah
/// background sendiri.
class LandingBackdrop extends StatefulWidget {
  const LandingBackdrop({super.key});

  @override
  State<LandingBackdrop> createState() => _LandingBackdropState();
}

class _LandingBackdropState extends State<LandingBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (BuildContext context, _) => CustomPaint(
          painter: _BackdropPainter(_ctrl.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t);

  final double t;

  // (x, y, radius, phase, warm?) — posisi relatif 0..1.
  static const List<(double, double, double, double, bool)> _bokeh =
      <(double, double, double, double, bool)>[
    (0.10, 0.18, 70, 0.00, false),
    (0.22, 0.72, 46, 0.15, true),
    (0.34, 0.12, 34, 0.30, true),
    (0.52, 0.88, 82, 0.45, false),
    (0.66, 0.20, 52, 0.60, true),
    (0.80, 0.64, 64, 0.75, false),
    (0.90, 0.14, 38, 0.90, true),
    (0.06, 0.52, 28, 0.35, true),
    (0.94, 0.86, 48, 0.55, true),
    (0.46, 0.40, 24, 0.80, false),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // Dasar gradasi.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            LandingPalette.navyDeep,
            LandingPalette.navy,
            Color(0xFF1A4A7C),
          ],
          stops: <double>[0, 0.55, 1],
        ).createShader(rect),
    );

    // Cahaya hangat dari bawah (nuansa lampu studio).
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 1.25),
          radius: 1.1,
          colors: <Color>[
            LandingPalette.amber.withValues(alpha: 0.34),
            LandingPalette.amber.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Cahaya biru muda di kiri atas.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.9, -1.0),
          radius: 0.9,
          colors: <Color>[
            const Color(0xFF4EA8FF).withValues(alpha: 0.22),
            const Color(0xFF4EA8FF).withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Bokeh melayang pelan.
    for (final (double x, double y, double r, double phase, bool warm)
        in _bokeh) {
      final double a = (t + phase) * 2 * math.pi;
      final Offset c = Offset(
        size.width * x + math.sin(a) * 18,
        size.height * y + math.cos(a * 0.8) * 14,
      );
      final Color color = warm ? LandingPalette.gold : Colors.white;
      final double radius = r * (size.shortestSide / 700).clamp(0.7, 1.6);

      canvas.drawCircle(
        c,
        radius,
        Paint()..color = color.withValues(alpha: warm ? 0.10 : 0.07),
      );
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: warm ? 0.22 : 0.14),
      );
    }

    // Vignette halus supaya fokus ke tengah.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 1.05,
          colors: <Color>[
            Colors.transparent,
            Colors.black.withValues(alpha: 0.30),
          ],
          stops: const <double>[0.62, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.t != t;
}

/// Kartu utama halaman awal: putih lembut, sudut besar, bayangan dalam,
/// dan animasi masuk (fade + naik sedikit).
class LandingCard extends StatelessWidget {
  const LandingCard({super.key, required this.child, this.width = 560});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double v, Widget? child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 24),
          child: child,
        ),
      ),
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxWidth: double.infinity),
        padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFFFFFFFF), Color(0xFFF1F4F9)],
          ),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 60,
              offset: const Offset(0, 28),
            ),
            BoxShadow(
              color: LandingPalette.amber.withValues(alpha: 0.12),
              blurRadius: 80,
              spreadRadius: 4,
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Tagline dengan garis dekoratif di atasnya.
class LandingTagline extends StatelessWidget {
  const LandingTagline({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 56,
          height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[LandingPalette.blue, LandingPalette.amber],
            ),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: LandingPalette.ink,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
        ),
      ],
    );
  }
}

/// Logo bawaan (dipakai bila operator belum mengunggah logo): cincin gradasi
/// dengan highlight kaca, ikon kamera, dan nama booth.
class DefaultBoothLogo extends StatelessWidget {
  const DefaultBoothLogo({super.key, required this.boothName, this.size = 300});

  final String boothName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final double ring = size * 0.028;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const SweepGradient(
          colors: <Color>[
            LandingPalette.blue,
            LandingPalette.amber,
            LandingPalette.gold,
            LandingPalette.blue,
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: LandingPalette.blue.withValues(alpha: 0.35),
            blurRadius: 36,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: LandingPalette.amber.withValues(alpha: 0.25),
            blurRadius: 50,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF14375F),
              Color(0xFF215A97),
              Color(0xFFE08A22),
            ],
            stops: <double>[0, 0.5, 1],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Highlight kaca di bagian atas lensa.
            Positioned(
              top: size * 0.04,
              child: Container(
                width: size * 0.62,
                height: size * 0.26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: size * 0.1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.camera_alt_rounded,
                    size: size * 0.17,
                    color: LandingPalette.gold.withValues(alpha: 0.95),
                  ),
                  SizedBox(height: size * 0.03),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      boothName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        color: LandingPalette.gold,
                        fontSize: size * 0.135,
                        fontWeight: FontWeight.w900,
                        letterSpacing: size * 0.008,
                        shadows: const <Shadow>[
                          Shadow(
                            color: Color(0x55000000),
                            blurRadius: 12,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tombol "Tap to Start!" — pil emas dengan denyut halus supaya menarik
/// perhatian pengunjung.
class LandingStartButton extends StatefulWidget {
  const LandingStartButton({
    super.key,
    required this.onPressed,
    this.label = 'Tap to Start!',
  });

  final VoidCallback onPressed;
  final String label;

  @override
  State<LandingStartButton> createState() => _LandingStartButtonState();
}

class _LandingStartButtonState extends State<LandingStartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (BuildContext context, Widget? child) {
        final double e = Curves.easeInOut.transform(_pulse.value);
        return Transform.scale(
          scale: 1 + e * 0.035,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[LandingPalette.gold, LandingPalette.amber],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: LandingPalette.amber.withValues(alpha: 0.30 + e * 0.30),
                  blurRadius: 24 + e * 22,
                  spreadRadius: e * 3,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.touch_app_rounded,
                    color: Color(0xFF1A1406), size: 28),
                const SizedBox(width: 12),
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF1A1406),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
