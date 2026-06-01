import 'package:flutter/material.dart';

import '../state/photo_booth_config.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({
    super.key,
    required this.config,
  });

  final PhotoBoothConfig config;

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  static const List<String> _tabs = <String>[
    'Color Settings',
    'Custom Background',
    'Custom Font',
    'Home Page',
    'Tutorial',
    'Custom Loading Media',
  ];

  static const List<String> _fontFamilies = <String>[
    'Josefin Sans (Default)',
    'Roboto',
    'Poppins',
    'Montserrat',
    'Open Sans',
  ];

  String _activeTab = 'Color Settings';

  @override
  Widget build(BuildContext context) {
    final ThemeData baseTheme = Theme.of(context);
    final ThemeData appearanceTheme = baseTheme.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0F2640),
      cardTheme: baseTheme.cardTheme.copyWith(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE9EDF3)),
        ),
      ),
      dividerColor: const Color(0xFFE8EBF0),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE3E7ED)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2D4A71)),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        helperStyle: const TextStyle(
          color: Color(0xFF98A1AE),
          fontSize: 12,
        ),
      ),
      textTheme: baseTheme.textTheme.apply(
        bodyColor: const Color(0xFF424A58),
        displayColor: const Color(0xFF424A58),
      ),
    );

    return Theme(
      data: appearanceTheme,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 980, maxHeight: 760),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 28,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              'Custom Appearance',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: const Color(0xFF324E71),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.close,
                                  size: 18, color: Color(0xFF8E97A5)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _tabs.map((String tab) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _AppearanceTab(
                                  label: tab,
                                  selected: _activeTab == tab,
                                  onTap: () {
                                    setState(() {
                                      _activeTab = tab;
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 18),
                        Expanded(
                          child: SingleChildScrollView(
                            child: _buildActiveTab(context),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF24456E),
                              foregroundColor: const Color(0xFFF1D065),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Appearance settings saved.')),
                              );
                            },
                            child: const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTab(BuildContext context) {
    switch (_activeTab) {
      case 'Color Settings':
        return _AppearanceColorSettings(
          config: widget.config,
          fontFamilies: _fontFamilies,
        );
      case 'Custom Background':
        return _AppearanceCustomBackgroundSettings(config: widget.config);
      case 'Custom Font':
        return _AppearanceCustomFontSettings(config: widget.config);
      case 'Home Page':
        return _AppearanceHomePageSettings(config: widget.config);
      case 'Tutorial':
        return _AppearanceTutorialSettings(config: widget.config);
      case 'Custom Loading Media':
        return _AppearanceCustomLoadingMediaSettings(config: widget.config);
      default:
        return _AppearancePlaceholder(label: _activeTab);
    }
  }
}

class _AppearanceColorSettings extends StatelessWidget {
  const _AppearanceColorSettings({
    required this.config,
    required this.fontFamilies,
  });

  final PhotoBoothConfig config;
  final List<String> fontFamilies;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            children: <Widget>[
              _AppearanceSectionCard(
                title: 'Background Colors',
                child: _AppearanceColorField(
                  label: 'Main Background Color',
                  value: config.appearanceMainBackgroundHex,
                  helperText: 'Main background color for the application',
                  onChanged: config.setAppearanceMainBackgroundHex,
                ),
              ),
              const SizedBox(height: 18),
              _AppearanceSectionCard(
                title: 'Text Colors',
                child: _AppearanceColorField(
                  label: 'Main Text Color',
                  value: config.appearanceMainTextHex,
                  helperText: 'Primary text color',
                  onChanged: config.setAppearanceMainTextHex,
                ),
              ),
              const SizedBox(height: 18),
              _AppearanceSectionCard(
                title: 'Primary Colors',
                child: Column(
                  children: <Widget>[
                    _AppearanceColorField(
                      label: 'Primary Color 1 (Container Background)',
                      value: config.appearancePrimary1BackgroundHex,
                      helperText: 'Primary accent color for containers',
                      onChanged: config.setAppearancePrimary1BackgroundHex,
                    ),
                    const SizedBox(height: 14),
                    _AppearanceColorField(
                      label: 'Primary Color 1 Text',
                      value: config.appearancePrimary1TextHex,
                      helperText: 'Text color for Primary Color 1 containers',
                      onChanged: config.setAppearancePrimary1TextHex,
                    ),
                    const SizedBox(height: 14),
                    _AppearanceColorField(
                      label: 'Primary Color 2 (Container Background)',
                      value: config.appearancePrimary2BackgroundHex,
                      helperText: 'Secondary accent color for hover states',
                      onChanged: config.setAppearancePrimary2BackgroundHex,
                    ),
                    const SizedBox(height: 14),
                    _AppearanceColorField(
                      label: 'Primary Color 2 Text',
                      value: config.appearancePrimary2TextHex,
                      helperText: 'Text color for Primary Color 2 containers',
                      onChanged: config.setAppearancePrimary2TextHex,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: <Widget>[
              _AppearanceSectionCard(
                title: 'Button Colors',
                child: Column(
                  children: <Widget>[
                    _AppearanceColorField(
                      label: 'Button 1 Background',
                      value: config.appearanceButton1BackgroundHex,
                      helperText: 'Primary button background color',
                      onChanged: config.setAppearanceButton1BackgroundHex,
                    ),
                    const SizedBox(height: 14),
                    _AppearanceColorField(
                      label: 'Button 1 Text',
                      value: config.appearanceButton1TextHex,
                      helperText: 'Primary button text color',
                      onChanged: config.setAppearanceButton1TextHex,
                    ),
                    const SizedBox(height: 14),
                    _AppearanceColorField(
                      label: 'Button 2 Background',
                      value: config.appearanceButton2BackgroundHex,
                      helperText: 'Secondary button background color',
                      onChanged: config.setAppearanceButton2BackgroundHex,
                    ),
                    const SizedBox(height: 14),
                    _AppearanceColorField(
                      label: 'Button 2 Text',
                      value: config.appearanceButton2TextHex,
                      helperText: 'Secondary button text color',
                      onChanged: config.setAppearanceButton2TextHex,
                    ),
                    const SizedBox(height: 14),
                    _AppearanceColorField(
                      label: 'Button 3 Background',
                      value: config.appearanceButton3BackgroundHex,
                      helperText: 'Tertiary button background color',
                      onChanged: config.setAppearanceButton3BackgroundHex,
                    ),
                    const SizedBox(height: 14),
                    _AppearanceColorField(
                      label: 'Button 3 Text',
                      value: config.appearanceButton3TextHex,
                      helperText: 'Tertiary button text color',
                      onChanged: config.setAppearanceButton3TextHex,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _AppearanceSectionCard(
                title: 'Typography',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Font Family',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: config.appearanceFontFamily,
                      items: fontFamilies
                          .map((String font) => DropdownMenuItem<String>(
                                value: font,
                                child: Text(font),
                              ))
                          .toList(),
                      onChanged: (String? value) {
                        if (value != null) {
                          config.setAppearanceFontFamily(value);
                        }
                      },
                      decoration: const InputDecoration(
                        helperText: 'Main font family for all text elements',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppearanceCustomBackgroundSettings extends StatelessWidget {
  const _AppearanceCustomBackgroundSettings({required this.config});

  final PhotoBoothConfig config;

  @override
  Widget build(BuildContext context) {
    return _AppearanceSectionCard(
      title: 'Custom Background Image',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Upload Background Image',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'File picker belum dihubungkan di build ini.')),
                  );
                },
                child: const Text('Choose File'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  config.customBackgroundPath ?? 'No file chosen',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD0A64B),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Upload a background image (JPG, PNG, GIF). Recommended size: 1920x1080 or higher.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF98A1AE),
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Background Preview',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 190,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E7ED)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CustomPaint(painter: _CheckerboardPainter()),
                Center(
                  child: Container(
                    width: 340,
                    height: 150,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFF0D4A84), Color(0xFFF39B2F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: const Color(0xFF2F5784), width: 4),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 16,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'PHOTOBOOTH',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Preview of your custom background',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF98A1AE),
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF707885),
                  foregroundColor: Colors.white,
                ),
                onPressed: config.customBackgroundPath == null
                    ? null
                    : () {
                        config.setCustomBackgroundPath(null);
                      },
                child: const Text('Remove Background'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF11A6CA),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Background preview refreshed.')),
                  );
                },
                child: const Text('Preview Background'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppearanceCustomFontSettings extends StatelessWidget {
  const _AppearanceCustomFontSettings({required this.config});

  final PhotoBoothConfig config;

  @override
  Widget build(BuildContext context) {
    return _AppearanceSectionCard(
      title: 'Custom Font Upload',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Upload Font File',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'File picker belum dihubungkan di build ini.')),
                  );
                },
                child: const Text('Choose File'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  config.customFontPath ?? 'No file chosen',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD0A64B),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Upload a font file (TTF, OTF, WOFF, WOFF2, EOT). This will replace the default theme font.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF98A1AE),
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Font Preview',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFD9DDE4),
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              children: <Widget>[
                Text(
                  'The quick brown fox jumps over the lazy dog',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFD7A92E),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  '1234567890',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFFD7A92E),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  '!@#\$% ^&*()',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFFD7A92E),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Preview of your custom font',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF98A1AE),
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF707885),
                  foregroundColor: Colors.white,
                ),
                onPressed: config.customFontPath == null
                    ? null
                    : () {
                        config.setCustomFontPath(null);
                      },
                child: const Text('Remove Font'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF11A6CA),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Font preview refreshed.')),
                  );
                },
                child: const Text('Preview Font'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppearanceHomePageSettings extends StatelessWidget {
  const _AppearanceHomePageSettings({required this.config});

  final PhotoBoothConfig config;

  @override
  Widget build(BuildContext context) {
    return _AppearanceSectionCard(
      title: 'Custom Home Page',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Upload Custom Home Page Image',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('File picker belum dihubungkan di build ini.'),
                    ),
                  );
                },
                child: const Text('Choose File'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  config.customHomePagePath ?? 'No file chosen',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD0A64B),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Upload a custom home page image or video (JPG, PNG, GIF, BMP, WEBP, MP4). This will replace the default home page design.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF98A1AE),
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Home Page Preview',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 340,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E7ED)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CustomPaint(painter: _CheckerboardPainter()),
                Center(
                  child: Container(
                    width: 330,
                    height: 330,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFF215A97), Color(0xFFF59A27)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      border: Border.all(
                        color: const Color(0xFF0F4E87),
                        width: 6,
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 18,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            'MYSTERY',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: const Color(0xFFFFC156),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.4,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: 150,
                            height: 120,
                            decoration: BoxDecoration(
                              color: const Color(0xFFAFD070),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: const Color(0xFF113C65), width: 4),
                            ),
                            child: const Icon(
                              Icons.photo_camera_front,
                              size: 54,
                              color: Color(0xFF113C65),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'PHOTOBOOTH',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: const Color(0xFFFFA53D),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Preview of your custom home page',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF98A1AE),
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF707885),
                  foregroundColor: Colors.white,
                ),
                onPressed: config.customHomePagePath == null
                    ? null
                    : () {
                        config.setCustomHomePagePath(null);
                      },
                child: const Text('Remove Home Page'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF11A6CA),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Home page preview refreshed.')),
                  );
                },
                child: const Text('Preview Home Page'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppearanceTutorialSettings extends StatelessWidget {
  const _AppearanceTutorialSettings({required this.config});

  final PhotoBoothConfig config;

  @override
  Widget build(BuildContext context) {
    return _AppearanceSectionCard(
      title: 'Photobooth Tutorial',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Upload Tutorial Image',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('File picker belum dihubungkan di build ini.'),
                    ),
                  );
                },
                child: const Text('Choose File'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  config.customTutorialPath ?? 'No file chosen',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD0A64B),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Upload a tutorial image that shows the photobooth procedure (JPG, PNG, GIF, BMP, WEBP).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF98A1AE),
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tutorial Preview',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              color: const Color(0xFFFCFCFD),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E7ED)),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'No tutorial image uploaded',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF9EA6B2),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Upload an image to see preview',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFB0B7C2),
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Preview of your tutorial image',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF98A1AE),
                ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF707885),
              foregroundColor: Colors.white,
            ),
            onPressed: config.customTutorialPath == null
                ? null
                : () {
                    config.setCustomTutorialPath(null);
                  },
            child: const Text('Remove Tutorial'),
          ),
        ],
      ),
    );
  }
}

class _AppearanceCustomLoadingMediaSettings extends StatelessWidget {
  const _AppearanceCustomLoadingMediaSettings({required this.config});

  final PhotoBoothConfig config;

  @override
  Widget build(BuildContext context) {
    return _AppearanceSectionCard(
      title: 'Custom Loading Media',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Upload a custom image or video to show during photo processing (instead of the default loading animation).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF98A1AE),
                ),
          ),
          const SizedBox(height: 14),
          Text(
            'Upload Loading Media (JPG, PNG, GIF, MP4)',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('File picker belum dihubungkan di build ini.'),
                    ),
                  );
                },
                child: const Text('Choose File'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  config.customLoadingMediaPath ?? 'No file chosen',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD0A64B),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Max 800px width. Images: 5MB max. Videos: 10MB max.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF98A1AE),
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Loading Media Preview',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 150,
            decoration: BoxDecoration(
              color: const Color(0xFFFCFCFD),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E7ED)),
            ),
            child: Center(
              child: Text(
                'No custom loading media (using default)',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFFC1C6CF),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF707885),
                  foregroundColor: Colors.white,
                ),
                onPressed: config.customLoadingMediaPath == null
                    ? null
                    : () {
                        config.setCustomLoadingMediaPath(null);
                      },
                child: const Text('Remove Loading Media'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E90FF),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Loading media uploaded.')),
                  );
                },
                child: const Text('Upload'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppearanceSectionCard extends StatelessWidget {
  const _AppearanceSectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _AppearanceColorField extends StatelessWidget {
  const _AppearanceColorField({
    required this.label,
    required this.value,
    required this.helperText,
    required this.onChanged,
  });

  final String label;
  final String value;
  final String helperText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            _ColorSwatch(hexValue: value),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                key: ValueKey<String>('$label-$value'),
                initialValue: value,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          helperText,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF98A1AE),
              ),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.hexValue});

  final String hexValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 14,
      decoration: BoxDecoration(
        color: _parseHex(hexValue),
        border: Border.all(color: const Color(0xFFAAB3BF)),
      ),
    );
  }

  Color _parseHex(String value) {
    final String hex = value.replaceAll('#', '').trim();
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return const Color(0xFFE1E1E1);
  }
}

class _AppearanceTab extends StatelessWidget {
  const _AppearanceTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF1D065) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? const Color(0xFF4C4C34)
                      : const Color(0xFF8A93A2),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}

class _AppearancePlaceholder extends StatelessWidget {
  const _AppearancePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 420,
      child: Center(
        child: Text(
          '$label belum diimplementasikan.',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF8A93A2),
              ),
        ),
      ),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double cell = 16;
    final Paint light = Paint()..color = const Color(0xFFF6F6F6);
    final Paint dark = Paint()..color = const Color(0xFFE7E7E7);

    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final bool isDark = ((x / cell).floor() + (y / cell).floor()).isEven;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cell, cell),
          isDark ? dark : light,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
