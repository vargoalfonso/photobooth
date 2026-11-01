import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'edsdk_types.dart';
import 'edsdk_native_stub.dart' if (dart.library.ffi) 'edsdk_native.dart';

/// Cara aplikasi terhubung ke Canon EOS R100.
enum CanonConnectionMode {
  /// USB langsung lewat Canon EDSDK (EDSDK.dll dimuat di dalam aplikasi lewat
  /// dart:ffi). Tidak butuh bridge/Python: colok kabel USB lalu Connect.
  /// Hanya Windows.
  edsdkDirect,

  /// Canon Camera Control API (CCAPI) lewat Wi-Fi.
  /// Kamera dan PC/tablet harus berada di jaringan yang sama.
  ccapiWifi,

  /// Bridge lokal di PC booth (gPhoto2 / EDSDK / digiCamControl HTTP helper)
  /// yang terhubung ke kamera lewat kabel USB. Paling stabil untuk booth mall.
  usbTetherBridge;

  String get label {
    switch (this) {
      case CanonConnectionMode.edsdkDirect:
        return 'USB Langsung (Canon EDSDK)';
      case CanonConnectionMode.ccapiWifi:
        return 'Wi-Fi (Canon CCAPI)';
      case CanonConnectionMode.usbTetherBridge:
        return 'USB Tether Bridge (gPhoto2 / EDSDK)';
    }
  }

  String get description {
    switch (this) {
      case CanonConnectionMode.edsdkDirect:
        return 'Kamera dicolok USB ke PC booth dan dikontrol langsung oleh '
            'aplikasi lewat EDSDK.dll. Tanpa Python/bridge. '
            'Tutup EOS Webcam Utility / EOS Utility sebelum connect.';
      case CanonConnectionMode.ccapiWifi:
        return 'Kamera aktifkan CCAPI, lalu sambungkan ke Wi-Fi booth. '
            'Tidak butuh kabel, tapi wajib sinyal stabil.';
      case CanonConnectionMode.usbTetherBridge:
        return 'Kamera dicolok USB ke PC booth dan dikontrol oleh helper '
            'service lokal. Paling stabil untuk operasional harian.';
    }
  }

  /// True bila mode ini memakai alamat host:port (HTTP).
  bool get usesNetwork => this != CanonConnectionMode.edsdkDirect;

  int get defaultPort {
    switch (this) {
      case CanonConnectionMode.edsdkDirect:
        return 0;
      case CanonConnectionMode.ccapiWifi:
        return 8080;
      case CanonConnectionMode.usbTetherBridge:
        return 5513;
    }
  }
}

/// Status koneksi kamera DSLR/mirrorless.
enum CanonConnectionState {
  disconnected,
  connecting,
  connected,
  error;

  bool get isConnected => this == CanonConnectionState.connected;
}

/// Ringkasan informasi kamera yang sedang terhubung.
class CanonDeviceInfo {
  const CanonDeviceInfo({
    required this.model,
    required this.serialNumber,
    required this.firmware,
    required this.lens,
    required this.batteryLevel,
    required this.storageRemaining,
  });

  final String model;
  final String serialNumber;
  final String firmware;
  final String lens;
  final String batteryLevel;
  final String storageRemaining;

  static const CanonDeviceInfo unknown = CanonDeviceInfo(
    model: 'Unknown',
    serialNumber: '-',
    firmware: '-',
    lens: '-',
    batteryLevel: '-',
    storageRemaining: '-',
  );
}

/// Hasil satu kali jepret.
class CanonCaptureResult {
  const CanonCaptureResult({
    required this.success,
    this.filePath,
    this.bytes,
    this.message,
  });

  final bool success;
  final String? filePath;
  final Uint8List? bytes;
  final String? message;
}

/// Service tunggal untuk mengontrol Canon EOS R100.
///
/// Semua request memakai `HttpClient` dari `dart:io` sehingga tidak butuh
/// dependency tambahan di `pubspec.yaml`.
class CanonCameraService extends ChangeNotifier {
  CanonCameraService();

  /// `dart:io` HttpClient tidak tersedia di Flutter Web, jadi client hanya
  /// dibuat saat benar-benar dipakai di platform desktop/mobile.
  HttpClient? _clientOrNull;

  HttpClient get _client {
    final HttpClient? existing = _clientOrNull;
    if (existing != null) {
      return existing;
    }
    final HttpClient created = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..idleTimeout = const Duration(seconds: 10);
    _clientOrNull = created;
    return created;
  }

  /// Kontrol kamera Canon hanya bisa dijalankan di Windows/macOS/Linux/Android/iOS.
  /// Di browser (Flutter Web) koneksi lokal ke kamera diblokir oleh sandbox
  /// dan CORS, jadi aplikasi otomatis memakai kamera perangkat.
  bool get isPlatformSupported => !kIsWeb;

  static const String _webUnsupportedMessage =
      'Mode web tidak mendukung kontrol Canon. Jalankan booth di Windows '
      '(flutter run -d windows) atau Android untuk memakai lensa Canon.';

  CanonConnectionMode _mode = _defaultMode();

  /// Windows memakai EDSDK langsung; platform lain tetap lewat bridge HTTP.
  static CanonConnectionMode _defaultMode() {
    if (!kIsWeb && Platform.isWindows) {
      return CanonConnectionMode.edsdkDirect;
    }
    return CanonConnectionMode.usbTetherBridge;
  }

  /// Hanya untuk pengujian otomatis (EDSDK palsu di Linux/macOS).
  @visibleForTesting
  static bool debugAllowNonWindowsEdsdk = false;

  EdsdkNative? _edsdk;
  String _sdkDllPath = '';
  int _frameErrors = 0;

  // ------------------------------------------------ deteksi otomatis (USB)
  /// Selang polling deteksi colok/cabut kamera. Boleh diubah untuk pengujian.
  Duration autoDetectInterval = const Duration(seconds: 3);

  bool _autoDetect = true;
  Timer? _autoTimer;
  bool _autoBusy = false;
  bool _autoInitialDone = false;

  /// Dijeda setelah operator memutus/mematikan Canon secara manual, supaya
  /// deteksi otomatis tidak langsung menyambungkan lagi. Dilepas oleh
  /// connect() / setEnabled(true).
  bool _autoPaused = false;
  DateTime _nextAutoAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Live view diminta oleh halaman booth. Dipakai untuk memulihkan live view
  /// otomatis setelah kamera tersambung ulang (kabel dicolok lagi).
  bool _liveViewWanted = false;
  int _lastFps = 15;
  String _host = '127.0.0.1';
  int _port = 5513;
  bool _enabled = false;
  bool _autoConnectOnStart = true;
  bool _saveToCameraCard = true;
  bool _downloadAfterCapture = true;
  String _downloadDirectory = '';

  CanonConnectionState _state = CanonConnectionState.disconnected;
  String _statusMessage = 'Belum terhubung ke kamera.';
  CanonDeviceInfo _deviceInfo = CanonDeviceInfo.unknown;
  Uint8List? _liveViewFrame;
  Timer? _liveViewTimer;
  bool _liveViewRunning = false;
  bool _isCapturing = false;
  bool _fetchingFrame = false;
  final List<String> _log = <String>[];

  // ---------------------------------------------------------------- getters
  CanonConnectionMode get mode => _mode;
  String get host => _host;
  int get port => _port;
  bool get enabled => _enabled;
  bool get autoConnectOnStart => _autoConnectOnStart;
  bool get saveToCameraCard => _saveToCameraCard;
  bool get downloadAfterCapture => _downloadAfterCapture;
  String get downloadDirectory => _downloadDirectory;
  String get sdkDllPath => _sdkDllPath;

  /// Deteksi kamera otomatis lewat USB (tanpa host/port, tanpa klik).
  bool get autoDetect => _autoDetect;

  /// Deteksi otomatis benar-benar berlaku (hanya mode USB Langsung).
  bool get autoDetectActive =>
      _autoDetect && _mode == CanonConnectionMode.edsdkDirect;

  /// True bila deteksi otomatis aktif tetapi EDSDK.dll belum ditemukan, jadi
  /// operator perlu memilih file-nya (satu kali).
  bool get needsSdkDll =>
      autoDetectActive && !kIsWeb && EdsdkNative.locateDll(_sdkDllPath) == null;

  /// True setelah satu putaran deteksi pertama selesai (terhubung, atau pasti
  /// tidak ada kamera/DLL). Dipakai halaman booth agar tidak salah memilih
  /// webcam saat deteksi awal masih berjalan.
  bool get autoInitialDone => _autoInitialDone;
  CanonConnectionState get state => _state;
  String get statusMessage => _statusMessage;
  CanonDeviceInfo get deviceInfo => _deviceInfo;
  Uint8List? get liveViewFrame => _liveViewFrame;
  bool get liveViewRunning => _liveViewRunning;
  bool get isCapturing => _isCapturing;
  List<String> get log => List<String>.unmodifiable(_log);

  bool get isReady => _enabled && _state.isConnected;

  String get baseUrl {
    switch (_mode) {
      case CanonConnectionMode.edsdkDirect:
        return 'edsdk://usb';
      case CanonConnectionMode.ccapiWifi:
        return 'http://$_host:$_port/ccapi';
      case CanonConnectionMode.usbTetherBridge:
        return 'http://$_host:$_port/api';
    }
  }

  // ---------------------------------------------------------------- setters
  void setEnabled(bool value) {
    _autoPaused = !value;
    if (_enabled == value) {
      return;
    }
    _enabled = value;
    if (!value) {
      stopLiveView();
      _state = CanonConnectionState.disconnected;
      _statusMessage = 'Canon dinonaktifkan, memakai kamera perangkat.';
    }
    _persist();
    notifyListeners();
  }

  void setMode(CanonConnectionMode value) {
    if (_mode == value) {
      return;
    }
    _mode = value;
    _port = value.defaultPort;
    _state = CanonConnectionState.disconnected;
    _statusMessage = 'Mode koneksi diubah ke ${value.label}.';
    _persist();
    notifyListeners();
  }

  void setHost(String value) {
    _host = value.trim();
    _persist();
    notifyListeners();
  }

  void setPort(int value) {
    _port = value;
    _persist();
    notifyListeners();
  }

  void setAutoConnectOnStart(bool value) {
    _autoConnectOnStart = value;
    _persist();
    notifyListeners();
  }

  void setSaveToCameraCard(bool value) {
    _saveToCameraCard = value;
    _persist();
    notifyListeners();
  }

  void setDownloadAfterCapture(bool value) {
    _downloadAfterCapture = value;
    _persist();
    notifyListeners();
  }

  void setAutoDetect(bool value) {
    if (_autoDetect == value) {
      return;
    }
    _autoDetect = value;
    if (value) {
      startAutoDetect();
    } else {
      _autoTimer?.cancel();
      _autoTimer = null;
    }
    _persist();
    notifyListeners();
  }

  void setSdkDllPath(String value) {
    _sdkDllPath = value.trim();
    _persist();
    notifyListeners();
  }

  void setDownloadDirectory(String value) {
    _downloadDirectory = value;
    _persist();
    notifyListeners();
  }

  // --------------------------------------------------- deteksi otomatis
  /// Mulai memantau kamera Canon di USB: otomatis terhubung saat kamera
  /// dicolok/dinyalakan, dan tersambung ulang bila terputus. Aman dipanggil
  /// berulang.
  void startAutoDetect() {
    if (!_autoDetect || _autoTimer != null) {
      return;
    }
    _autoTimer = Timer.periodic(autoDetectInterval, (_) => _autoTick());
    unawaited(_autoTick());
  }

  void stopAutoDetect() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  /// Menunggu deteksi awal selesai (maks [timeout]). Langsung kembali bila
  /// deteksi otomatis tidak berlaku.
  Future<void> waitUntilSettled({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!autoDetectActive) {
      return;
    }
    final DateTime end = DateTime.now().add(timeout);
    while ((!_autoInitialDone ||
            _state == CanonConnectionState.connecting) &&
        DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void _setAutoStatus(CanonConnectionState state, String message) {
    if (_state == state && _statusMessage == message) {
      return;
    }
    _state = state;
    _statusMessage = message;
    notifyListeners();
  }

  Future<void> _autoTick() async {
    if (!_autoDetect ||
        _autoPaused ||
        _autoBusy ||
        _isCapturing ||
        _mode != CanonConnectionMode.edsdkDirect) {
      return;
    }
    if (kIsWeb || !(Platform.isWindows || debugAllowNonWindowsEdsdk)) {
      _autoInitialDone = true;
      return;
    }
    if (DateTime.now().isBefore(_nextAutoAttempt)) {
      return;
    }

    _autoBusy = true;
    try {
      final EdsdkNative sdk = _edsdk ??= EdsdkNative();
      if (!sdk.isLoaded) {
        final String? dll = EdsdkNative.locateDll(_sdkDllPath);
        if (dll == null) {
          _setAutoStatus(
            CanonConnectionState.error,
            'EDSDK.dll tidak ditemukan. Letakkan folder EDSDK di samping '
            'aplikasi (atau pilih manual di Canon Setup).',
          );
          _nextAutoAttempt = DateTime.now().add(const Duration(seconds: 30));
          return;
        }
        _addLog('Memuat $dll');
        sdk.load(dll);
      }

      final int count = sdk.cameraCount();

      if (_state.isConnected) {
        if (count == 0) {
          _handleCameraLost();
        }
        return;
      }

      if (count == 0) {
        _setAutoStatus(
          CanonConnectionState.disconnected,
          'Menunggu kamera Canon... colok kabel USB dan nyalakan kamera.',
        );
        return;
      }

      final bool ok = await connect();
      if (ok) {
        if (_liveViewWanted) {
          await startLiveView(fps: _lastFps);
        }
      } else {
        _nextAutoAttempt = DateTime.now().add(const Duration(seconds: 8));
      }
    } catch (error) {
      _setAutoStatus(CanonConnectionState.error, _friendlyError(error));
      _nextAutoAttempt = DateTime.now().add(const Duration(seconds: 10));
    } finally {
      _autoBusy = false;
      _autoInitialDone = true;
    }
  }

  void _handleCameraLost() {
    _addLog('Kamera Canon terputus (tidak lagi terlihat di USB)');
    stopLiveView(keepWanted: true);
    _edsdk?.closeCamera();
    _state = CanonConnectionState.disconnected;
    _statusMessage = 'Kamera Canon terputus. Mencari ulang otomatis...';
    notifyListeners();
  }

  // ------------------------------------------------------------ persistence
  static const String _kPrefix = 'canon.';

  /// Muat pengaturan Canon yang tersimpan. Panggil sekali saat aplikasi start,
  /// sebelum auto-connect.
  Future<void> loadPersisted() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String? modeName = p.getString('${_kPrefix}mode');
      if (modeName != null) {
        for (final CanonConnectionMode m in CanonConnectionMode.values) {
          if (m.name == modeName) {
            _mode = m;
          }
        }
      }
      _host = p.getString('${_kPrefix}host') ?? _host;
      _port = p.getInt('${_kPrefix}port') ?? _mode.defaultPort;
      _enabled = p.getBool('${_kPrefix}enabled') ?? _enabled;
      _autoConnectOnStart =
          p.getBool('${_kPrefix}autoConnect') ?? _autoConnectOnStart;
      _saveToCameraCard = p.getBool('${_kPrefix}saveToCard') ?? _saveToCameraCard;
      _downloadAfterCapture =
          p.getBool('${_kPrefix}download') ?? _downloadAfterCapture;
      _downloadDirectory =
          p.getString('${_kPrefix}downloadDir') ?? _downloadDirectory;
      _sdkDllPath = p.getString('${_kPrefix}sdkDll') ?? _sdkDllPath;
      _autoDetect = p.getBool('${_kPrefix}autoDetect') ?? _autoDetect;
      notifyListeners();
    } catch (error) {
      _addLog('Gagal memuat pengaturan Canon: $error');
    }
  }

  void _persist() {
    unawaited(() async {
      try {
        final SharedPreferences p = await SharedPreferences.getInstance();
        await p.setString('${_kPrefix}mode', _mode.name);
        await p.setString('${_kPrefix}host', _host);
        await p.setInt('${_kPrefix}port', _port);
        await p.setBool('${_kPrefix}enabled', _enabled);
        await p.setBool('${_kPrefix}autoConnect', _autoConnectOnStart);
        await p.setBool('${_kPrefix}saveToCard', _saveToCameraCard);
        await p.setBool('${_kPrefix}download', _downloadAfterCapture);
        await p.setString('${_kPrefix}downloadDir', _downloadDirectory);
        await p.setString('${_kPrefix}sdkDll', _sdkDllPath);
        await p.setBool('${_kPrefix}autoDetect', _autoDetect);
      } catch (_) {
        // gagal simpan tidak boleh mengganggu operasional booth
      }
    }());
  }

  // ------------------------------------------------------------------ utils
  void _addLog(String message) {
    final String stamp = DateTime.now().toIso8601String().substring(11, 19);
    _log.insert(0, '[$stamp] $message');
    if (_log.length > 60) {
      _log.removeRange(60, _log.length);
    }
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> _getJson(String path) async {
    final HttpClientRequest request = await _client.getUrl(_uri(path));
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode}: $body');
    }
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final Object? decoded = jsonDecode(body);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'value': decoded};
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, [
    Map<String, dynamic>? payload,
  ]) async {
    final HttpClientRequest request =
        await _client.openUrl(method, _uri(path));
    request.headers.contentType = ContentType.json;
    if (payload != null) {
      request.write(jsonEncode(payload));
    }
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode}: $body');
    }
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final Object? decoded = jsonDecode(body);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'value': decoded};
  }

  Future<Uint8List> _getBytes(String path) async {
    final HttpClientRequest request = await _client.getUrl(_uri(path));
    final HttpClientResponse response = await request.close();
    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final List<int> bytes =
        await response.fold<List<int>>(<int>[], (List<int> acc, List<int> c) {
      acc.addAll(c);
      return acc;
    });
    return Uint8List.fromList(bytes);
  }

  String _pathFor(_CanonEndpoint endpoint) {
    final bool ccapi = _mode == CanonConnectionMode.ccapiWifi;
    switch (endpoint) {
      case _CanonEndpoint.deviceInformation:
        return ccapi ? '/ver100/deviceinformation' : '/camera/info';
      case _CanonEndpoint.battery:
        return ccapi ? '/ver100/devicestatus/battery' : '/camera/battery';
      case _CanonEndpoint.storage:
        return ccapi ? '/ver100/devicestatus/storage' : '/camera/storage';
      case _CanonEndpoint.lens:
        return ccapi ? '/ver100/devicestatus/lens' : '/camera/lens';
      case _CanonEndpoint.liveViewStart:
        return ccapi ? '/ver100/shooting/liveview' : '/liveview/start';
      case _CanonEndpoint.liveViewFrame:
        return ccapi ? '/ver100/shooting/liveview/flip' : '/liveview/frame';
      case _CanonEndpoint.liveViewStop:
        return ccapi ? '/ver100/shooting/liveview' : '/liveview/stop';
      case _CanonEndpoint.shutter:
        return ccapi
            ? '/ver100/shooting/control/shutterbutton'
            : '/capture';
      case _CanonEndpoint.autofocus:
        return ccapi ? '/ver100/shooting/control/af' : '/autofocus';
      case _CanonEndpoint.iso:
        return ccapi ? '/ver100/shooting/settings/iso' : '/settings/iso';
      case _CanonEndpoint.aperture:
        return ccapi ? '/ver100/shooting/settings/av' : '/settings/aperture';
      case _CanonEndpoint.shutterSpeed:
        return ccapi ? '/ver100/shooting/settings/tv' : '/settings/shutter';
      case _CanonEndpoint.whiteBalance:
        return ccapi ? '/ver100/shooting/settings/wb' : '/settings/wb';
      case _CanonEndpoint.lastContent:
        return ccapi ? '/ver100/contents' : '/capture/last';
    }
  }

  // ------------------------------------------------------------- connection
  /// Menghubungkan aplikasi ke kamera dan membaca informasi perangkat.
  Future<bool> connect() async {
    if (!isPlatformSupported) {
      _state = CanonConnectionState.error;
      _statusMessage = _webUnsupportedMessage;
      _addLog(_webUnsupportedMessage);
      notifyListeners();
      return false;
    }

    _autoPaused = false;
    if (!_enabled) {
      _enabled = true;
      _persist();
    }

    if (_mode == CanonConnectionMode.edsdkDirect) {
      return _connectEdsdk();
    }

    _state = CanonConnectionState.connecting;
    _statusMessage = 'Menghubungkan ke $baseUrl ...';
    _addLog('Connect ke $baseUrl');
    notifyListeners();

    try {
      final Map<String, dynamic> info =
          await _getJson(_pathFor(_CanonEndpoint.deviceInformation))
              .timeout(const Duration(seconds: 8));

      String battery = '-';
      String storage = '-';
      String lens = '-';

      try {
        final Map<String, dynamic> batteryJson =
            await _getJson(_pathFor(_CanonEndpoint.battery));
        battery = '${batteryJson['level'] ?? batteryJson['value'] ?? '-'}';
      } catch (_) {
        // opsional, sebagian firmware tidak menyediakan endpoint ini
      }

      try {
        final Map<String, dynamic> storageJson =
            await _getJson(_pathFor(_CanonEndpoint.storage));
        storage = '${storageJson['nphotos'] ?? storageJson['free'] ?? '-'}';
      } catch (_) {}

      try {
        final Map<String, dynamic> lensJson =
            await _getJson(_pathFor(_CanonEndpoint.lens));
        lens = '${lensJson['name'] ?? lensJson['value'] ?? '-'}';
      } catch (_) {}

      _deviceInfo = CanonDeviceInfo(
        model: '${info['productname'] ?? info['model'] ?? 'Canon EOS R100'}',
        serialNumber: '${info['serialnumber'] ?? info['serial'] ?? '-'}',
        firmware: '${info['firmwareversion'] ?? info['firmware'] ?? '-'}',
        lens: lens,
        batteryLevel: battery,
        storageRemaining: storage,
      );

      _state = CanonConnectionState.connected;
      _statusMessage = '${_deviceInfo.model} siap digunakan.';
      _addLog('Terhubung: ${_deviceInfo.model} (lensa: ${_deviceInfo.lens})');
      notifyListeners();
      return true;
    } catch (error) {
      _state = CanonConnectionState.error;
      _statusMessage = _friendlyError(error);
      _addLog('Gagal connect: $error');
      notifyListeners();
      return false;
    }
  }

  /// Koneksi USB langsung lewat EDSDK.dll (dart:ffi).
  Future<bool> _connectEdsdk() async {
    _state = CanonConnectionState.connecting;
    _statusMessage = 'Menghubungkan ke kamera Canon lewat USB (EDSDK)...';
    _addLog('Connect EDSDK USB');
    notifyListeners();

    try {
      if (kIsWeb || !(Platform.isWindows || debugAllowNonWindowsEdsdk)) {
        throw EdsdkException(
            'Mode USB Langsung hanya tersedia di Windows. '
            'Pilih mode bridge / CCAPI di platform ini.');
      }
      // Beri satu frame agar UI sempat menampilkan status "Connecting".
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final EdsdkNative sdk = _edsdk ??= EdsdkNative();
      if (!sdk.isLoaded) {
        final String? dll = EdsdkNative.locateDll(_sdkDllPath);
        if (dll == null) {
          throw EdsdkException(
              'EDSDK.dll tidak ditemukan. Pilih file EDSDK.dll di pengaturan, '
              'atau letakkan folder EDSDK di samping aplikasi.');
        }
        _addLog('Memuat $dll');
        sdk.load(dll);
      }

      // Selalu mulai sesi bersih (aman setelah kabel dicabut/dicolok ulang).
      stopLiveView(keepWanted: true);
      sdk.closeCamera();
      sdk.openCamera();

      final EdsdkInfo info = sdk.readInfo();
      _deviceInfo = CanonDeviceInfo(
        model: info.model,
        serialNumber: info.serialNumber,
        firmware: info.firmware,
        lens: info.lens,
        batteryLevel: info.battery,
        storageRemaining: info.storage,
      );
      _frameErrors = 0;
      _state = CanonConnectionState.connected;
      _statusMessage = '${_deviceInfo.model} siap digunakan.';
      _addLog('Terhubung (EDSDK): ${_deviceInfo.model} / ${_deviceInfo.lens}');
      notifyListeners();
      return true;
    } catch (error) {
      _state = CanonConnectionState.error;
      _statusMessage = _friendlyError(error);
      _addLog('Gagal connect (EDSDK): $error');
      notifyListeners();
      return false;
    }
  }

  String _friendlyError(Object error) {
    if (error is EdsdkException) {
      return error.message;
    }
    if (error is SocketException) {
      return 'Tidak bisa menjangkau $_host:$_port. '
          'Cek kabel/Wi-Fi kamera dan pastikan service kamera berjalan.';
    }
    if (error is TimeoutException) {
      return 'Kamera tidak merespons (timeout). Coba nyalakan ulang kamera.';
    }
    return error.toString();
  }

  Future<void> disconnect() async {
    _autoPaused = true;
    stopLiveView();
    _edsdk?.closeCamera();
    _state = CanonConnectionState.disconnected;
    _statusMessage = 'Koneksi kamera diputus.';
    _addLog('Disconnect');
    notifyListeners();
  }

  // -------------------------------------------------------------- live view
  /// Memulai live view sehingga preview booth memakai lensa Canon.
  Future<void> startLiveView({int fps = 15}) async {
    _liveViewWanted = true;
    _lastFps = fps;
    if (!isReady || _liveViewRunning) {
      return;
    }

    try {
      if (_mode == CanonConnectionMode.edsdkDirect) {
        _edsdk!.startLiveView();
        _frameErrors = 0;
      } else if (_mode == CanonConnectionMode.ccapiWifi) {
        await _sendJson('POST', _pathFor(_CanonEndpoint.liveViewStart),
            <String, dynamic>{
              'liveviewsize': 'medium',
              'cameradisplay': 'on',
            });
      } else {
        await _sendJson('POST', _pathFor(_CanonEndpoint.liveViewStart));
      }

      _liveViewRunning = true;
      _addLog('Live view start (${fps}fps)');
      final Duration interval =
          Duration(milliseconds: (1000 / fps.clamp(1, 30)).round());
      _liveViewTimer?.cancel();
      _liveViewTimer = Timer.periodic(interval, (_) => _pullFrame());
      notifyListeners();
    } catch (error) {
      _statusMessage = 'Live view gagal: ${_friendlyError(error)}';
      _addLog('Live view gagal: $error');
      notifyListeners();
    }
  }

  Future<void> _pullFrame() async {
    if (_fetchingFrame || _isCapturing || !_liveViewRunning) {
      return;
    }
    _fetchingFrame = true;
    try {
      final Uint8List? frame = _mode == CanonConnectionMode.edsdkDirect
          ? _edsdk?.liveViewFrame()
          : await _getBytes(_pathFor(_CanonEndpoint.liveViewFrame));
      if (frame != null && frame.isNotEmpty) {
        _liveViewFrame = frame;
        _frameErrors = 0;
        notifyListeners();
      }
    } catch (error) {
      // Frame drop diabaikan agar preview tidak berkedip. Untuk USB langsung,
      // error beruntun berarti kamera putus: tampilkan status error.
      if (_mode == CanonConnectionMode.edsdkDirect &&
          ++_frameErrors >= 15) {
        _state = CanonConnectionState.error;
        _statusMessage = 'Koneksi kamera terputus: ${_friendlyError(error)}';
        _addLog('Live view berhenti: $error');
        stopLiveView(keepWanted: true);
      }
    } finally {
      _fetchingFrame = false;
    }
  }

  /// Hentikan live view. [keepWanted] = true untuk penghentian internal
  /// (kamera putus) agar live view dipulihkan otomatis setelah tersambung ulang.
  void stopLiveView({bool keepWanted = false}) {
    if (!keepWanted) {
      _liveViewWanted = false;
    }
    _liveViewTimer?.cancel();
    _liveViewTimer = null;
    if (_liveViewRunning) {
      _addLog('Live view stop');
    }
    _liveViewRunning = false;
    if (_mode == CanonConnectionMode.edsdkDirect) {
      _edsdk?.stopLiveView();
    }
    if (_mode == CanonConnectionMode.ccapiWifi && _state.isConnected) {
      unawaited(_sendJson('POST', _pathFor(_CanonEndpoint.liveViewStop),
              <String, dynamic>{'liveviewsize': 'off', 'cameradisplay': 'on'})
          .catchError((_) => <String, dynamic>{}));
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- capture
  /// Autofocus sebelum jepret (dipakai saat countdown mulai).
  Future<void> autoFocus() async {
    if (!isReady) {
      return;
    }
    try {
      if (_mode == CanonConnectionMode.edsdkDirect) {
        await _edsdk?.autoFocus();
      } else if (_mode == CanonConnectionMode.ccapiWifi) {
        await _sendJson('POST', _pathFor(_CanonEndpoint.shutter),
            <String, dynamic>{'af': true, 'action': 'half_press'});
      } else {
        await _sendJson('POST', _pathFor(_CanonEndpoint.autofocus));
      }
    } catch (error) {
      _addLog('Autofocus gagal: $error');
    }
  }

  /// Menjepret satu foto lewat Canon EOS R100.
  Future<CanonCaptureResult> capture() async {
    if (!isReady) {
      return const CanonCaptureResult(
        success: false,
        message: 'Kamera Canon belum terhubung.',
      );
    }

    _isCapturing = true;
    notifyListeners();

    if (_mode == CanonConnectionMode.edsdkDirect) {
      return _captureEdsdk();
    }

    try {
      Map<String, dynamic> response;
      if (_mode == CanonConnectionMode.ccapiWifi) {
        response = await _sendJson(
          'POST',
          _pathFor(_CanonEndpoint.shutter),
          <String, dynamic>{'af': true, 'action': 'full_press'},
        );
      } else {
        response = await _sendJson(
          'POST',
          _pathFor(_CanonEndpoint.shutter),
          <String, dynamic>{
            'keepOnCard': _saveToCameraCard,
            'download': _downloadAfterCapture,
            'targetDirectory': _downloadDirectory,
          },
        );
      }

      String? path = response['path'] as String? ??
          response['filePath'] as String? ??
          response['url'] as String?;

      Uint8List? bytes;
      if (_downloadAfterCapture) {
        bytes = await _downloadLastPhoto(path);
        if (bytes != null && _downloadDirectory.isNotEmpty) {
          path = await _persistLocally(bytes);
        }
      }

      _addLog('Capture sukses${path != null ? ' -> $path' : ''}');
      return CanonCaptureResult(success: true, filePath: path, bytes: bytes);
    } catch (error) {
      _addLog('Capture gagal: $error');
      return CanonCaptureResult(
        success: false,
        message: _friendlyError(error),
      );
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
  }

  Future<CanonCaptureResult> _captureEdsdk() async {
    try {
      final EdsdkShot shot = await _edsdk!.capture(
        keepOnCard: _saveToCameraCard,
        download: _downloadAfterCapture,
      );
      final Uint8List? bytes = shot.bytes;
      String? path;
      if (bytes != null && _downloadDirectory.trim().isNotEmpty) {
        path = await _persistLocally(bytes);
      }
      _addLog('Capture sukses (EDSDK)'
          '${shot.fileName.isEmpty ? '' : ' ${shot.fileName}'}'
          '${path != null ? ' -> $path' : ''}');
      return CanonCaptureResult(success: true, filePath: path, bytes: bytes);
    } catch (error) {
      _addLog('Capture gagal (EDSDK): $error');
      return CanonCaptureResult(
        success: false,
        message: _friendlyError(error),
      );
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
  }

  Future<Uint8List?> _downloadLastPhoto(String? path) async {
    try {
      if (path != null && path.startsWith('http')) {
        final HttpClientRequest request =
            await _client.getUrl(Uri.parse(path));
        final HttpClientResponse response = await request.close();
        final List<int> bytes = await response
            .fold<List<int>>(<int>[], (List<int> acc, List<int> chunk) {
          acc.addAll(chunk);
          return acc;
        });
        return Uint8List.fromList(bytes);
      }
      return await _getBytes(_pathFor(_CanonEndpoint.lastContent));
    } catch (error) {
      _addLog('Download foto gagal: $error');
      return null;
    }
  }

  Future<String?> _persistLocally(Uint8List bytes) async {
    if (!isPlatformSupported || _downloadDirectory.trim().isEmpty) {
      return null;
    }
    try {
      final Directory dir = Directory(_downloadDirectory);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final String name =
          'booth_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (error) {
      _addLog('Simpan file gagal: $error');
      return null;
    }
  }

  // --------------------------------------------------------------- settings
  /// Mengirim setting eksposur booth ke kamera (ISO, aperture, shutter, WB).
  Future<bool> applyExposureSettings({
    String? iso,
    String? aperture,
    String? shutterSpeed,
    String? whiteBalance,
  }) async {
    if (!isReady) {
      return false;
    }

    bool allOk = true;

    Future<void> put(_CanonEndpoint endpoint, String? value) async {
      if (value == null || value.isEmpty) {
        return;
      }
      try {
        if (_mode == CanonConnectionMode.edsdkDirect) {
          final String kind = switch (endpoint) {
            _CanonEndpoint.iso => 'iso',
            _CanonEndpoint.aperture => 'aperture',
            _CanonEndpoint.shutterSpeed => 'shutter',
            _CanonEndpoint.whiteBalance => 'wb',
            _ => '',
          };
          _edsdk!.setExposure(kind, value);
          return;
        }
        await _sendJson(
          _mode == CanonConnectionMode.ccapiWifi ? 'PUT' : 'POST',
          _pathFor(endpoint),
          <String, dynamic>{'value': value},
        );
      } catch (error) {
        allOk = false;
        _addLog('Set ${endpoint.name} gagal: $error');
      }
    }

    await put(_CanonEndpoint.iso, iso);
    await put(_CanonEndpoint.aperture, aperture);
    await put(_CanonEndpoint.shutterSpeed, shutterSpeed);
    await put(_CanonEndpoint.whiteBalance, whiteBalance);

    _statusMessage = allOk
        ? 'Setting eksposur terkirim ke kamera.'
        : 'Sebagian setting tidak didukung kamera/mode saat ini.';
    notifyListeners();
    return allOk;
  }

  /// Membaca ulang status kamera (baterai, sisa kartu, lensa terpasang).
  Future<void> refreshStatus() async {
    if (!isReady) {
      return;
    }
    await connect();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _liveViewTimer?.cancel();
    _edsdk?.dispose();
    _edsdk = null;
    _clientOrNull?.close(force: true);
    super.dispose();
  }
}

enum _CanonEndpoint {
  deviceInformation,
  battery,
  storage,
  lens,
  liveViewStart,
  liveViewFrame,
  liveViewStop,
  shutter,
  autofocus,
  iso,
  aperture,
  shutterSpeed,
  whiteBalance,
  lastContent,
}
