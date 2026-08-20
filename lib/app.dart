import 'package:flutter/material.dart';

import 'pages/api_settings_page.dart';
import 'pages/appearance_page.dart';
import 'pages/booth_page.dart';
import 'pages/canon_setup_page.dart';
import 'pages/crop_page.dart';
import 'pages/filters_page.dart';
import 'pages/frames_page.dart';
import 'pages/launcher_page.dart';
import 'pages/session_reprint_page.dart';
import 'pages/settings_page.dart';
import 'pages/setup_wizard_page.dart';
import 'pages/uploads_page.dart';
import 'services/canon_camera_service.dart';
import 'state/photo_booth_config.dart';
import 'theme/app_theme.dart';

class LuminashBoothApp extends StatefulWidget {
  const LuminashBoothApp({super.key});

  @override
  State<LuminashBoothApp> createState() => _LuminashBoothAppState();
}

class _LuminashBoothAppState extends State<LuminashBoothApp> {
  final PhotoBoothConfig _config = PhotoBoothConfig();
  final CanonCameraService _canon = CanonCameraService();

  @override
  void initState() {
    super.initState();
    // Auto connect ke Canon EOS R100 saat aplikasi dibuka (jika diaktifkan).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_config.useCanonCamera && _canon.autoConnectOnStart) {
        _canon.connect();
      }
    });
  }

  @override
  void dispose() {
    _canon.dispose();
    _config.dispose();
    super.dispose();
  }

  Route<dynamic> _buildRoute(RouteSettings settings) {
    Widget page;

    switch (settings.name) {
      case '/booth':
        page = BoothPage(config: _config, canon: _canon);
      case '/settings':
        page = SettingsPage(config: _config);
      case '/appearance':
        page = AppearancePage(config: _config);
      case '/crop':
        page = CropPage(config: _config);
      case '/frames':
        page = FramesPage(config: _config);
      case '/filters':
        page = FiltersPage(config: _config);
      case '/session-reprint':
        page = SessionReprintPage(config: _config);
      case '/uploads':
        page = UploadsPage(config: _config);
      case '/canon':
        page = CanonSetupPage(config: _config, canon: _canon);
      case '/api-settings':
        page = ApiSettingsPage(config: _config);
      case '/wizard':
        page = SetupWizardPage(config: _config, canon: _canon);
      case '/':
      default:
        page = LauncherPage(config: _config, canon: _canon);
    }

    return PageRouteBuilder<void>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_config, _canon]),
      builder: (BuildContext context, _) {
        return MaterialApp(
          title: 'Luminash Booth',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(),
          onGenerateRoute: _buildRoute,
          initialRoute: '/',
        );
      },
    );
  }
}
