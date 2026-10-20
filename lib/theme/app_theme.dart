import 'dart:ui';

import 'package:flutter/material.dart';

/// Central design system for the booth app.
///
/// Semua warna, radius, shadow, dan komponen "glass" dipakai ulang di seluruh
/// halaman supaya tampilan konsisten dan modern.
class AppTheme {
  const AppTheme._();

  // Core palette
  static const Color bgDeep = Color(0xFF070B16);
  static const Color bgBase = Color(0xFF0C1222);
  static const Color surface = Color(0xFF141B2E);
  static const Color surfaceHigh = Color(0xFF1B2440);
  static const Color stroke = Color(0x1FFFFFFF);
  static const Color strokeStrong = Color(0x33FFFFFF);

  static const Color accent = Color(0xFFF5C451);
  static const Color accentAlt = Color(0xFFFF7A59);
  static const Color mint = Color(0xFF2BD9A4);
  static const Color violet = Color(0xFF8B7CFF);
  static const Color sky = Color(0xFF4EA8FF);
  static const Color danger = Color(0xFFFF5C7A);

  static const Color textPrimary = Color(0xFFF3F5FB);
  static const Color textSecondary = Color(0xFFA6B0C8);
  static const Color textMuted = Color(0xFF6E7A96);

  // Typography: Fredoka (rounded, bouncy) untuk judul & tombol,
  // Nunito (rounded, ramah) untuk teks biasa. Keduanya dibundel di assets/fonts.
  static const String displayFont = 'Fredoka';
  static const String bodyFont = 'Nunito';

  /// Pilihan font untuk dropdown Typography di halaman Appearance.
  static const String fontPlayful = 'Fredoka + Nunito (Playful)';
  static const String fontFredoka = 'Fredoka';
  static const String fontNunito = 'Nunito';
  static const String fontSystem = 'Roboto (Classic)';
  static const List<String> fontChoices = <String>[
    fontPlayful,
    fontFredoka,
    fontNunito,
    fontSystem,
  ];

  /// (body, display) font family untuk satu pilihan.
  static (String, String) _resolveFonts(String choice) {
    switch (choice) {
      case fontFredoka:
        return (displayFont, displayFont);
      case fontNunito:
        return (bodyFont, bodyFont);
      case fontSystem:
        return ('Roboto', 'Roboto');
      case fontPlayful:
      default:
        return (bodyFont, displayFont);
    }
  }

  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 26;
  static const double radiusXl = 34;

  static const LinearGradient accentGradient = LinearGradient(
    colors: <Color>[Color(0xFFF5C451), Color(0xFFFF7A59)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient coolGradient = LinearGradient(
    colors: <Color>[Color(0xFF8B7CFF), Color(0xFF4EA8FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: <Color>[Color(0xFF070B16), Color(0xFF101A33), Color(0xFF070B16)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> softShadow({double opacity = 0.35, double blur = 30}) {
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: opacity),
        blurRadius: blur,
        offset: const Offset(0, 14),
      ),
    ];
  }

  static ThemeData build({String fontChoice = fontPlayful}) {
    final (String body, String display) = _resolveFonts(fontChoice);
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      onPrimary: const Color(0xFF1A1406),
      secondary: mint,
      onSecondary: const Color(0xFF04231A),
      surface: surface,
      onSurface: textPrimary,
      error: danger,
    );

    final TextTheme text = ThemeData(brightness: Brightness.dark)
        .textTheme
        .apply(
          bodyColor: textPrimary,
          displayColor: textPrimary,
          fontFamily: body,
        );

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: bgBase,
      colorScheme: scheme,
      canvasColor: bgBase,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: body,
      textTheme: text.copyWith(
        displayLarge: text.displayLarge?.copyWith(
          fontFamily: display,
          fontWeight: FontWeight.w700,
        ),
        displayMedium: text.displayMedium?.copyWith(
          fontFamily: display,
          fontWeight: FontWeight.w700,
        ),
        displaySmall: text.displaySmall?.copyWith(
          fontFamily: display,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        headlineLarge: text.headlineLarge?.copyWith(
          fontFamily: display,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontFamily: display,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontFamily: display,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontFamily: display,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontFamily: display,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: text.titleSmall?.copyWith(
          fontFamily: display,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: text.bodyMedium?.copyWith(color: textSecondary),
        labelLarge: text.labelLarge?.copyWith(
          fontFamily: display,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: display,
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: stroke),
        ),
      ),
      dividerTheme: const DividerThemeData(color: stroke, thickness: 1),
      iconTheme: const IconThemeData(color: textPrimary),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF1A1406),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: TextStyle(
            fontFamily: display,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: strokeStrong),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: TextStyle(fontFamily: display, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: TextStyle(fontFamily: display, fontWeight: FontWeight.w600),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF101728),
        hintStyle: const TextStyle(color: textMuted),
        labelStyle: const TextStyle(color: textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: accent, width: 1.6),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? const Color(0xFF1A1406)
              : textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? accent
              : const Color(0xFF232C45),
        ),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(stroke),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: Color(0xFF232C45),
        thumbColor: accent,
        overlayColor: Color(0x33F5C451),
        trackHeight: 5,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceHigh,
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(color: stroke),
        ),
        textStyle: const TextStyle(color: textPrimary, fontSize: 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: stroke),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: Color(0xFF232C45),
      ),
    );
  }
}

/// Background gradient + soft glow blobs, dipakai sebagai dasar tiap halaman.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppTheme.backgroundGradient),
          child: SizedBox.expand(),
        ),
        const Positioned(
          top: -160,
          left: -120,
          child: _GlowBlob(color: Color(0x33F5C451), size: 420),
        ),
        const Positioned(
          bottom: -200,
          right: -140,
          child: _GlowBlob(color: Color(0x2A8B7CFF), size: 520),
        ),
        child,
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Kartu kaca (glassmorphism) serbaguna.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppTheme.radiusLg,
    this.blur = 18,
    this.onTap,
    this.borderColor,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint ?? Colors.white.withValues(alpha: 0.05),
            borderRadius: borderRadius,
            border: Border.all(color: borderColor ?? AppTheme.stroke),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge status kecil (online/offline/warning).
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ] else ...<Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Judul section dengan subjudul opsional.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Tombol utama dengan gradient.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.gradient = AppTheme.accentGradient,
    this.expand = false,
    this.padding =
        const EdgeInsets.symmetric(horizontal: 26, vertical: 17),
    this.fontSize = 16,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Gradient gradient;
  final bool expand;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null;

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 20, color: const Color(0xFF17130A)),
          const SizedBox(width: 10),
        ],
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF17130A),
            fontWeight: FontWeight.w800,
            fontSize: fontSize,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );

    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: disabled
              ? null
              : <BoxShadow>[
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.28),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            onTap: onPressed,
            child: Padding(padding: padding, child: content),
          ),
        ),
      ),
    );
  }
}
