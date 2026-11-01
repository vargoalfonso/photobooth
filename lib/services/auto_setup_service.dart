// Setup otomatis tanpa interaksi operator.
//
//  * Kamera: memantau USB (lihat CanonCameraService.startAutoDetect) dan
//    menyetel `config.useCanonCamera` sendiri: Canon bila terdeteksi, webcam
//    bila tidak ada Canon.
//  * API: sinkron ke server saat aplikasi start, mengulang dengan jeda
//    bertahap bila server belum terjangkau, lalu menyegarkan berkala.

import 'dart:async';

import '../state/photo_booth_config.dart';
import 'canon_camera_service.dart';
import 'photobooth_api_service.dart';

class AutoSetupService {
  AutoSetupService({required this.config, required this.canon});

  final PhotoBoothConfig config;
  final CanonCameraService canon;

  /// Jeda-jeda ini bisa diubah (mis. untuk pengujian).
  Duration refreshEvery = const Duration(minutes: 5);
  Duration deferWhileBooth = const Duration(seconds: 60);
  Duration canonOffDebounce = const Duration(seconds: 10);
  List<Duration> backoff = const <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(seconds: 60),
  ];

  Timer? _apiTimer;
  Timer? _canonOffTimer;
  bool _apiBusy = false;
  bool _resync = false;
  bool _started = false;
  bool _disposed = false;
  int _apiFailures = 0;
  String _apiKey = '';

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _apiKey = _currentApiKey();
    config.addListener(_onConfig);
    canon.addListener(_onCanon);

    // Kamera
    if (canon.autoDetectActive) {
      canon.startAutoDetect();
      _onCanon();
    } else if (config.useCanonCamera && canon.autoConnectOnStart) {
      // Mode manual (bridge / CCAPI): perilaku lama.
      if (!canon.enabled) {
        canon.setEnabled(true);
      }
      canon.connect();
    }

    // API
    unawaited(_syncApi());
  }

  void dispose() {
    _disposed = true;
    _apiTimer?.cancel();
    _canonOffTimer?.cancel();
    config.removeListener(_onConfig);
    canon.removeListener(_onCanon);
  }

  // ---------------------------------------------------------------- kamera
  /// Menyamakan `useCanonCamera` dengan keadaan kamera. Terhubung -> langsung
  /// pakai Canon. Tidak terhubung -> kembali ke webcam setelah jeda singkat,
  /// supaya putus sesaat (kabel goyang) tidak mengganti sumber kamera.
  void _onCanon() {
    if (_disposed || !canon.autoDetectActive) {
      return;
    }
    if (canon.state.isConnected) {
      _canonOffTimer?.cancel();
      _canonOffTimer = null;
      if (!config.useCanonCamera) {
        config.setUseCanonCamera(true);
      }
      return;
    }
    if (canon.autoInitialDone &&
        config.useCanonCamera &&
        _canonOffTimer == null) {
      _canonOffTimer = Timer(canonOffDebounce, () {
        _canonOffTimer = null;
        if (!_disposed &&
            canon.autoDetectActive &&
            !canon.state.isConnected &&
            config.useCanonCamera) {
          config.setUseCanonCamera(false);
        }
      });
    }
  }

  // ------------------------------------------------------------------- API
  String _currentApiKey() => '${config.apiBaseUrl}|${config.apiAuthToken}';

  /// Operator mengganti URL/token di halaman API -> sinkron ulang sendiri.
  void _onConfig() {
    final String key = _currentApiKey();
    if (key != _apiKey) {
      _apiKey = key;
      _apiFailures = 0;
      unawaited(_syncApi());
    }
  }

  Duration _nextBackoff() {
    final int i = (_apiFailures - 1).clamp(0, backoff.length - 1);
    return backoff[i];
  }

  void _schedule(Duration delay) {
    _apiTimer?.cancel();
    if (_disposed) {
      return;
    }
    _apiTimer = Timer(delay, () => unawaited(_syncApi()));
  }

  Future<void> _syncApi() async {
    if (_disposed) {
      return;
    }
    if (_apiBusy) {
      _resync = true;
      return;
    }
    // Jangan mengubah daftar frame di tengah sesi pelanggan.
    if (config.boothSessionActive && config.apiOnline == true) {
      _schedule(deferWhileBooth);
      return;
    }

    _apiBusy = true;
    _apiTimer?.cancel();
    try {
      final ApiSyncResult result = await PhotoboothApiService.syncAll(config);
      if (result.ok) {
        _apiFailures = 0;
        config.setApiStatus(
          online: true,
          message: result.message,
          warnings: result.warnings,
        );
        _schedule(refreshEvery);
      } else {
        _apiFailures++;
        config.setApiStatus(online: false, message: result.message);
        _schedule(_nextBackoff());
      }
    } catch (error) {
      _apiFailures++;
      config.setApiStatus(
        online: false,
        message: 'Sinkron gagal: $error',
      );
      _schedule(_nextBackoff());
    } finally {
      _apiBusy = false;
      if (_resync) {
        _resync = false;
        unawaited(_syncApi());
      }
    }
  }
}
