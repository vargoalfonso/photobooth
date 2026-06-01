import 'package:flutter/material.dart';

import 'pages/appearance_page.dart';
import 'pages/booth_page.dart';
import 'pages/crop_page.dart';
import 'pages/filters_page.dart';
import 'pages/frames_page.dart';
import 'pages/launcher_page.dart';
import 'pages/session_reprint_page.dart';
import 'pages/settings_page.dart';
import 'pages/simple_info_page.dart';
import 'pages/uploads_page.dart';
import 'state/photo_booth_config.dart';

class LuminashBoothApp extends StatefulWidget {
  const LuminashBoothApp({super.key});

  @override
  State<LuminashBoothApp> createState() => _LuminashBoothAppState();
}

class _LuminashBoothAppState extends State<LuminashBoothApp> {
  final PhotoBoothConfig _config = PhotoBoothConfig();

  Route<dynamic> _buildRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute<void>(
          builder: (_) => LauncherPage(config: _config),
          settings: settings,
        );
      case '/booth':
        return MaterialPageRoute<void>(
          builder: (_) => BoothPage(config: _config),
          settings: settings,
        );
      case '/settings':
        return MaterialPageRoute<void>(
          builder: (_) => SettingsPage(config: _config),
          settings: settings,
        );
      case '/appearance':
        return MaterialPageRoute<void>(
          builder: (_) => AppearancePage(config: _config),
          settings: settings,
        );
      case '/crop':
        return MaterialPageRoute<void>(
          builder: (_) => CropPage(config: _config),
          settings: settings,
        );
      case '/frames':
        return MaterialPageRoute<void>(
          builder: (_) => FramesPage(config: _config),
          settings: settings,
        );
      case '/filters':
        return MaterialPageRoute<void>(
          builder: (_) => FiltersPage(config: _config),
          settings: settings,
        );
      case '/session-reprint':
        return MaterialPageRoute<void>(
          builder: (_) => SessionReprintPage(config: _config),
          settings: settings,
        );
      case '/uploads':
        return MaterialPageRoute<void>(
          builder: (_) => UploadsPage(config: _config),
          settings: settings,
        );
      case '/wizard':
        return MaterialPageRoute<void>(
          builder: (_) => const SimpleInfoPage(
            title: 'Setup Wizard',
            description: 'Panduan step-by-step untuk branding, device, printer, dan layout booth.',
          ),
          settings: settings,
        );
      default:
        return MaterialPageRoute<void>(
          builder: (_) => LauncherPage(config: _config),
          settings: settings,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _config,
      builder: (context, _) {
        return MaterialApp(
          title: 'Luminash Booth',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF1E4A73),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFF1C24C),
              brightness: Brightness.dark,
              primary: const Color(0xFFF1C24C),
              secondary: const Color(0xFF12A05C),
              surface: const Color(0xFF254F78),
            ),
            snackBarTheme: const SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
            ),
            fontFamily: 'Roboto',
          ),
          onGenerateRoute: _buildRoute,
          initialRoute: '/',
        );
      },
    );
  }
}
