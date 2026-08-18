import 'package:flutter/material.dart';

enum BoothFilter {
  none,
  warm,
  cool,
  noir,
  vintage,
  vivid;

  String get label {
    switch (this) {
      case BoothFilter.none:
        return 'Natural';
      case BoothFilter.warm:
        return 'Warm Glow';
      case BoothFilter.cool:
        return 'Cool Blue';
      case BoothFilter.noir:
        return 'Noir';
      case BoothFilter.vintage:
        return 'Vintage';
      case BoothFilter.vivid:
        return 'Vivid';
    }
  }

  String get description {
    switch (this) {
      case BoothFilter.none:
        return 'Warna natural tanpa filter.';
      case BoothFilter.warm:
        return 'Tone hangat untuk skin tone lembut.';
      case BoothFilter.cool:
        return 'Tone dingin untuk nuansa modern.';
      case BoothFilter.noir:
        return 'Hitam putih tegas.';
      case BoothFilter.vintage:
        return 'Sedikit faded dengan nuansa retro.';
      case BoothFilter.vivid:
        return 'Kontras dan saturasi lebih kuat.';
    }
  }

  Color get accentColor {
    switch (this) {
      case BoothFilter.none:
        return const Color(0xFFF7D98A);
      case BoothFilter.warm:
        return const Color(0xFFE58F65);
      case BoothFilter.cool:
        return const Color(0xFF6BAED6);
      case BoothFilter.noir:
        return const Color(0xFF9AA0A6);
      case BoothFilter.vintage:
        return const Color(0xFFC49A6C);
      case BoothFilter.vivid:
        return const Color(0xFF7D5CFF);
    }
  }

  List<double>? get matrix {
    switch (this) {
      case BoothFilter.none:
        return null;
      case BoothFilter.warm:
        return const <double>[
          1.15, 0.0, 0.0, 0.0, 8.0,
          0.0, 1.02, 0.0, 0.0, 2.0,
          0.0, 0.0, 0.9, 0.0, -8.0,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ];
      case BoothFilter.cool:
        return const <double>[
          0.92, 0.0, 0.0, 0.0, -6.0,
          0.0, 1.0, 0.0, 0.0, 0.0,
          0.0, 0.0, 1.12, 0.0, 10.0,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ];
      case BoothFilter.noir:
        return const <double>[
          0.2126, 0.7152, 0.0722, 0.0, 0.0,
          0.2126, 0.7152, 0.0722, 0.0, 0.0,
          0.2126, 0.7152, 0.0722, 0.0, 0.0,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ];
      case BoothFilter.vintage:
        return const <double>[
          0.9, 0.1, 0.0, 0.0, 12.0,
          0.0, 0.82, 0.1, 0.0, 6.0,
          0.0, 0.0, 0.72, 0.0, -4.0,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ];
      case BoothFilter.vivid:
        return const <double>[
          1.25, 0.0, 0.0, 0.0, 0.0,
          0.0, 1.15, 0.0, 0.0, 0.0,
          0.0, 0.0, 1.18, 0.0, 0.0,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ];
    }
  }
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

class BoothFrameOption {
  const BoothFrameOption({
    required this.id,
    required this.name,
    required this.description,
    required this.borderColor,
    required this.gradient,
    this.slotCount = 4,
  });

  final String id;
  final String name;
  final String description;
  final Color borderColor;
  final List<Color> gradient;

  /// Jumlah slot foto pada frame ini. Saat ini hanya 3 atau 4.
  final int slotCount;

  /// Frame horizontal (strip mendatar). Selain ini dianggap vertikal.
  bool get isHorizontal => id == 'minimal-slate';
}

const List<BoothFrameOption> kFrameOptions = <BoothFrameOption>[
  BoothFrameOption(
    id: 'classic-gold',
    name: 'Classic Gold',
    description: 'Border emas elegan seperti brand booth premium.',
    borderColor: Color(0xFFF1C24C),
    gradient: <Color>[Color(0x66F1C24C), Color(0x11FFFFFF)],
    slotCount: 4,
  ),
  BoothFrameOption(
    id: 'neon-night',
    name: 'Neon Night',
    description: 'Aksen neon untuk event malam dan konser.',
    borderColor: Color(0xFF44E0FF),
    gradient: <Color>[Color(0x3344E0FF), Color(0x117D5CFF)],
    slotCount: 4,
  ),
  BoothFrameOption(
    id: 'rose-party',
    name: 'Rose Party',
    description: 'Nuansa soft pink untuk wedding dan bridal booth.',
    borderColor: Color(0xFFFF8FB1),
    gradient: <Color>[Color(0x44FF8FB1), Color(0x11FFF3F7)],
    slotCount: 3,
  ),
  BoothFrameOption(
    id: 'minimal-slate',
    name: 'Minimal Slate',
    description: 'Frame tipis modern untuk corporate activation.',
    borderColor: Color(0xFFB6C2D9),
    gradient: <Color>[Color(0x223D5877), Color(0x11000000)],
    slotCount: 3,
  ),
];
