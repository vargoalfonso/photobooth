import 'package:flutter/material.dart';

import 'api_models.dart';

/// Filter foto ala Instagram. Tiap filter dibuat dari "resep" ([BoothFilterRecipe])
/// yang dirangkai jadi satu color matrix, ditambah vignette opsional.
///
/// [apiKey] adalah teks yang disimpan di server (`sessions.filter`); jangan
/// diubah untuk filter yang sudah ada supaya data lama tetap terbaca.
enum BoothFilter {
  none(
    apiKey: null,
    label: 'Natural',
    description: 'Warna asli tanpa filter.',
    accentColor: Color(0xFFF7D98A),
  ),
  glow(
    apiKey: 'glow',
    label: 'Glow',
    description: 'Kulit cerah dan lembut, seperti beauty mode.',
    accentColor: Color(0xFFFFC9A8),
    recipe: BoothFilterRecipe(brightness: 0.05, contrast: 0.94, saturation: 1.05, red: 1.04, blue: 0.98, fade: 0.04),
  ),
  clear(
    apiKey: 'clear',
    label: 'Clear',
    description: 'Kontras tegas, warna jernih.',
    accentColor: Color(0xFF4FA3E0),
    recipe: BoothFilterRecipe(contrast: 1.18, saturation: 1.25, red: 0.98, blue: 1.06, brightness: 0.02),
  ),
  fresh(
    apiKey: 'fresh',
    label: 'Fresh',
    description: 'Terang dan segar.',
    accentColor: Color(0xFF9BE3C2),
    recipe: BoothFilterRecipe(brightness: 0.06, contrast: 1.05, saturation: 0.95, red: 0.97, green: 1.03, blue: 1.05),
  ),
  sunny(
    apiKey: 'sunny',
    label: 'Sunny',
    description: 'Hangat cerah, warna pop.',
    accentColor: Color(0xFFFFB347),
    recipe: BoothFilterRecipe(contrast: 1.1, saturation: 1.3, red: 1.08, blue: 0.92, brightness: 0.02),
  ),
  honey(
    apiKey: 'honey',
    label: 'Honey',
    description: 'Madu keemasan yang lembut.',
    accentColor: Color(0xFFE8B04B),
    recipe: BoothFilterRecipe(saturation: 1.05, red: 1.08, green: 1.02, blue: 0.88, brightness: 0.03, fade: 0.08),
  ),
  golden(
    apiKey: 'golden',
    label: 'Golden Hour',
    description: 'Cahaya sore keemasan.',
    accentColor: Color(0xFFFF9A3C),
    recipe: BoothFilterRecipe(saturation: 1.15, contrast: 1.05, red: 1.14, green: 1.04, blue: 0.82, brightness: 0.04),
    vignette: 0.12,
  ),
  warm(
    apiKey: 'warm',
    label: 'Warm Glow',
    description: 'Tone hangat untuk skin tone lembut.',
    accentColor: Color(0xFFE58F65),
    recipe: BoothFilterRecipe(saturation: 1.1, red: 1.1, green: 1.01, blue: 0.9, brightness: 0.03),
  ),
  peach(
    apiKey: 'peach',
    label: 'Peach',
    description: 'Rona persik manis.',
    accentColor: Color(0xFFFFAD8F),
    recipe: BoothFilterRecipe(saturation: 1.1, contrast: 1.05, red: 1.08, green: 0.98, blue: 0.95, shiftRed: 14.0, shiftGreen: 4.0, shiftBlue: 10.0, fade: 0.1),
  ),
  rose(
    apiKey: 'rose',
    label: 'Rose',
    description: 'Pink lembut, romantis.',
    accentColor: Color(0xFFF29BB5),
    recipe: BoothFilterRecipe(saturation: 1.1, contrast: 1.05, red: 1.06, green: 0.97, blue: 1.02, shiftRed: 8.0, shiftBlue: 6.0, brightness: 0.04),
    vignette: 0.15,
  ),
  dreamy(
    apiKey: 'dreamy',
    label: 'Dreamy',
    description: 'Pudar lembut seperti mimpi.',
    accentColor: Color(0xFFD4B8F0),
    recipe: BoothFilterRecipe(saturation: 1.1, contrast: 0.9, blue: 1.06, brightness: 0.07, fade: 0.06),
    vignette: 0.15,
  ),
  pastel(
    apiKey: 'pastel',
    label: 'Pastel',
    description: 'Warna permen yang kalem.',
    accentColor: Color(0xFFB8E0D2),
    recipe: BoothFilterRecipe(saturation: 0.85, contrast: 0.85, red: 1.02, blue: 1.05, brightness: 0.08, fade: 0.08),
  ),
  softfade(
    apiKey: 'softfade',
    label: 'Soft Fade',
    description: 'Matte pudar, nuansa lavender.',
    accentColor: Color(0xFFC9C3E6),
    recipe: BoothFilterRecipe(saturation: 0.9, contrast: 0.95, blue: 1.04, brightness: 0.03, fade: 0.14),
  ),
  cool(
    apiKey: 'cool',
    label: 'Cool Blue',
    description: 'Tone dingin untuk nuansa modern.',
    accentColor: Color(0xFF6BAED6),
    recipe: BoothFilterRecipe(red: 0.96, blue: 1.1, shiftRed: -3.0, shiftBlue: 8.0, brightness: 0.02),
  ),
  frost(
    apiKey: 'frost',
    label: 'Frost',
    description: 'Biru es yang bersih.',
    accentColor: Color(0xFF8FC7F0),
    recipe: BoothFilterRecipe(saturation: 1.05, contrast: 1.2, red: 0.92, blue: 1.15, shiftBlue: 8.0, brightness: 0.02),
    vignette: 0.25,
  ),
  dusk(
    apiKey: 'dusk',
    label: 'Dusk',
    description: 'Senja redup dan sendu.',
    accentColor: Color(0xFFB08FA8),
    recipe: BoothFilterRecipe(saturation: 0.9, contrast: 0.92, red: 1.03, green: 0.98, blue: 0.96, fade: 0.15),
    vignette: 0.2,
  ),
  film(
    apiKey: 'film',
    label: 'Film',
    description: 'Nuansa film analog.',
    accentColor: Color(0xFFC7A97A),
    recipe: BoothFilterRecipe(saturation: 0.88, contrast: 1.12, red: 1.03, green: 1.02, blue: 0.97, fade: 0.08),
    vignette: 0.2,
  ),
  vintage(
    apiKey: 'vintage',
    label: 'Vintage',
    description: 'Sedikit faded dengan nuansa retro.',
    accentColor: Color(0xFFC49A6C),
    recipe: BoothFilterRecipe(saturation: 0.8, red: 1.05, blue: 0.85, shiftRed: 6.0, fade: 0.12),
    vignette: 0.25,
  ),
  sepia(
    apiKey: 'sepia',
    label: 'Sepia Retro',
    description: 'Cokelat klasik tempo dulu.',
    accentColor: Color(0xFF9C7448),
    recipe: BoothFilterRecipe(saturation: 0.25, contrast: 1.05, red: 1.15, blue: 0.78, fade: 0.1),
    vignette: 0.4,
  ),
  cinema(
    apiKey: 'cinema',
    label: 'Cinema',
    description: 'Gelap sinematik.',
    accentColor: Color(0xFF3F6E7A),
    recipe: BoothFilterRecipe(saturation: 0.9, contrast: 1.2, red: 1.05, green: 0.98, blue: 1.04),
    vignette: 0.35,
  ),
  xpro(
    apiKey: 'xpro',
    label: 'Cross',
    description: 'Cross-process: kontras tinggi, warna aneh.',
    accentColor: Color(0xFF7ACB6B),
    recipe: BoothFilterRecipe(saturation: 1.15, contrast: 1.25, red: 1.05, blue: 0.88, shiftBlue: 14.0),
    vignette: 0.4,
  ),
  vivid(
    apiKey: 'vivid',
    label: 'Vivid',
    description: 'Kontras dan saturasi lebih kuat.',
    accentColor: Color(0xFF7D5CFF),
    recipe: BoothFilterRecipe(saturation: 1.4, contrast: 1.1),
  ),
  punch(
    apiKey: 'punch',
    label: 'Punch',
    description: 'Kontras keras, warna ngejreng.',
    accentColor: Color(0xFFFF5C5C),
    recipe: BoothFilterRecipe(saturation: 1.4, contrast: 1.3),
    vignette: 0.3,
  ),
  noir(
    apiKey: 'noir',
    label: 'Noir',
    description: 'Hitam putih tegas.',
    accentColor: Color(0xFF9AA0A6),
    recipe: BoothFilterRecipe(saturation: 0.0, contrast: 1.25),
    vignette: 0.35,
  ),
  moon(
    apiKey: 'moon',
    label: 'Moonlight',
    description: 'Hitam putih dingin yang lembut.',
    accentColor: Color(0xFFB6C4D6),
    recipe: BoothFilterRecipe(saturation: 0.0, contrast: 1.1, red: 0.95, blue: 1.08, brightness: 0.02),
    vignette: 0.2,
  ),
  monofade(
    apiKey: 'monofade',
    label: 'Mono Fade',
    description: 'Hitam putih matte.',
    accentColor: Color(0xFFB5B5B5),
    recipe: BoothFilterRecipe(saturation: 0.0, contrast: 0.9, brightness: 0.02, fade: 0.18),
  );

  const BoothFilter({
    required this.apiKey,
    required this.label,
    required this.description,
    required this.accentColor,
    this.recipe,
    this.vignette = 0,
  });

  /// Nilai untuk server; null = tanpa filter.
  final String? apiKey;
  final String label;
  final String description;
  final Color accentColor;
  final BoothFilterRecipe? recipe;

  /// Kekuatan vignette (gelap di pinggir foto), 0 = mati.
  final double vignette;

  static final Map<BoothFilter, List<double>?> _matrixCache =
      <BoothFilter, List<double>?>{};

  /// Color matrix 4x5 untuk `ColorFilter.matrix`, null bila tanpa filter.
  List<double>? get matrix =>
      _matrixCache.putIfAbsent(this, () => recipe?.toMatrix());
}

/// Resep satu filter. Urutan penerapan: saturasi -> kontras -> white balance
/// ([red]/[green]/[blue] + shift) -> kecerahan -> fade (matte).
class BoothFilterRecipe {
  const BoothFilterRecipe({
    this.saturation = 1,
    this.contrast = 1,
    this.brightness = 0,
    this.red = 1,
    this.green = 1,
    this.blue = 1,
    this.shiftRed = 0,
    this.shiftGreen = 0,
    this.shiftBlue = 0,
    this.fade = 0,
  });

  /// 0 = hitam putih, 1 = normal, >1 = lebih pekat.
  final double saturation;
  final double contrast;

  /// -1..1 (digeser ke 0..255 saat dihitung).
  final double brightness;

  /// Pengali per kanal (white balance).
  final double red;
  final double green;
  final double blue;

  /// Geser per kanal (skala 0..255).
  final double shiftRed;
  final double shiftGreen;
  final double shiftBlue;

  /// 0..1: mengangkat hitam & meredam putih (tampilan matte).
  final double fade;

  List<double> toMatrix() {
    List<double> m = _kIdentityMatrix;
    m = _thenMatrix(m, _saturationMatrix(saturation));
    m = _thenMatrix(m, _contrastMatrix(contrast));
    m = _thenMatrix(m, <double>[
      red, 0, 0, 0, shiftRed, //
      0, green, 0, 0, shiftGreen,
      0, 0, blue, 0, shiftBlue,
      0, 0, 0, 1, 0,
    ]);
    m = _thenMatrix(m, _offsetMatrix(brightness * 255));
    if (fade > 0) {
      m = _thenMatrix(m, _fadeMatrix(fade));
    }
    return m;
  }
}

const List<double> _kIdentityMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

/// Terapkan [first] lalu [second] (keduanya matrix 4x5 ala Flutter).
List<double> _thenMatrix(List<double> first, List<double> second) {
  final List<double> out = List<double>.filled(20, 0);
  for (int r = 0; r < 4; r++) {
    for (int c = 0; c < 5; c++) {
      double v = 0;
      for (int k = 0; k < 4; k++) {
        v += second[r * 5 + k] * first[k * 5 + c];
      }
      if (c == 4) {
        v += second[r * 5 + 4];
      }
      out[r * 5 + c] = v;
    }
  }
  return out;
}

List<double> _saturationMatrix(double s) {
  const double lr = 0.2126;
  const double lg = 0.7152;
  const double lb = 0.0722;
  final double i = 1 - s;
  return <double>[
    lr * i + s, lg * i, lb * i, 0, 0, //
    lr * i, lg * i + s, lb * i, 0, 0,
    lr * i, lg * i, lb * i + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

List<double> _contrastMatrix(double c) {
  final double t = 128 * (1 - c);
  return <double>[
    c, 0, 0, 0, t, //
    0, c, 0, 0, t,
    0, 0, c, 0, t,
    0, 0, 0, 1, 0,
  ];
}

List<double> _offsetMatrix(double o) => <double>[
      1, 0, 0, 0, o, //
      0, 1, 0, 0, o,
      0, 0, 1, 0, o,
      0, 0, 0, 1, 0,
    ];

List<double> _fadeMatrix(double a) {
  final double s = 1 - a;
  final double o = a * 255 * 0.85;
  return <double>[
    s, 0, 0, 0, o, //
    0, s, 0, 0, o,
    0, 0, s, 0, o,
    0, 0, 0, 1, 0,
  ];
}

/// Terapkan [filter] ke [child]: color matrix + vignette. Tidak mengubah
/// ukuran [child]. Dipakai di live preview, hasil foto, strip, dan kartu filter.
Widget applyBoothFilter(Widget child, BoothFilter filter) {
  final List<double>? m = filter.matrix;
  Widget out = m == null
      ? child
      : ColorFiltered(colorFilter: ColorFilter.matrix(m), child: child);
  if (filter.vignette > 0) {
    out = Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        out,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _VignettePainter(filter.vignette)),
          ),
        ),
      ],
    );
  }
  return out;
}

/// Vignette elips: sudut paling gelap, tengah tetap bersih.
class _VignettePainter extends CustomPainter {
  const _VignettePainter(this.strength);

  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.width / 2, size.height / 2);
    const Rect unit = Rect.fromLTRB(-1, -1, 1, 1);
    final Paint paint = Paint()
      ..shader = RadialGradient(
        radius: 0.7071,
        colors: <Color>[
          const Color(0x00000000),
          Color.fromRGBO(0, 0, 0, strength),
        ],
        stops: const <double>[0.55, 1.0],
      ).createShader(unit);
    canvas.drawRect(unit, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VignettePainter old) => old.strength != strength;
}

enum BoothAspectRatio {
  auto,
  ratio4x3,
  ratio16x9,
  square;

  String get label {
    switch (this) {
      case BoothAspectRatio.auto:
        return 'Auto (Detect from camera)';
      case BoothAspectRatio.ratio4x3:
        return '4:3';
      case BoothAspectRatio.ratio16x9:
        return '16:9';
      case BoothAspectRatio.square:
        return '1:1';
    }
  }

  double? get value {
    switch (this) {
      case BoothAspectRatio.auto:
        return null;
      case BoothAspectRatio.ratio4x3:
        return 4 / 3;
      case BoothAspectRatio.ratio16x9:
        return 16 / 9;
      case BoothAspectRatio.square:
        return 1;
    }
  }
}

enum BoothFlipMode {
  none,
  flipAll,
  livePreviewOnly;

  String get label {
    switch (this) {
      case BoothFlipMode.none:
        return 'Normal (No Flip)';
      case BoothFlipMode.flipAll:
        return 'Flip All';
      case BoothFlipMode.livePreviewOnly:
        return 'Live View Only';
    }
  }

  String get description {
    switch (this) {
      case BoothFlipMode.none:
        return 'No mirror effect.';
      case BoothFlipMode.flipAll:
        return 'Flips both live preview and final photos.';
      case BoothFlipMode.livePreviewOnly:
        return 'Flips live preview for selfie experience only.';
    }
  }

  bool get mirrorsPreview {
    switch (this) {
      case BoothFlipMode.none:
        return false;
      case BoothFlipMode.flipAll:
      case BoothFlipMode.livePreviewOnly:
        return true;
    }
  }
}

enum BoothCompressionProfile {
  none,
  medium,
  high;

  String get label {
    switch (this) {
      case BoothCompressionProfile.none:
        return 'No Compression';
      case BoothCompressionProfile.medium:
        return 'Medium Compression';
      case BoothCompressionProfile.high:
        return 'High Compression';
    }
  }

  String get description {
    switch (this) {
      case BoothCompressionProfile.none:
        return 'Keeps best quality with larger file size.';
      case BoothCompressionProfile.medium:
        return 'Balanced quality and file size.';
      case BoothCompressionProfile.high:
        return 'Smaller files with slightly reduced quality.';
    }
  }
}

enum BoothPrintMode {
  individualPrints,
  copyBased;

  String get label {
    switch (this) {
      case BoothPrintMode.individualPrints:
        return 'Individual Prints (Recommended)';
      case BoothPrintMode.copyBased:
        return 'Copy-based Printing';
    }
  }

  String get description {
    switch (this) {
      case BoothPrintMode.individualPrints:
        return 'Sends separate print commands for each copy.';
      case BoothPrintMode.copyBased:
        return 'Uses printer built-in copy mechanism.';
    }
  }
}

enum BoothScreenOrientation {
  landscape,
  portrait;

  String get label {
    switch (this) {
      case BoothScreenOrientation.landscape:
        return 'Landscape (Normal)';
      case BoothScreenOrientation.portrait:
        return 'Portrait';
    }
  }
}

enum BoothWhiteBalancePreset {
  auto,
  daylight,
  cloudy,
  tungsten,
  fluorescent,
  flash,
  custom,
  shade;

  String get label {
    switch (this) {
      case BoothWhiteBalancePreset.auto:
        return 'Auto';
      case BoothWhiteBalancePreset.daylight:
        return 'Daylight';
      case BoothWhiteBalancePreset.cloudy:
        return 'Cloudy';
      case BoothWhiteBalancePreset.tungsten:
        return 'Tungsten';
      case BoothWhiteBalancePreset.fluorescent:
        return 'Fluorescent';
      case BoothWhiteBalancePreset.flash:
        return 'Flash';
      case BoothWhiteBalancePreset.custom:
        return 'Custom';
      case BoothWhiteBalancePreset.shade:
        return 'Shade';
    }
  }

  Color get tintColor {
    switch (this) {
      case BoothWhiteBalancePreset.auto:
        return const Color(0x00000000);
      case BoothWhiteBalancePreset.daylight:
        return const Color(0x11FFD27A);
      case BoothWhiteBalancePreset.cloudy:
        return const Color(0x14FFD9A3);
      case BoothWhiteBalancePreset.tungsten:
        return const Color(0x180F7BFF);
      case BoothWhiteBalancePreset.fluorescent:
        return const Color(0x1400D9A6);
      case BoothWhiteBalancePreset.flash:
        return const Color(0x11FFF2C7);
      case BoothWhiteBalancePreset.custom:
        return const Color(0x12C67BFF);
      case BoothWhiteBalancePreset.shade:
        return const Color(0x18FFBA66);
    }
  }
}

enum BoothShutterSpeed {
  bulb,
  s30,
  s25,
  s20,
  s15,
  s13,
  s10,
  s8,
  s6,
  s5,
  s4,
  s3_2,
  s3,
  s2_5,
  s2,
  s1_6,
  s1_5,
  s1_3,
  s1,
  s0_8,
  s0_7,
  s0_6,
  s0_5,
  s0_4,
  s0_3,
  q1_4,
  q1_5,
  q1_6,
  q1_8,
  q1_10,
  q1_13,
  q1_15,
  q1_20,
  q1_25,
  q1_30,
  q1_40,
  q1_45,
  q1_50,
  q1_60,
  q1_80,
  q1_90,
  q1_100,
  q1_125,
  q1_160,
  q1_180,
  q1_200,
  q1_250,
  q1_320,
  q1_350,
  q1_400,
  q1_500,
  q1_640,
  q1_750,
  q1_800,
  q1_1000;

  String get label {
    return switch (this) {
      BoothShutterSpeed.bulb => 'Bulb',
      BoothShutterSpeed.s30 => '30"',
      BoothShutterSpeed.s25 => '25"',
      BoothShutterSpeed.s20 => '20"',
      BoothShutterSpeed.s15 => '15"',
      BoothShutterSpeed.s13 => '13"',
      BoothShutterSpeed.s10 => '10"',
      BoothShutterSpeed.s8 => '8"',
      BoothShutterSpeed.s6 => '6"',
      BoothShutterSpeed.s5 => '5"',
      BoothShutterSpeed.s4 => '4"',
      BoothShutterSpeed.s3_2 => '3.2"',
      BoothShutterSpeed.s3 => '3"',
      BoothShutterSpeed.s2_5 => '2.5"',
      BoothShutterSpeed.s2 => '2"',
      BoothShutterSpeed.s1_6 => '1.6"',
      BoothShutterSpeed.s1_5 => '1.5"',
      BoothShutterSpeed.s1_3 => '1.3"',
      BoothShutterSpeed.s1 => '1"',
      BoothShutterSpeed.s0_8 => '0.8"',
      BoothShutterSpeed.s0_7 => '0.7"',
      BoothShutterSpeed.s0_6 => '0.6"',
      BoothShutterSpeed.s0_5 => '0.5"',
      BoothShutterSpeed.s0_4 => '0.4"',
      BoothShutterSpeed.s0_3 => '0.3"',
      BoothShutterSpeed.q1_4 => '1/4',
      BoothShutterSpeed.q1_5 => '1/5',
      BoothShutterSpeed.q1_6 => '1/6',
      BoothShutterSpeed.q1_8 => '1/8',
      BoothShutterSpeed.q1_10 => '1/10',
      BoothShutterSpeed.q1_13 => '1/13',
      BoothShutterSpeed.q1_15 => '1/15',
      BoothShutterSpeed.q1_20 => '1/20',
      BoothShutterSpeed.q1_25 => '1/25',
      BoothShutterSpeed.q1_30 => '1/30',
      BoothShutterSpeed.q1_40 => '1/40',
      BoothShutterSpeed.q1_45 => '1/45',
      BoothShutterSpeed.q1_50 => '1/50',
      BoothShutterSpeed.q1_60 => '1/60',
      BoothShutterSpeed.q1_80 => '1/80',
      BoothShutterSpeed.q1_90 => '1/90',
      BoothShutterSpeed.q1_100 => '1/100',
      BoothShutterSpeed.q1_125 => '1/125',
      BoothShutterSpeed.q1_160 => '1/160',
      BoothShutterSpeed.q1_180 => '1/180',
      BoothShutterSpeed.q1_200 => '1/200',
      BoothShutterSpeed.q1_250 => '1/250',
      BoothShutterSpeed.q1_320 => '1/320',
      BoothShutterSpeed.q1_350 => '1/350',
      BoothShutterSpeed.q1_400 => '1/400',
      BoothShutterSpeed.q1_500 => '1/500',
      BoothShutterSpeed.q1_640 => '1/640',
      BoothShutterSpeed.q1_750 => '1/750',
      BoothShutterSpeed.q1_800 => '1/800',
      BoothShutterSpeed.q1_1000 => '1/1000',
    };
  }
}

enum BoothIsoSetting {
  auto,
  iso100,
  iso200,
  iso400,
  iso800,
  iso1600,
  iso3200,
  iso6400,
  iso12800,
  iso25600;

  String get label {
    return switch (this) {
      BoothIsoSetting.auto => 'Auto',
      BoothIsoSetting.iso100 => '100',
      BoothIsoSetting.iso200 => '200',
      BoothIsoSetting.iso400 => '400',
      BoothIsoSetting.iso800 => '800',
      BoothIsoSetting.iso1600 => '1600',
      BoothIsoSetting.iso3200 => '3200',
      BoothIsoSetting.iso6400 => '6400',
      BoothIsoSetting.iso12800 => '12800',
      BoothIsoSetting.iso25600 => '25600',
    };
  }
}

enum BoothApertureSetting {
  f1,
  f1_1,
  f1_2,
  f1_4,
  f1_6,
  f1_8,
  f2,
  f2_2,
  f2_5,
  f2_8,
  f3_2,
  f3_5,
  f4,
  f4_5,
  f5,
  f5_6,
  f6_3,
  f7_1,
  f8,
  f9,
  f10,
  f11,
  f13,
  f14,
  f16,
  f18,
  f20,
  f22,
  f25;

  String get label {
    return switch (this) {
      BoothApertureSetting.f1 => 'f/1',
      BoothApertureSetting.f1_1 => 'f/1.1',
      BoothApertureSetting.f1_2 => 'f/1.2',
      BoothApertureSetting.f1_4 => 'f/1.4',
      BoothApertureSetting.f1_6 => 'f/1.6',
      BoothApertureSetting.f1_8 => 'f/1.8',
      BoothApertureSetting.f2 => 'f/2.0',
      BoothApertureSetting.f2_2 => 'f/2.2',
      BoothApertureSetting.f2_5 => 'f/2.5',
      BoothApertureSetting.f2_8 => 'f/2.8',
      BoothApertureSetting.f3_2 => 'f/3.2',
      BoothApertureSetting.f3_5 => 'f/3.5',
      BoothApertureSetting.f4 => 'f/4.0',
      BoothApertureSetting.f4_5 => 'f/4.5',
      BoothApertureSetting.f5 => 'f/5.0',
      BoothApertureSetting.f5_6 => 'f/5.6',
      BoothApertureSetting.f6_3 => 'f/6.3',
      BoothApertureSetting.f7_1 => 'f/7.1',
      BoothApertureSetting.f8 => 'f/8.0',
      BoothApertureSetting.f9 => 'f/9',
      BoothApertureSetting.f10 => 'f/10',
      BoothApertureSetting.f11 => 'f/11',
      BoothApertureSetting.f13 => 'f/13',
      BoothApertureSetting.f14 => 'f/14',
      BoothApertureSetting.f16 => 'f/16',
      BoothApertureSetting.f18 => 'f/18',
      BoothApertureSetting.f20 => 'f/20',
      BoothApertureSetting.f22 => 'f/22',
      BoothApertureSetting.f25 => 'f/25',
    };
  }
}

/// Pengaturan sesi: selalu 8 kali jepret dengan jeda 10 detik antar foto.
/// Customer memilih foto terbaik dari 8 hasil jepretan untuk mengisi slot frame.
const int kBoothShotsPerSession = 8;
const int kBoothShotDelaySeconds = 10;

/// Bentuk susunan slot pada sebuah frame.
enum BoothFrameLayout {
  /// Strip tegak lurus (foto bertumpuk dari atas ke bawah).
  stripVertical,

  /// Strip mendatar (foto berjajar kiri ke kanan).
  stripHorizontal,

  /// Grid 2 kolom x N baris dengan caption di samping tiap foto (portrait).
  gridPortrait,

  /// Grid 2 baris x N kolom dengan caption di sisi kiri (landscape).
  gridLandscape,

  /// Template dari server (`GET /api/templates`): posisi tiap slot memakai
  /// persentase `x/y/w/h` pada kanvas, dan PNG frame ditumpuk di atasnya.
  /// Bentuk default-nya memanjang vertikal (strip tegak).
  template;

  /// Layout dengan orientasi berlawanan (strip tegak <-> mendatar, grid
  /// portrait <-> landscape). Jumlah slot tetap sama. Dipakai agar satu desain
  /// background bisa dipakai semua frame: susunan foto mengikuti bentuk area.
  BoothFrameLayout get transposed => switch (this) {
        BoothFrameLayout.stripVertical => BoothFrameLayout.stripHorizontal,
        BoothFrameLayout.stripHorizontal => BoothFrameLayout.stripVertical,
        BoothFrameLayout.gridPortrait => BoothFrameLayout.gridLandscape,
        BoothFrameLayout.gridLandscape => BoothFrameLayout.gridPortrait,
        BoothFrameLayout.template => BoothFrameLayout.template,
      };
}

/// Cara foto diisikan ke frame.
enum BoothPhotoMode {
  /// Setiap slot memakai foto yang berbeda.
  different,

  /// Foto yang sama dicetak dua kali (strip dicetak 2x, atau separuh grid
  /// diulang), jadi hanya butuh separuh jumlah foto unik.
  duplicate,
}

extension BoothPhotoModeLabel on BoothPhotoMode {
  String get label => this == BoothPhotoMode.different
      ? 'Foto Beda-beda'
      : 'Foto Double';

  String get hint => this == BoothPhotoMode.different
      ? 'Setiap slot berisi foto yang berbeda.'
      : 'Foto yang sama dicetak dua kali.';
}

/// Satu slot foto pada template server. Semua nilai dalam persen (0..100)
/// dari lebar/tinggi kanvas, sama seperti `layout_json.slots[]` di PHP.
class BoothSlotRect {
  const BoothSlotRect({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final String id;
  final String label;
  final double x;
  final double y;
  final double w;
  final double h;
}

/// Kanvas default template server bila `layout_json.width/height` kosong:
/// strip vertikal 1 : 3.
const double kTemplateDefaultWidth = 600;
const double kTemplateDefaultHeight = 1800;

class BoothFrameOption {
  const BoothFrameOption({
    required this.id,
    required this.name,
    required this.description,
    required this.borderColor,
    required this.gradient,
    this.slotCount = 4,
    this.layout = BoothFrameLayout.stripVertical,
    this.captions = const <String>[],
    this.remoteId,
    this.imageUrl,
    this.canvasWidth = kTemplateDefaultWidth,
    this.canvasHeight = kTemplateDefaultHeight,
    this.slots = const <BoothSlotRect>[],
    this.background,
  });

  /// Bangun frame dari template server ([PhotoFrameDto]).
  ///
  /// [hostBaseUrl] adalah host monolith tanpa `/api` (mis.
  /// `http://192.168.1.10:8000`), dipakai untuk menyusun URL gambar frame.
  factory BoothFrameOption.fromTemplate(
    PhotoFrameDto dto, {
    required String hostBaseUrl,
  }) {
    final Map<String, dynamic>? layout = dto.layoutJson;

    double number(Object? v, double fallback) {
      final double? parsed =
          v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
      return parsed == null || parsed <= 0 ? fallback : parsed;
    }

    final double width = number(layout?['width'], kTemplateDefaultWidth);
    final double height = number(layout?['height'], kTemplateDefaultHeight);

    // Slot lama (grid 0/1 dengan w=h=1) dikonversi seperti di editor PHP.
    final Object? rawSlots = layout?['slots'];
    final List<Map<String, dynamic>> rawList = rawSlots is List
        ? rawSlots.whereType<Map<String, dynamic>>().toList(growable: false)
        : const <Map<String, dynamic>>[];
    final bool legacyGrid = rawList.isNotEmpty &&
        rawList.every((Map<String, dynamic> s) =>
            number(s['w'], 0) <= 1 && number(s['h'], 0) <= 1);

    final List<BoothSlotRect> slots = <BoothSlotRect>[];
    for (int i = 0; i < rawList.length; i++) {
      final Map<String, dynamic> s = rawList[i];
      final double x = legacyGrid
          ? number(s['x'], 0) * 50 + 5
          : (s['x'] is num ? (s['x'] as num).toDouble() : 10.0);
      final double y = legacyGrid
          ? number(s['y'], 0) * 50 + 5
          : (s['y'] is num ? (s['y'] as num).toDouble() : 10.0);
      slots.add(BoothSlotRect(
        id: s['id']?.toString() ?? 'slot-$i',
        label: s['label']?.toString() ?? 'Foto ${i + 1}',
        x: x.clamp(0.0, 100.0).toDouble(),
        y: y.clamp(0.0, 100.0).toDouble(),
        w: (legacyGrid ? 40.0 : number(s['w'], 35)).clamp(1.0, 100.0).toDouble(),
        h: (legacyGrid ? 40.0 : number(s['h'], 35)).clamp(1.0, 100.0).toDouble(),
      ));
    }

    const List<Color> accents = <Color>[
      Color(0xFFD9CDB7),
      Color(0xFFC9B79C),
      Color(0xFFB6C2D9),
      Color(0xFFD8B08A),
    ];
    final Color accent = accents[dto.id % accents.length];

    return BoothFrameOption(
      id: 'api-${dto.id}',
      name: dto.name,
      description:
          'Template server, strip vertikal dengan ${slots.length} slot foto.',
      borderColor: accent,
      gradient: <Color>[accent.withValues(alpha: 0.2), const Color(0x11FFFFFF)],
      slotCount: slots.length,
      layout: BoothFrameLayout.template,
      captions: <String>[for (final BoothSlotRect s in slots) s.label],
      remoteId: dto.id,
      imageUrl: _resolveFrameUrl(dto, hostBaseUrl),
      canvasWidth: width,
      canvasHeight: height,
      slots: slots,
    );
  }

  final String id;
  final String name;
  final String description;
  final Color borderColor;
  final List<Color> gradient;

  /// Jumlah slot foto yang tercetak pada frame ini (3, 4, 6, atau 8).
  final int slotCount;

  final BoothFrameLayout layout;

  /// Caption per foto (opsional), mis. "The Main Character".
  final List<String> captions;

  // --- khusus template dari server ---
  /// ID `photo_frames.id` di monolith. Null = frame bawaan Flutter.
  final int? remoteId;

  /// URL PNG frame (overlay) di server.
  final String? imageUrl;

  /// Ukuran kanvas asli template (piksel), menentukan rasio lembar.
  final double canvasWidth;
  final double canvasHeight;

  /// Posisi tiap slot (persen) untuk layout [BoothFrameLayout.template].
  final List<BoothSlotRect> slots;

  /// Background lembar frame dari dashboard (`/api/frame-backgrounds`):
  /// gambar penuh (logo, tulisan, hiasan) + area tempat foto ditempatkan.
  /// Null = lembar putih biasa.
  final FrameBackgroundInfo? background;

  String? get backgroundUrl => background?.url;

  bool get hasBackground => (background?.url ?? '').isNotEmpty;

  /// Rasio lebar : tinggi SATU lembar bila memakai background.
  double get backgroundAspect {
    final double? a = background?.aspect;
    return (a != null && a > 0) ? a : 2 / 3;
  }

  /// Salinan frame ini dengan background baru (atau tanpa background).
  BoothFrameOption withBackground(FrameBackgroundInfo? info) {
    if (info == null && background == null) return this;
    return BoothFrameOption(
      id: id,
      name: name,
      description: description,
      borderColor: borderColor,
      gradient: gradient,
      slotCount: slotCount,
      layout: layout,
      captions: captions,
      remoteId: remoteId,
      imageUrl: imageUrl,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      slots: slots,
      background: info,
    );
  }

  /// Salinan frame ini dengan susunan [newLayout] (background tetap).
  BoothFrameOption withLayout(BoothFrameLayout newLayout) {
    if (newLayout == layout) return this;
    return BoothFrameOption(
      id: id,
      name: name,
      description: description,
      borderColor: borderColor,
      gradient: gradient,
      slotCount: slotCount,
      layout: newLayout,
      captions: captions,
      remoteId: remoteId,
      imageUrl: imageUrl,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      slots: slots,
      background: background,
    );
  }

  /// Frame ini berasal dari `/api/templates`.
  bool get isRemote => remoteId != null;

  bool get isTemplate => layout == BoothFrameLayout.template;

  /// Rasio lebar : tinggi kanvas template.
  double get canvasAspect => canvasWidth / canvasHeight;

  /// Rasio kartu pratinjau pada daftar pilihan frame.
  double get previewAspect {
    if (hasBackground) return backgroundAspect.clamp(0.25, 3.0).toDouble();
    if (isTemplate) return canvasAspect.clamp(0.25, 2.5).toDouble();
    return isLandscape ? 1.35 : 0.78;
  }

  /// Frame horizontal (strip mendatar).
  bool get isHorizontal => layout == BoothFrameLayout.stripHorizontal;

  bool get isGrid =>
      layout == BoothFrameLayout.gridPortrait ||
      layout == BoothFrameLayout.gridLandscape;

  /// Lembar bentuk mendatar (lebar > tinggi).
  bool get isLandscape =>
      layout == BoothFrameLayout.stripHorizontal ||
      layout == BoothFrameLayout.gridLandscape ||
      (isTemplate && canvasWidth > canvasHeight);

  /// Jumlah foto unik yang harus dipilih customer.
  /// Grid mode double: separuh slot mengulang separuh lainnya.
  /// Strip mode double: strip yang sama dicetak 2x (foto unik tetap sama).
  int uniqueSlotCount(BoothPhotoMode mode) =>
      isGrid && mode == BoothPhotoMode.duplicate ? slotCount ~/ 2 : slotCount;

  /// Berapa kali strip digandakan pada lembar cetak (hanya untuk strip).
  int stripCopies(BoothPhotoMode mode) =>
      !isGrid && mode == BoothPhotoMode.duplicate ? 2 : 1;

  /// Untuk tiap sel tercetak (urut baris demi baris), index slot unik
  /// yang mengisinya.
  List<int> cellSources(BoothPhotoMode mode) {
    final bool dup = mode == BoothPhotoMode.duplicate;
    switch (layout) {
      case BoothFrameLayout.gridPortrait:
        // 2 kolom: sel kiri & kanan dalam satu baris memakai foto yang sama.
        return List<int>.generate(slotCount, (int i) => dup ? i ~/ 2 : i);
      case BoothFrameLayout.gridLandscape:
        // Baris kedua mengulang baris pertama.
        final int cols = slotCount ~/ 2;
        return List<int>.generate(slotCount, (int i) => dup ? i % cols : i);
      case BoothFrameLayout.stripVertical:
      case BoothFrameLayout.stripHorizontal:
      case BoothFrameLayout.template:
        return List<int>.generate(slotCount, (int i) => i);
    }
  }

  String captionFor(int source) =>
      source >= 0 && source < captions.length ? captions[source] : '';
}

const List<BoothFrameOption> kFrameOptions = <BoothFrameOption>[
  BoothFrameOption(
    id: 'main-character',
    name: 'Main Character 3x2',
    description: 'Grid 3 baris x 2 kolom dengan caption di samping tiap foto (6 slot).',
    borderColor: Color(0xFFD9CDB7),
    gradient: <Color>[Color(0x33D9CDB7), Color(0x11FFFFFF)],
    slotCount: 6,
    layout: BoothFrameLayout.gridPortrait,
    captions: <String>[
      'The Main Character',
      'The Ride or Die',
      'The Trendsetter',
      'The Chaos',
      'The Savage',
      'The Realist',
    ],
  ),
  BoothFrameOption(
    id: 'main-character-4',
    name: 'Main Character 4x2',
    description: 'Grid 4 baris x 2 kolom dengan caption di samping tiap foto (8 slot).',
    borderColor: Color(0xFFD9CDB7),
    gradient: <Color>[Color(0x33D9CDB7), Color(0x11FFFFFF)],
    slotCount: 8,
    layout: BoothFrameLayout.gridPortrait,
    captions: <String>[
      'The Main Character',
      'The Ride or Die',
      'The Trendsetter',
      'The Chaos',
      'The Savage',
      'The Realist',
      'The Dreamer',
      'The Wildcard',
    ],
  ),
  BoothFrameOption(
    id: 'spotlight',
    name: 'Spotlight 3x2',
    description: 'Landscape 2 baris x 3 kolom dengan caption di sisi kiri (6 slot).',
    borderColor: Color(0xFFC9B79C),
    gradient: <Color>[Color(0x33C9B79C), Color(0x11FFFFFF)],
    slotCount: 6,
    layout: BoothFrameLayout.gridLandscape,
    captions: <String>[
      'The Spotlight',
      'The Photogenic',
      'The Best Dressed',
      'The One',
      'The Charismatic',
      'The Head Turner',
    ],
  ),
  BoothFrameOption(
    id: 'spotlight-4',
    name: 'Spotlight 4x2',
    description: 'Landscape 2 baris x 4 kolom dengan caption di sisi kiri (8 slot).',
    borderColor: Color(0xFFC9B79C),
    gradient: <Color>[Color(0x33C9B79C), Color(0x11FFFFFF)],
    slotCount: 8,
    layout: BoothFrameLayout.gridLandscape,
    captions: <String>[
      'The Spotlight',
      'The Photogenic',
      'The Best Dressed',
      'The One',
      'The Charismatic',
      'The Head Turner',
      'The Icon',
      'The Showstopper',
    ],
  ),
  BoothFrameOption(
    id: 'straight-3',
    name: 'Lurus 3 Foto',
    description: 'Strip tegak lurus berisi 3 foto.',
    borderColor: Color(0xFFD9CDB7),
    gradient: <Color>[Color(0x33D9CDB7), Color(0x11FFFFFF)],
    slotCount: 3,
  ),
  BoothFrameOption(
    id: 'straight-4',
    name: 'Lurus 4 Foto',
    description: 'Strip tegak lurus berisi 4 foto.',
    borderColor: Color(0xFFC9B79C),
    gradient: <Color>[Color(0x33C9B79C), Color(0x11FFFFFF)],
    slotCount: 4,
  ),
  BoothFrameOption(
    id: 'row-3',
    name: 'Sebaris 3 Foto',
    description: 'Satu baris mendatar berisi 3 foto.',
    borderColor: Color(0xFFD9CDB7),
    gradient: <Color>[Color(0x33D9CDB7), Color(0x11FFFFFF)],
    slotCount: 3,
    layout: BoothFrameLayout.stripHorizontal,
  ),
  BoothFrameOption(
    id: 'minimal-slate',
    name: 'Minimal Slate',
    description: 'Satu baris mendatar berisi 4 foto, gaya tipis modern.',
    borderColor: Color(0xFFB6C2D9),
    gradient: <Color>[Color(0x223D5877), Color(0x11000000)],
    slotCount: 4,
    layout: BoothFrameLayout.stripHorizontal,
  ),
];

/// Susun URL absolut PNG frame. Pakai `image_url` dari server bila ada,
/// kalau tidak, bentuk dari `file_path` (disk `public` -> `/storage/...`).
String? _resolveFrameUrl(PhotoFrameDto dto, String hostBaseUrl) {
  final RegExp trailingSlashes = RegExp(r'/+$');
  final RegExp leadingSlashes = RegExp(r'^/+');
  final String host = hostBaseUrl.replaceAll(trailingSlashes, '');

  final String? direct = dto.imageUrl;
  if (direct != null && direct.isNotEmpty) {
    if (direct.startsWith('http://') || direct.startsWith('https://')) {
      return direct;
    }
    final String rel = direct.replaceAll(leadingSlashes, '');
    return '$host/$rel';
  }

  final String? path = dto.filePath;
  if (path == null || path.isEmpty) return null;
  final String cleaned =
      path.replaceAll(leadingSlashes, '').replaceFirst('storage/', '');
  return '$host/storage/$cleaned';
}
