import 'package:flutter/material.dart';

import '../services/canon_camera_service.dart';
import '../state/photo_booth_config.dart';

/// Palet pastel lembut (soft watercolor) untuk halaman awal booth.
class _Cozy {
  const _Cozy._();

  static const Color skyTop = Color(0xFFBFE0F2);
  static const Color skyMid = Color(0xFFDCEEF6);
  static const Color creamLow = Color(0xFFF7F1E3);
  static const Color cream = Color(0xFFFDF8EE);

  static const Color ink = Color(0xFF2C3A4B);
  static const Color inkSoft = Color(0xFF5C6B7C);
  static const Color inkMuted = Color(0xFF8A98A8);

  static const Color butter = Color(0xFFF6D68A);
  static const Color butterDeep = Color(0xFFE9B949);
  static const Color rose = Color(0xFFF3B7B0);
  static const Color sage = Color(0xFFA8C8A0);
  static const Color lilac = Color(0xFFC3B7E4);
  static const Color aqua = Color(0xFF9FCBDD);
  static const Color clay = Color(0xFFE0A98A);

  static const Color cardBorder = Color(0x33FFFFFF);

  // Aset ilustrasi cat air.
  static const String bgAsset = 'assets/images/background.png';
  static const String cameraAsset = 'assets/images/kamera.png';
  static const String sootAsset = 'assets/images/sootjump.png';
  static const String bunnyAsset = 'assets/images/bunnywave.png';

  static List<BoxShadow> get softShadow => const <BoxShadow>[
        BoxShadow(
          color: Color(0x1A4A5A6A),
          blurRadius: 26,
          offset: Offset(0, 12),
        ),
      ];
}

/// Home screen operator booth: status perangkat + akses cepat semua modul.
class LauncherPage extends StatelessWidget {
  const LauncherPage({
    super.key,
    required this.config,
    required this.canon,
  });

  final PhotoBoothConfig config;
  final CanonCameraService canon;

  @override
  Widget build(BuildContext context) {
    final List<_LauncherAction> actions = <_LauncherAction>[
      const _LauncherAction(
        'Canon Setup',
        'Koneksi EOS R100, live view, eksposur',
        '/canon',
        Icons.camera,
        _Cozy.clay,
      ),
      const _LauncherAction(
        'Settings',
        'Kamera, printer, timer, payment',
        '/settings',
        Icons.tune,
        _Cozy.aqua,
      ),
      const _LauncherAction(
        'Frames',
        'Kelola template photostrip',
        '/frames',
        Icons.border_style,
        _Cozy.lilac,
      ),
      const _LauncherAction(
        'Filters',
        'Preset warna untuk hasil foto',
        '/filters',
        Icons.auto_fix_high,
        _Cozy.sage,
      ),
      const _LauncherAction(
        'Crop',
        'Atur framing live view',
        '/crop',
        Icons.crop,
        _Cozy.aqua,
      ),
      const _LauncherAction(
        'Session Re-Print',
        'Cetak ulang hasil sesi lama',
        '/session-reprint',
        Icons.print,
        _Cozy.butterDeep,
      ),
      const _LauncherAction(
        'Uploads',
        'Sinkron file ke drive booth',
        '/uploads',
        Icons.cloud_upload,
        _Cozy.lilac,
      ),
      const _LauncherAction(
        'API Monolith',
        'Konfigurasi & sinkron ke server Laravel',
        '/api-settings',
        Icons.cloud_sync,
        _Cozy.aqua,
      ),
      const _LauncherAction(
        'Custom Appearance',
        'Warna, logo, font, background',
        '/appearance',
        Icons.palette_outlined,
        _Cozy.rose,
      ),
      const _LauncherAction(
        'Setup Wizard',
        'Panduan cepat 5 langkah',
        '/wizard',
        Icons.auto_awesome,
        _Cozy.sage,
      ),
    ];

    final ThemeData base = Theme.of(context);
    final ThemeData cozyTheme = base.copyWith(
      scaffoldBackgroundColor: _Cozy.cream,
      textTheme: base.textTheme.apply(
        bodyColor: _Cozy.ink,
        displayColor: _Cozy.ink,
      ),
      iconTheme: const IconThemeData(color: _Cozy.inkSoft),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _Cozy.ink,
          side: const BorderSide(color: Color(0x55FFFFFF), width: 1.4),
          backgroundColor: Colors.white.withValues(alpha: 0.45),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: _Cozy.ink,
          backgroundColor: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );

    return Theme(
      data: cozyTheme,
      child: Scaffold(
        body: _CozyBackground(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool wide = constraints.maxWidth >= 1040;

                final Widget hero = _HeroPanel(config: config, canon: canon);
                final Widget grid = _ActionGrid(
                  actions: actions,
                  columns: constraints.maxWidth >= 700 ? 2 : 1,
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _TopBar(config: config, canon: canon),
                      const SizedBox(height: 22),
                      if (wide)
                        // Tanpa IntrinsicHeight: panel kanan memakai
                        // LayoutBuilder yang tidak mendukung intrinsic sizing.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(flex: 5, child: hero),
                            const SizedBox(width: 20),
                            Expanded(flex: 5, child: grid),
                          ],
                        )
                      else ...<Widget>[
                        hero,
                        const SizedBox(height: 20),
                        grid,
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Latar cat air: gradasi langit ke krem + bulatan warna lembut.
class _CozyBackground extends StatelessWidget {
  const _CozyBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // Gradasi dipakai sebagai dasar sekaligus cadangan bila gambar latar
        // gagal dimuat.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                _Cozy.skyTop,
                _Cozy.skyMid,
                _Cozy.creamLow,
                _Cozy.cream,
              ],
              stops: <double>[0, 0.38, 0.76, 1],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned.fill(
          child: Image.asset(
            _Cozy.bgAsset,
            fit: BoxFit.cover,
            // Jangan sembunyikan diam-diam: kalau aset belum ter-bundle,
            // tampilkan peringatan supaya jelas penyebabnya.
            errorBuilder: (BuildContext context, Object error,
                    StackTrace? stackTrace) =>
                const _AssetWarning(),
          ),
        ),
        const Positioned(
          top: -150,
          left: -110,
          child: _SoftBlob(color: Color(0x66FFFFFF), size: 420),
        ),
        const Positioned(
          top: 40,
          right: -120,
          child: _SoftBlob(color: Color(0x44F6D68A), size: 380),
        ),
        const Positioned(
          bottom: -180,
          left: 60,
          child: _SoftBlob(color: Color(0x40A8C8A0), size: 460),
        ),
        const Positioned(
          bottom: -140,
          right: -80,
          child: _SoftBlob(color: Color(0x3AF3B7B0), size: 400),
        ),
        // Maskot ditempatkan relatif terhadap ukuran layar supaya tidak
        // menabrak kartu menu di resolusi kecil.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double w = c.maxWidth;
              final double h = c.maxHeight;
              final double bunny = (w * 0.17).clamp(120.0, 240.0);

              return Stack(
                children: <Widget>[
                  Positioned(
                    top: h * 0.06,
                    left: w * 0.30,
                    child: const _Mascot(
                        asset: _Cozy.sootAsset, size: 58, opacity: 0.9),
                  ),
                  Positioned(
                    top: h * 0.16,
                    right: w * 0.06,
                    child: const _Mascot(
                        asset: _Cozy.sootAsset, size: 40, opacity: 0.75),
                  ),
                  Positioned(
                    bottom: h * 0.10,
                    left: w * 0.02,
                    child: const _Mascot(
                        asset: _Cozy.sootAsset, size: 50, opacity: 0.8),
                  ),
                  Positioned(
                    bottom: 0,
                    right: w * 0.01,
                    child: _Mascot(
                        asset: _Cozy.bunnyAsset, size: bunny, opacity: 0.95),
                  ),
                ],
              );
            },
          ),
        ),
        child,
      ],
    );
  }
}

/// Peringatan bila aset gambar belum ter-bundle ke aplikasi.
class _AssetWarning extends StatelessWidget {
  const _AssetWarning();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1D6),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE9B949)),
            ),
            child: const Text(
              'Aset gambar belum ter-bundle. Jalankan: flutter pub get, '
              'lalu stop aplikasi dan flutter run ulang (hot restart tidak cukup).',
              style: TextStyle(
                color: Color(0xFF6B5312),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ilustrasi maskot yang tidak menghalangi interaksi.
class _Mascot extends StatelessWidget {
  const _Mascot({
    required this.asset,
    required this.size,
    this.opacity = 1,
  });

  final String asset;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Image.asset(
          asset,
          width: size,
          fit: BoxFit.contain,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) =>
                  const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _SoftBlob extends StatelessWidget {
  const _SoftBlob({required this.color, required this.size});

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

/// Kartu putih lembut dengan sudut membulat besar.
class _SoftCard extends StatelessWidget {
  const _SoftCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 26,
    this.onTap,
    this.borderColor,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint ?? Colors.white.withValues(alpha: 0.72),
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ?? _Cozy.cardBorder,
          width: 1.4,
        ),
        boxShadow: _Cozy.softShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.config, required this.canon});

  final PhotoBoothConfig config;
  final CanonCameraService canon;

  @override
  Widget build(BuildContext context) {
    final bool canonOn = canon.state.isConnected;

    return Row(
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[_Cozy.butter, _Cozy.clay],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _Cozy.softShadow,
          ),
          child: const Icon(Icons.camera_alt_rounded,
              color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                config.boothName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _Cozy.ink,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
              ),
              Text(
                'Operator Console',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _Cozy.inkMuted,
                    ),
              ),
            ],
          ),
        ),
        _CozyBadge(
          label: canonOn
              ? 'Canon EOS R100 siap'
              : (config.useCanonCamera
                  ? 'Canon belum tersambung'
                  : 'Mode webcam'),
          color: canonOn
              ? _Cozy.sage
              : (config.useCanonCamera ? _Cozy.rose : _Cozy.inkMuted),
        ),
        const SizedBox(width: 10),
        Material(
          color: Colors.white.withValues(alpha: 0.65),
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: 'Reconnect kamera',
            onPressed: () => canon.connect(),
            icon: const Icon(Icons.sync, color: _Cozy.inkSoft),
          ),
        ),
      ],
    );
  }
}

class _CozyBadge extends StatelessWidget {
  const _CozyBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _Cozy.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.config, required this.canon});

  final PhotoBoothConfig config;
  final CanonCameraService canon;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      padding: const EdgeInsets.all(28),
      radius: 30,
      tint: Colors.white.withValues(alpha: 0.78),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _Cozy.butter.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _Cozy.butterDeep.withValues(alpha: 0.5)),
            ),
            child: const Text(
              'MALL PHOTO BOOTH SYSTEM',
              style: TextStyle(
                color: Color(0xFF8A6A1F),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Image.asset(
              _Cozy.cameraAsset,
              width: 260,
              fit: BoxFit.contain,
              errorBuilder: (BuildContext context, Object error,
                      StackTrace? stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Siap jepret dengan\nlensa Canon EOS R100',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: _Cozy.ink,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                ),
          ),
          const SizedBox(height: 14),
          Text(
            'Live view langsung dari kamera Canon, countdown otomatis, '
            'frame & filter siap cetak dalam satu alur.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: _Cozy.inkSoft,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _InfoChip(
                icon: Icons.auto_fix_high,
                label: config.filter.label,
              ),
              _InfoChip(
                icon: Icons.border_outer,
                label: config.frame.name,
              ),
              _InfoChip(
                icon: Icons.timer_outlined,
                label: '${config.countdownSeconds}s countdown',
              ),
              _InfoChip(
                icon: Icons.burst_mode_outlined,
                label: '${config.photosPerSession} foto/sesi',
              ),
              _InfoChip(
                icon: config.useCanonCamera ? Icons.camera : Icons.videocam,
                label: config.useCanonCamera
                    ? 'Sumber: Canon R100'
                    : 'Sumber: kamera perangkat',
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: <Widget>[
              _CozyPrimaryButton(
                label: 'Mulai Booth',
                icon: Icons.play_arrow_rounded,
                onPressed: () => Navigator.of(context).pushNamed('/booth'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/canon'),
                  icon: const Icon(Icons.settings_input_antenna,
                      color: _Cozy.inkSoft),
                  label: const Text('Cek Kamera'),
                ),
              ),
            ],
          ),
          if (canon.statusMessage.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                const Icon(Icons.info_outline, size: 15, color: _Cozy.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    canon.statusMessage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _Cozy.inkMuted,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CozyPrimaryButton extends StatelessWidget {
  const _CozyPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[_Cozy.butter, _Cozy.butterDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33E9B949),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 20, color: _Cozy.ink),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: _Cozy.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
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

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.actions, required this.columns});

  final List<_LauncherAction> actions;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 14;
        final double itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: actions
              .map(
                (_LauncherAction action) => SizedBox(
                  width: itemWidth,
                  child: _ActionCard(action: action),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ActionCard extends StatefulWidget {
  const _ActionCard({required this.action});

  final _LauncherAction action;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final _LauncherAction action = widget.action;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.02 : 1,
        duration: const Duration(milliseconds: 160),
        child: _SoftCard(
          padding: const EdgeInsets.all(18),
          radius: 22,
          borderColor: _hover
              ? action.color.withValues(alpha: 0.75)
              : Colors.white.withValues(alpha: 0.7),
          tint: _hover
              ? action.color.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.7),
          onTap: () => Navigator.of(context).pushNamed(action.route),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: action.color.withValues(alpha: 0.55)),
                ),
                child: Icon(action.icon, color: _Cozy.ink, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      action.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: _Cozy.ink,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      action.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _Cozy.inkMuted,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: _hover ? _Cozy.ink : _Cozy.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x22415464)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: _Cozy.inkSoft),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _Cozy.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _LauncherAction {
  const _LauncherAction(
    this.label,
    this.subtitle,
    this.route,
    this.icon,
    this.color,
  );

  final String label;
  final String subtitle;
  final String route;
  final IconData icon;
  final Color color;
}
