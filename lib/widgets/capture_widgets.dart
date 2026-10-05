// Komponen visual untuk layar pengambilan foto (booth_page.dart).
//
// Semuanya murni tampilan: tidak menyimpan state sesi dan tidak memanggil API.
// Data (jumlah foto, countdown, gambar thumbnail) dikirim dari BoothPage.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// ------------------------------------------------------------- countdown

/// Countdown besar di tengah live view: cincin yang menyusut tiap detik,
/// angka yang "pop", dan teks arahan di bawahnya.
class CaptureCountdown extends StatelessWidget {
  const CaptureCountdown({super.key, required this.value, this.prompt});

  final int value;
  final String? prompt;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: <Color>[
              Colors.black.withValues(alpha: 0.12),
              Colors.black.withValues(alpha: 0.58),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TweenAnimationBuilder<double>(
                key: ValueKey<int>(value),
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(seconds: 1),
                builder: (BuildContext context, double t, Widget? child) {
                  return SizedBox(
                    width: 210,
                    height: 210,
                    child: CustomPaint(
                      painter: _CountdownRingPainter(progress: t),
                      child: child,
                    ),
                  );
                },
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.55, end: 1),
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutBack,
                    builder:
                        (BuildContext context, double scale, Widget? child) {
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Text(
                      '$value',
                      style: const TextStyle(
                        fontSize: 104,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: <Shadow>[
                          Shadow(color: Colors.black54, blurRadius: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (prompt != null && prompt!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 22),
                Text(
                  prompt!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.3,
                    shadows: <Shadow>[
                      Shadow(color: Colors.black87, blurRadius: 14),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  _CountdownRingPainter({required this.progress});

  /// 0 -> 1 selama satu detik. Busur menyusut seiring progress.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2 - 12;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    // Piringan gelap supaya angka terbaca di atas background apa pun.
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Colors.black.withValues(alpha: 0.38),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = Colors.white.withValues(alpha: 0.16),
    );

    final double sweep = 2 * math.pi * (1 - progress);
    if (sweep <= 0.01) return;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..color = AppTheme.accent.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..shader = AppTheme.accentGradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ----------------------------------------------------------------- flash

/// Kilat putih saat shutter: muncul cepat, memudar halus.
class CaptureFlash extends StatelessWidget {
  const CaptureFlash({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: Duration(milliseconds: on ? 70 : 320),
        curve: Curves.easeOut,
        child: const ColoredBox(color: Colors.white),
      ),
    );
  }
}

// ------------------------------------------------------------ viewfinder

/// Empat sudut bingkai ala viewfinder kamera.
class ViewfinderCorners extends StatelessWidget {
  const ViewfinderCorners({
    super.key,
    this.color = Colors.white70,
    this.inset = 20,
    this.length = 34,
  });

  final Color color;
  final double inset;
  final double length;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: const Duration(milliseconds: 250),
        builder: (BuildContext context, Color? value, Widget? _) {
          return SizedBox.expand(
            child: CustomPaint(
              painter: _CornersPainter(
                color: value ?? color,
                inset: inset,
                length: length,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CornersPainter extends CustomPainter {
  _CornersPainter({
    required this.color,
    required this.inset,
    required this.length,
  });

  final Color color;
  final double inset;
  final double length;

  @override
  void paint(Canvas canvas, Size size) {
    final double l = inset;
    final double t = inset;
    final double r = size.width - inset;
    final double b = size.height - inset;

    final Path path = Path()
      ..moveTo(l, t + length)
      ..lineTo(l, t)
      ..lineTo(l + length, t)
      ..moveTo(r - length, t)
      ..lineTo(r, t)
      ..lineTo(r, t + length)
      ..moveTo(r, b - length)
      ..lineTo(r, b)
      ..lineTo(r - length, b)
      ..moveTo(l + length, b)
      ..lineTo(l, b)
      ..lineTo(l, b - length);

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CornersPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.inset != inset ||
      oldDelegate.length != length;
}

// ------------------------------------------------------------- progress

/// Pil kecil di pojok live view: "Foto 2 dari 4" + titik progres.
class CaptureProgressPill extends StatelessWidget {
  const CaptureProgressPill({
    super.key,
    required this.total,
    required this.taken,
    required this.running,
  });

  final int total;
  final int taken;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final String label =
        running ? 'Foto ${math.min(taken + 1, total)} dari $total' : '$total foto per sesi';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.photo_camera_rounded,
              size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 12),
          for (int i = 0; i < total; i++)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: i < taken
                  ? _dot(AppTheme.accent)
                  : (running && i == taken)
                      ? const _PulseDot()
                      : _dot(Colors.white24),
            ),
        ],
      ),
    );
  }

  static Widget _dot(Color color) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        final double v = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accent.withValues(alpha: 0.5 + 0.5 * v),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppTheme.accent.withValues(alpha: 0.6 * v),
                blurRadius: 8,
                spreadRadius: 1.5 * v,
              ),
            ],
          ),
        );
      },
    );
  }
}

// --------------------------------------------------------------- prompt

/// Teks arahan singkat di bawah live view ("Bagus! Ganti pose").
class CapturePromptBanner extends StatelessWidget {
  const CapturePromptBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.4),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey<String>(text),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- tray

/// Deretan thumbnail hasil foto selama sesi. Slot yang belum terisi tampil
/// sebagai kotak bernomor; foto baru muncul dengan animasi "pop".
class CaptureShotTray extends StatelessWidget {
  const CaptureShotTray({
    super.key,
    required this.total,
    required this.taken,
    required this.thumbBuilder,
  });

  final int total;
  final int taken;

  /// Dipanggil hanya untuk index < [taken].
  final Widget Function(int index) thumbBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 10;
        final double available =
            constraints.maxWidth - gap * math.max(0, total - 1);
        final double side =
            math.max(36.0, math.min(84.0, available / math.max(1, total)));

        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < total; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: gap),
                _TrayTile(
                  side: side,
                  index: i,
                  filled: i < taken,
                  active: i == taken,
                  thumb: i < taken ? thumbBuilder(i) : null,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TrayTile extends StatelessWidget {
  const _TrayTile({
    required this.side,
    required this.index,
    required this.filled,
    required this.active,
    required this.thumb,
  });

  final double side;
  final int index;
  final bool filled;
  final bool active;
  final Widget? thumb;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = filled
        ? AppTheme.accent
        : active
            ? AppTheme.accent.withValues(alpha: 0.6)
            : AppTheme.stroke;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: side,
      height: side,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: filled ? null : Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: borderColor, width: filled ? 2.5 : 1.5),
        boxShadow: filled
            ? <BoxShadow>[
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.25),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: thumb != null
          ? TweenAnimationBuilder<double>(
              key: ValueKey<int>(index),
              tween: Tween<double>(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (BuildContext context, double scale, Widget? child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: thumb,
              ),
            )
          : Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: active ? AppTheme.accent : AppTheme.textMuted,
                  fontSize: side * 0.34,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
    );
  }
}
