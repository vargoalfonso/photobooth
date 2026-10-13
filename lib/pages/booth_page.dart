import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart';

import '../models/api_models.dart';
import '../models/booth_models.dart';
import '../models/payment_models.dart';
import '../services/canon_camera_service.dart';
import '../services/monolith_api_client.dart';
import '../services/photobooth_api_service.dart';
import '../state/photo_booth_config.dart';
import '../theme/app_theme.dart';
import '../widgets/capture_widgets.dart';
import '../widgets/landing_widgets.dart';
import 'payment_gate_page.dart';

/// Satu hasil jepretan dalam sesi booth.
class BoothShot {
  const BoothShot({this.filePath, this.bytes});

  final String? filePath;
  final Uint8List? bytes;

  bool get hasImage =>
      bytes != null ||
      (!kIsWeb && filePath != null && File(filePath!).existsSync());
}

class BoothPage extends StatefulWidget {
  const BoothPage({
    super.key,
    required this.config,
    required this.canon,
  });

  final PhotoBoothConfig config;
  final CanonCameraService canon;

  @override
  State<BoothPage> createState() => _BoothPageState();
}

class _BoothPageState extends State<BoothPage> {
  CameraController? _controller;
  bool _isLoading = true;
  late _BoothStage _stage;
  late BoothFrameOption _pendingFrame;
  String? _error;
  String? _activeCameraId;
  ResolutionPreset? _activePreset;

  // --- gerbang pembayaran ---
  /// Sesi yang sudah lunas (hasil [PaymentGatePage]). Null = belum bayar.
  PaidSession? _paid;

  /// True setelah foto terkirim ke sesi berbayar, supaya retry saat PUT
  /// metadata gagal tidak mengirim foto dobel (server membatasi jumlah take).
  bool _paidPhotosSent = false;

  /// Booth baru boleh dimulai setelah pembayaran terverifikasi di dashboard.
  bool get _needsPayment => widget.config.requirePayment;

  /// Stage awal. Kalau pembayaran wajib, selalu mulai dari landing supaya
  /// gerbang QR muncul saat "Tap to Start!", walau overlay tap-to-start dimatikan.
  _BoothStage get _initialStage =>
      (widget.config.enableTapToStartOverlayScreen || _needsPayment)
          ? _BoothStage.landing
          : _BoothStage.frameSelection;

  /// Jumlah jepretan sesi ini: selalu 8 (customer memilih foto terbaik
  /// untuk mengisi slot frame di layar compose).
  int get _photosTotal => kBoothShotsPerSession;

  /// Tampilkan layar QR dan tunggu status paid. True bila boleh lanjut.
  Future<bool> _ensurePaid() async {
    if (!_needsPayment || _paid != null) {
      return true;
    }

    final PaidSession? result = await Navigator.of(context).push<PaidSession>(
      MaterialPageRoute<PaidSession>(
        fullscreenDialog: true,
        builder: (BuildContext _) => PaymentGatePage(config: widget.config),
      ),
    );

    if (!mounted || result == null) {
      return false;
    }
    setState(() => _paid = result);
    return true;
  }

  // --- state sesi capture ---
  final List<BoothShot> _shots = <BoothShot>[];
  int _countdown = 0;
  bool _sessionRunning = false;
  bool _flashOn = false;
  int _retakeCount = 0;
  String? _captureError;

  // --- filter sumber frame pada layar "Select Your Frame" ---
  _FrameSource _frameSource = _FrameSource.all;

  List<BoothFrameOption> get _visibleFrames {
    switch (_frameSource) {
      case _FrameSource.defaults:
        return widget.config.defaultFrames;
      case _FrameSource.server:
        return widget.config.remoteFrames;
      case _FrameSource.all:
        return widget.config.allFrames;
    }
  }

  /// Versi terbaru sebuah frame (mis. setelah background selesai diunduh).
  BoothFrameOption _fresh(BoothFrameOption frame) {
    for (final BoothFrameOption f in widget.config.allFrames) {
      if (f.id == frame.id) return f;
    }
    return frame;
  }

  // --- desain background (dipilih customer sebelum memilih filter) ---
  /// Background yang dipilih customer (lihat [_designKeyOf]). Null = default,
  /// yaitu tampilan frame bawaan tanpa gambar background.
  String? _designKey;

  static String _designKeyOf(FrameBackgroundInfo d) =>
      d.id != null ? 'id:${d.id}' : 'url:${d.url}';

  /// Desain background frame aktif. Template server tidak punya desain.
  List<FrameBackgroundInfo> get _designs => _activeFrame.isRemote
      ? const <FrameBackgroundInfo>[]
      : widget.config.backgroundsFor(_activeFrame.id);

  /// Langkah "Pilih Background" muncul bila dashboard punya background aktif.
  bool get _hasDesignChoice => _designs.isNotEmpty;

  /// Background yang sedang dipakai; null = default (tanpa gambar).
  FrameBackgroundInfo? get _selectedDesign {
    final String? key = _designKey;
    if (key == null) return null;
    for (final FrameBackgroundInfo d in _designs) {
      if (_designKeyOf(d) == key) return d;
    }
    return null;
  }

  /// Frame aktif lengkap dengan desain pilihan customer.
  BoothFrameOption _styledFrame() {
    final BoothFrameOption base = _fresh(_activeFrame);
    if (base.isRemote) return base;
    return base.withBackground(_selectedDesign);
  }

  void _resetDesign() {
    _designKey = null;
  }

  // --- state compose (frame mockup + slot assignment) ---
  /// Frame yang sedang aktif untuk compose/filter/print. Bisa diganti di
  /// layar compose lewat chip.
  late BoothFrameOption _activeFrame = widget.config.frame;

  /// Filter yang sedang aktif untuk preview & cetak strip. Default mengikuti
  /// pilihan filter awal user.
  late BoothFilter _activeFilter = widget.config.filter;

  /// Panjang list = _activeFrame.slotCount. Isi = index ke _shots atau null
  /// bila slot kosong.
  List<int?> _slotAssignments = <int?>[];

  /// Slot yang sedang dipilih user (highlight) untuk menerima assignment
  /// dari tray thumbnail. Null bila belum ada slot yang dipilih.
  int? _selectedSlot;

  /// Foto (index ke _shots) yang sedang di-retake + urutan yang sedang jalan.
  /// Kosong = bukan sedang retake. Dipakai untuk menampilkan label
  /// "Retake Slot N" di layar kamera, bukan progres sesi biasa.
  List<int> _retakeTargets = <int>[];
  int _retakeStep = 0;

  bool get _isRetaking => _sessionRunning && _retakeTargets.isNotEmpty;

  /// Label foto yang sedang di-retake: slot di frame bila sudah ditempatkan.
  String _retakeLabelFor(int shotIndex) {
    final int slot = _slotAssignments.indexOf(shotIndex);
    return slot >= 0 ? 'Slot ${slot + 1}' : 'Foto ${shotIndex + 1}';
  }

  /// Mode "retake banyak foto": tap beberapa slot lalu retake sekaligus.
  bool _bulkRetakeMode = false;
  final Set<int> _bulkSlots = <int>{};

  /// Foto beda-beda per slot, atau foto yang sama dicetak double.
  BoothPhotoMode _printMode = BoothPhotoMode.different;

  /// Jumlah foto unik yang harus dipilih untuk frame + mode saat ini.
  int get _slotTotal => _activeFrame.uniqueSlotCount(_printMode);

  @override
  void initState() {
    super.initState();
    _pendingFrame = widget.config.frame;
    _stage = _initialStage;
    // Segarkan template dari /api/templates setiap booth dibuka.
    unawaited(PhotoboothApiService.syncFrames(widget.config));
    widget.config.addListener(_handleConfigChanged);
    widget.canon.addListener(_handleCanonChanged);
    _bootCamera();
  }

  bool get _useCanon => widget.config.useCanonCamera;

  /// Menentukan sumber gambar: Canon EOS R100 atau kamera perangkat.
  Future<void> _bootCamera() async {
    if (_useCanon) {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      bool ok = widget.canon.state.isConnected;
      if (!ok) {
        ok = await widget.canon.connect();
      }
      if (ok) {
        await widget.canon.startLiveView(fps: widget.config.canonLiveViewFps);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = ok ? null : widget.canon.statusMessage;
      });
      return;
    }

    await _initializeCamera();
  }

  void _handleCanonChanged() {
    if (mounted && _useCanon) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.config.removeListener(_handleConfigChanged);
    widget.canon.removeListener(_handleCanonChanged);
    widget.canon.stopLiveView();
    _controller?.dispose();
    super.dispose();
  }

  void _handleConfigChanged() {
    if (!mounted) return;

    void apply() {
      if (!mounted) return;
      if (_useCanon) {
        setState(() {});
        return;
      }

      // Restart kamera HANYA bila pilihan kamera/resolusi benar-benar
      // berubah. `preferredCameraId` bernilai null secara default, jadi
      // membandingkannya langsung dengan `_activeCameraId` selalu "beda" dan
      // membuat kamera restart tiap ada notifikasi config (mis. selesai
      // sinkron frame dari server) -> preview membeku / error.
      final String? wanted = widget.config.preferredCameraId;
      final bool cameraChanged =
          wanted != null && wanted.isNotEmpty && wanted != _activeCameraId;
      if (cameraChanged || _activePreset != widget.config.resolutionPreset) {
        _initializeCamera();
      } else {
        setState(() {});
      }
    }

    // Notifikasi bisa datang di tengah build/finalize; tunda supaya tidak
    // memanggil setState saat tree terkunci.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  bool _initializingCamera = false;

  Future<void> _initializeCamera() async {
    // Hindari dua inisialisasi berjalan bersamaan (controller saling dispose).
    if (_initializingCamera) return;
    _initializingCamera = true;

    // Lepas controller lama dari UI dulu; dispose dilakukan setelah preview
    // tidak lagi dipakai widget mana pun.
    final CameraController? previous = _controller;
    setState(() {
      _isLoading = true;
      _error = null;
      _controller = null;
    });

    if (previous != null) {
      // Beri waktu satu-dua frame supaya CameraPreview lama sudah lepas dari
      // tree sebelum controller-nya dibuang.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      try {
        await previous.dispose();
      } catch (_) {}
    }

    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No cameras available on this device.');
      }

      final CameraDescription selectedCamera = cameras.firstWhere(
        (CameraDescription camera) =>
            camera.name == widget.config.preferredCameraId,
        orElse: () => cameras.first,
      );

      final CameraController controller = CameraController(
        selectedCamera,
        widget.config.resolutionPreset,
        enableAudio: false,
      );

      await controller.initialize();
      final _ZoomBounds zoomBounds = await _readZoomBounds(controller);
      final double minZoomLevel = zoomBounds.minZoomLevel;
      final double maxZoomLevel = zoomBounds.maxZoomLevel;
      final double resolvedZoom =
          widget.config.cameraZoomLevel.clamp(minZoomLevel, maxZoomLevel);
      final double appliedZoom = zoomBounds.isSupported
          ? await _applyZoomSafely(
              controller,
              preferredZoom: resolvedZoom,
              fallbackZoom: minZoomLevel,
            )
          : minZoomLevel;

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _activeCameraId = selectedCamera.name;
        _activePreset = widget.config.resolutionPreset;
      });

      if (appliedZoom != widget.config.cameraZoomLevel) {
        widget.config.setCameraZoomLevel(appliedZoom);
      }
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.description ?? error.code;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      _initializingCamera = false;
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<_ZoomBounds> _readZoomBounds(CameraController controller) async {
    try {
      final double minZoomLevel = await controller.getMinZoomLevel();
      final double maxZoomLevel = await controller.getMaxZoomLevel();
      return _ZoomBounds(
        minZoomLevel: minZoomLevel,
        maxZoomLevel: maxZoomLevel,
        isSupported: true,
      );
    } catch (error) {
      if (!_isZoomRelatedError(error)) {
        rethrow;
      }

      return const _ZoomBounds(
        minZoomLevel: 1.0,
        maxZoomLevel: 1.0,
        isSupported: false,
      );
    }
  }

  Future<double> _applyZoomSafely(
    CameraController controller, {
    required double preferredZoom,
    required double fallbackZoom,
  }) async {
    double applied = fallbackZoom;

    Future<void> trySetZoom(double zoom) async {
      await controller.setZoomLevel(zoom);
      applied = zoom;
    }

    Future<double> clampToDeviceBounds(double zoom) async {
      final double minZoomLevel = await controller.getMinZoomLevel();
      final double maxZoomLevel = await controller.getMaxZoomLevel();
      return zoom.clamp(minZoomLevel, maxZoomLevel);
    }


    try {
      final double clampedPreferred = await clampToDeviceBounds(preferredZoom);
      await trySetZoom(clampedPreferred);
      return applied;

    } catch (error) {
      if (!_isZoomRelatedError(error)) {
        rethrow;
      }

      // Retry once after re-reading min/max, because some devices report
      // a supported zoom range only after the controller is fully initialized.
      try {
        final double clampedPreferred = await clampToDeviceBounds(preferredZoom);
        await trySetZoom(clampedPreferred);
        return applied;

      } catch (_) {
        // ignore and fall through
      }

      try {
        final double clampedFallback = await clampToDeviceBounds(fallbackZoom);
        await trySetZoom(clampedFallback);

      } catch (fallbackError) {
        if (!_isZoomRelatedError(fallbackError)) {
          rethrow;
        }
        return fallbackZoom;
      }

      return applied;
    }
  }

  bool _isZoomRelatedError(Object error) {
    if (error is CameraException) {
      return error.code.toLowerCase().contains('zoom');
    }
    if (error is PlatformException) {
      return (error.code).toLowerCase().contains('zoom') ||
          (error.message ?? '').toLowerCase().contains('zoom');
    }

    return error.toString().toLowerCase().contains('zoom');
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _BoothStage.landing) {
      return _buildStartScreen(context);
    }

    if (_stage == _BoothStage.frameSelection) {
      return _buildFrameSelectionScreen(context);
    }

    if (_stage == _BoothStage.compose) {
      return _buildComposeScreen(context);
    }

    if (_stage == _BoothStage.background) {
      return _buildBackgroundScreen(context);
    }

    if (_stage == _BoothStage.filterSelect) {
      return _buildFilterSlideScreen(context);
    }

    if (_stage == _BoothStage.result) {
      return _buildResultScreen(context);
    }

    return _buildCaptureScreen(context);
  }

  // -------------------------------------------------------- alur pengambilan

  /// Widget live view aktif: Canon EOS R100 atau kamera perangkat.
  Widget _buildLiveSource(BuildContext context) {
    if (_useCanon) {
      final Uint8List? frame = widget.canon.liveViewFrame;
      if (frame == null) {
        return _StatusMessage(
          icon: Icons.linked_camera_outlined,
          title: widget.canon.state.isConnected
              ? 'Menunggu live view Canon'
              : 'Canon EOS R100 belum terhubung',
          message: widget.canon.statusMessage,
        );
      }

      Widget image = Image.memory(
        frame,
        gaplessPlayback: true,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );

      image = applyBoothFilter(image, widget.config.filter);

      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scale(widget.config.mirrorPreview ? -1.0 : 1.0, 1.0),
        child: image,
      );
    }

    final CameraController? controller = _controller;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _StatusMessage(
        icon: Icons.error_outline,
        title: 'Camera unavailable',
        message: _error!,
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const _StatusMessage(
        icon: Icons.videocam_off,
        title: 'Camera not initialized',
        message: 'Buka Settings untuk memilih kamera lain, lalu coba lagi.',
      );
    }

    return _buildPreview(controller);
  }

  /// Menjalankan satu sesi lengkap: countdown + jepret sebanyak konfigurasi.
  Future<void> _startSession() async {
    if (_sessionRunning) {
      return;
    }

    // Pengaman terakhir: tanpa pembayaran lunas, kembali ke layar awal.
    if (_needsPayment && _paid == null) {
      setState(() => _stage = _BoothStage.landing);
      return;
    }

    setState(() {
      _sessionRunning = true;
      _captureError = null;
      _shots.clear();
      _retakeCount = 0;
      _retakeTargets = <int>[];
      _retakeStep = 0;
    });

    final int total = _photosTotal;
    for (int index = 0; index < total; index++) {
      // Jeda tetap 10 detik sebelum setiap jepretan.
      await _runCountdown(kBoothShotDelaySeconds);
      if (!mounted || !_sessionRunning) {
        return;
      }

      final BoothShot? shot = await _captureOne();
      if (!mounted) {
        return;
      }
      if (shot != null) {
        setState(() => _shots.add(shot));
      }

      if (index < total - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _sessionRunning = false;
      _activeFrame = widget.config.frame;
      _activeFilter = widget.config.filter;
      _resetDesign();
      _initSlotsForFrame(_activeFrame);
      _stage = _BoothStage.compose;
    });
  }

  Future<void> _runCountdown(int seconds) async {
    for (int value = seconds; value > 0; value--) {
      if (!mounted || !_sessionRunning) {
        return;
      }
      setState(() => _countdown = value);

      if (value == 1 &&
          _useCanon &&
          widget.config.canonAutoFocusBeforeShot) {
        unawaited(widget.canon.autoFocus());
      }

      await Future<void>.delayed(const Duration(seconds: 1));
    }

    if (mounted) {
      setState(() => _countdown = 0);
    }
  }

  Future<void> _flash() async {
    if (!widget.config.showFlashOverlay || !mounted) {
      return;
    }
    setState(() => _flashOn = true);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (mounted) {
      setState(() => _flashOn = false);
    }
  }

  /// Melanjutkan preview kamera perangkat yang berhenti/membeku.
  Future<void> _resumePreviewSafely([CameraController? controller]) async {
    final CameraController? c = controller ?? _controller;
    if (_useCanon || c == null || !c.value.isInitialized) return;
    try {
      await c.resumePreview();
    } catch (_) {
      // Abaikan: tidak semua platform mendukung resume.
    }
  }

  /// Pastikan kamera perangkat menampilkan gambar langsung sebelum jepret.
  /// [restart] = nyalakan ulang kamera (di web, ini menjamin stream segar
  /// walau preview sebelumnya membeku di foto terakhir).
  Future<void> _ensureLivePreview({bool restart = false}) async {
    if (_useCanon) return;
    final CameraController? c = _controller;
    if (restart || c == null || !c.value.isInitialized) {
      await _initializeCamera();
      return;
    }
    await _resumePreviewSafely(c);
  }

  /// Satu kali jepret dari sumber kamera yang aktif.
  Future<BoothShot?> _captureOne() async {
    if (widget.config.playShutterSound) {
      unawaited(SystemSound.play(SystemSoundType.click));
    }
    unawaited(_flash());

    if (_useCanon) {
      final CanonCaptureResult result = await widget.canon.capture();
      if (!result.success) {
        if (mounted) {
          setState(() => _captureError = result.message);
        }
        return null;
      }
      // Di web, filePath tidak bisa dibaca via dart:io File, jadi butuh bytes.
      Uint8List? bytes = result.bytes;
      if (bytes == null && kIsWeb && result.filePath != null) {
        try {
          bytes = await XFile(result.filePath!).readAsBytes();
        } catch (_) {
          bytes = null;
        }
      }
      return BoothShot(filePath: result.filePath, bytes: bytes);
    }

    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      setState(() => _captureError = 'Kamera belum siap untuk mengambil foto.');
      return null;
    }

    try {
      final XFile file = await controller.takePicture();
      // Di web (Chrome) preview membeku di foto terakhir setelah jepret.
      // Lanjutkan lagi supaya jepretan berikutnya melihat gambar langsung.
      unawaited(_resumePreviewSafely(controller));
      // Selalu baca bytes agar bisa ditampilkan di web (file.path = blob URL)
      // dan tetap aman di desktop/mobile.
      Uint8List? bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        bytes = null;
      }
      return BoothShot(filePath: file.path, bytes: bytes);
    } on CameraException catch (error) {
      if (mounted) {
        setState(() => _captureError = error.description ?? error.code);
      }
      return null;
    }
  }

  /// Retake satu foto tertentu (dari layar compose atau halaman hasil).
  Future<void> _retakeShot(int index) => _retakeShots(<int>[index]);

  /// Retake satu atau banyak foto sekaligus. Kamera dibuka kembali dan
  /// tiap foto di [shotIndexes] diambil ulang berurutan (countdown masing-
  /// masing), lalu kembali ke layar compose dengan slot yang sama.
  Future<void> _retakeShots(List<int> shotIndexes) async {
    if (!widget.config.enableRetakeButton || shotIndexes.isEmpty) {
      return;
    }
    final List<int> targets = shotIndexes.toSet().toList()..sort();

    if (!widget.config.unlimitedRetakes) {
      final int remaining = widget.config.retakeLimitPerPhoto - _retakeCount;
      if (remaining < targets.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              remaining <= 0
                  ? 'Batas retake tercapai (${widget.config.retakeLimitPerPhoto}x).'
                  : 'Sisa jatah retake $remaining kali, kamu memilih ${targets.length} foto.',
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      _stage = _BoothStage.preview;
      _sessionRunning = true;
      _captureError = null;
      _retakeCount += targets.length;
      _retakeTargets = targets;
      _retakeStep = 0;
    });

    // Kamera sempat berhenti di layar compose / membeku setelah jepret
    // sebelumnya: nyalakan lagi dulu supaya yang tampil gambar langsung.
    await _ensureLivePreview(restart: kIsWeb);
    if (!mounted) {
      return;
    }

    for (int i = 0; i < targets.length; i++) {
      if (mounted) setState(() => _retakeStep = i);
      if (i > 0) await _ensureLivePreview();
      await _runCountdown(kBoothShotDelaySeconds);
      if (!mounted || !_sessionRunning) {
        return;
      }
      final BoothShot? shot = await _captureOne();
      if (!mounted) {
        return;
      }
      final int index = targets[i];
      if (shot != null) {
        setState(() {
          if (index < _shots.length) {
            _shots[index] = shot;
          } else {
            _shots.add(shot);
          }
        });
      }
      if (i < targets.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _sessionRunning = false;
      _retakeTargets = <int>[];
      _retakeStep = 0;
      _bulkRetakeMode = false;
      _bulkSlots.clear();
      // Kembali ke layar compose supaya user langsung lihat hasil retake di
      // dalam frame mockup (slot tetap sama).
      _stage = _BoothStage.compose;
    });
  }

  // ------------------------------------------------------------- helper compose

  /// Menyiapkan daftar slot untuk frame [frame]. Semua slot AWALNYA KOSONG:
  /// customer sendiri yang menempatkan foto dari tray di bawah. Slot pertama
  /// langsung terpilih supaya customer bisa langsung tap foto.
  void _initSlotsForFrame(BoothFrameOption frame) {
    final int count = frame.uniqueSlotCount(_printMode);
    _slotAssignments = List<int?>.filled(count, null);
    _selectedSlot = count > 0 ? 0 : null;
  }

  /// Index slot kosong pertama, atau null bila semua sudah terisi.
  int? _firstEmptySlot() {
    final int index = _slotAssignments.indexWhere((int? v) => v == null);
    return index == -1 ? null : index;
  }

  /// Ganti mode foto beda-beda <-> double di layar compose. Pilihan foto
  /// yang sudah ada dipertahankan sebanyak mungkin.
  void _switchPrintMode(BoothPhotoMode mode) {
    if (mode == _printMode) {
      return;
    }
    final List<int?> previous = List<int?>.from(_slotAssignments);
    final int count = _activeFrame.uniqueSlotCount(mode);
    final List<int?> next = List<int?>.filled(count, null);
    final int copy = count < previous.length ? count : previous.length;
    for (int i = 0; i < copy; i++) {
      next[i] = previous[i];
    }
    setState(() {
      _printMode = mode;
      _slotAssignments = next;
      _selectedSlot = _bulkRetakeMode ? null : _firstEmptySlot();
      _bulkSlots.clear();
    });
  }

  /// Tap sebuah slot untuk memilihnya (highlight); tap lagi untuk unselect.
  void _handleSlotTap(int slotIndex) {
    setState(() {
      if (_bulkRetakeMode) {
        // Mode retake banyak foto: hanya slot berisi foto yang bisa dipilih.
        final bool hasPhoto = slotIndex < _slotAssignments.length &&
            _slotAssignments[slotIndex] != null;
        if (hasPhoto && !_bulkSlots.remove(slotIndex)) {
          _bulkSlots.add(slotIndex);
        }
        return;
      }
      _selectedSlot = _selectedSlot == slotIndex ? null : slotIndex;
    });
  }

  void _setBulkRetakeMode(bool on) {
    setState(() {
      _bulkRetakeMode = on;
      _bulkSlots.clear();
      // Mode biasa: tidak ada slot aktif sampai user memilih.
      if (on) _selectedSlot = null;
    });
  }

  /// Tap sebuah thumbnail di tray untuk menempatkan foto ke slot yang aktif.
  /// Bila foto tersebut sudah ada di slot lain, dilakukan swap.
  void _assignShotToSelectedSlot(int shotIndex) {
    final int? target = _selectedSlot;
    if (target == null || target >= _slotAssignments.length) {
      return;
    }
    setState(() {
      final int existingSlot = _slotAssignments.indexOf(shotIndex);
      final int? previousAtTarget = _slotAssignments[target];
      _slotAssignments[target] = shotIndex;
      if (existingSlot != -1 && existingSlot != target) {
        _slotAssignments[existingSlot] = previousAtTarget;
      }
      // Mengisi slot kosong -> otomatis pilih slot kosong berikutnya.
      // Mengganti/menukar foto yang sudah ada -> selesai, tidak lompat.
      _selectedSlot = previousAtTarget == null ? _firstEmptySlot() : null;
    });
  }

  /// Menghapus foto dari slot yang aktif (bila ada).
  void _clearSelectedSlot() {
    final int? target = _selectedSlot;
    if (target == null || target >= _slotAssignments.length) {
      return;
    }
    setState(() {
      _slotAssignments[target] = null;
      _selectedSlot = null;
    });
  }

  void _resetSession() {
    setState(() {
      _shots.clear();
      _countdown = 0;
      _retakeCount = 0;
      _slotAssignments = <int?>[];
      _selectedSlot = null;
      _bulkRetakeMode = false;
      _bulkSlots.clear();
      _retakeTargets = <int>[];
      _retakeStep = 0;
      _activeFrame = widget.config.frame;
      _activeFilter = widget.config.filter;
      _resetDesign();
      _captureError = null;
      _sessionRunning = false;
      _uploading = false;
      _lastUploadedSessionId = null;
      _uploadedShotIndexes = <int>[];
      // Sesi berikutnya wajib bayar lagi.
      _paid = null;
      _paidPhotosSent = false;
      _stage = _initialStage;
    });
  }

  // -------------------------------------------------------- upload monolith
  bool _uploading = false;
  int? _lastUploadedSessionId;

  /// Kirim seluruh [_shots] ke API monolith sebagai sesi baru.
  ///
  /// Bila fitur API belum diaktifkan (lihat `PhotoBoothConfig.apiEnabled`)
  /// tombol pemanggilnya tidak akan aktif, jadi method ini aman dipanggil.
  Future<int?> _uploadCurrentSessionToServer() async {
    if (_uploading || _shots.isEmpty) return null;

    final PhotoboothApiService? svc =
        PhotoboothApiService.fromConfig(widget.config);
    if (svc == null) {
      _showApiInactive();
      return null;
    }

    setState(() => _uploading = true);

    try {
      // 1) Tentukan template di server. Frame yang dipilih dari /api/templates
      //    sudah membawa id-nya; frame bawaan Flutter dicocokkan berdasarkan
      //    jumlah slot seperti sebelumnya.
      //    Sesi berbayar tidak membutuhkan template server: sesinya sudah ada
      //    dan frame bawaan Flutter dicatat lewat `layout`. Jadi jangan menebak
      //    template (bisa salah) dan jangan gagal setelah pelanggan bayar.
      final PaidSession? paid = _paid;
      int? frameId = _activeFrame.remoteId;
      if (frameId == null && paid == null) {
        final List<PhotoFrameDto> templates = await svc.listTemplates();
        PhotoFrameDto? match;
        final int photoCount = _shots.length;
        for (final PhotoFrameDto t in templates) {
          if (t.slotCount == photoCount) {
            match = t;
            break;
          }
        }
        match ??= templates.isNotEmpty ? templates.first : null;
        frameId = match?.id;
      }

      if (frameId == null && paid == null) {
        _showSnack(
          'Tidak ada template aktif di server. Buat dulu di dashboard monolith.',
        );
        return null;
      }

      // 2) Siapkan payload photos[]. Tanpa pembayaran, server mewajibkan
      //    jumlah foto == jumlah slot template, jadi kirim foto sesuai urutan
      //    slot. Sesi berbayar mengirim semua jepretan (dibatasi paket).
      final bool slotOrdered = _activeFrame.isRemote && _paid == null;
      final List<int> sourceIdx = slotOrdered
          ? <int>[
              for (final int? a in _slotAssignments)
                if (a != null && a < _shots.length) a,
            ]
          : <int>[for (int i = 0; i < _shots.length; i++) i];
      final List<BoothShot> source = <BoothShot>[
        for (final int i in sourceIdx) _shots[i],
      ];
      if (slotOrdered && source.length != _activeFrame.slotCount) {
        _showSnack(
          'Isi semua ${_activeFrame.slotCount} slot template dulu sebelum upload.',
        );
        return null;
      }

      final List<PhotoUpload> uploads = <PhotoUpload>[];
      final List<int> uploadedIdx = <int>[];
      for (int i = 0; i < source.length; i++) {
        final BoothShot shot = source[i];
        final Uint8List? bytes = shot.bytes;
        final String? path = shot.filePath;
        final String filename =
            'shot_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        if (bytes != null) {
          uploads.add(PhotoUpload(filename: filename, bytes: bytes));
          uploadedIdx.add(sourceIdx[i]);
        } else if (path != null && !kIsWeb) {
          uploads.add(PhotoUpload(filename: filename, filePath: path));
          uploadedIdx.add(sourceIdx[i]);
        }
      }
      final Map<String, dynamic> composition = _buildComposition(uploadedIdx);

      if (uploads.isEmpty) {
        _showSnack('Tidak ada foto yang bisa dibaca untuk diupload.');
        return null;
      }

      // 3) Simpan ke server.
      //    - Sudah bayar: foto masuk ke sesi yang dibuat saat pembayaran
      //      (POST /photo-sessions/{id}/photos + PUT metadata). Server menolak
      //      sesi yang belum paid dan membatasi jumlah foto sesuai paket.
      //    - Tanpa pembayaran (mode lama): POST /api/photo-sessions.
      final PhotoSessionDto session;
      if (paid != null) {
        if (!_paidPhotosSent) {
          // Upload sebelumnya bisa saja sudah sampai & tersimpan di server
          // walau aplikasi menerima timeout. Cek dulu supaya foto tidak
          // dikirim dobel (server menolak: "Sisa take ... hanya 0 foto").
          final PhotoSessionDto existing =
              await svc.getSession(paid.sessionId);
          if (existing.media.isEmpty) {
            await svc.addPhotos(sessionId: paid.sessionId, photos: uploads);
          }
          _paidPhotosSent = true;
        }
        session = await svc.updateSession(
          sessionId: paid.sessionId,
          photoFrameId: frameId,
          filter: filterToApiString(_activeFilter),
          layout: _activeFrame.id,
          takenAt: DateTime.now(),
          composition: composition,
        );
      } else {
        session = await svc.createSession(
          boothId: widget.config.apiBoothId,
          photoFrameId: frameId!,
          photos: uploads,
          filter: filterToApiString(_activeFilter),
          layout: _activeFrame.id,
          takenAt: DateTime.now(),
        );
        // Susunan akhir untuk halaman detail di dashboard (tidak fatal).
        try {
          await svc.updateSession(
            sessionId: session.id,
            composition: composition,
          );
        } catch (_) {}
      }
      _uploadedShotIndexes = uploadedIdx;

      if (!mounted) return null;
      setState(() => _lastUploadedSessionId = session.id);
      _showSnack(
        'Sesi ${session.sessionCode} tersimpan ke server (id #${session.id}).',
      );
      return session.id;
    } on ApiException catch (e) {
      _showSnack('Upload gagal: ${e.message}');
    } catch (e) {
      _showSnack('Upload gagal: $e');
    } finally {
      svc.close();
      if (mounted) setState(() => _uploading = false);
    }

    return null;
  }

  /// Index _shots yang terunggah ke server, berurutan sama dengan urutan
  /// `media` di sesi (dipakai untuk memetakan sel frame -> foto).
  List<int> _uploadedShotIndexes = <int>[];

  /// Susunan akhir pilihan customer (frame + background + foto per sel +
  /// filter) supaya dashboard bisa menampilkan ulang hasilnya dan memilih
  /// filter lain. `cells[i]` = posisi foto di daftar media sesi (-1 = kosong).
  Map<String, dynamic> _buildComposition(List<int> uploadedShotIndexes) {
    final BoothFrameOption frame = _styledFrame();
    final bool hasBg = frame.hasBackground && !frame.isTemplate;

    // Sama dengan _buildFrameSheet: susunan foto mengikuti bentuk area desain.
    BoothFrameOption inner = frame;
    if (hasBg) {
      final FrameBackgroundInfo info = frame.background!;
      final bool areaLandscape = info.areaH > 0 &&
          (info.areaW / info.areaH) * frame.backgroundAspect > 1;
      if (frame.isLandscape != areaLandscape) {
        inner = frame.withLayout(frame.layout.transposed);
      }
    }

    final List<int> cells = <int>[
      for (final int slot in inner.cellSources(_printMode))
        (slot < _slotAssignments.length && _slotAssignments[slot] != null)
            ? uploadedShotIndexes.indexOf(_slotAssignments[slot]!)
            : -1,
    ];

    final (int cols, int rows) = switch (inner.layout) {
      BoothFrameLayout.stripVertical => (1, inner.slotCount),
      BoothFrameLayout.stripHorizontal => (inner.slotCount, 1),
      BoothFrameLayout.gridPortrait => (2, inner.slotCount ~/ 2),
      BoothFrameLayout.gridLandscape => (inner.slotCount ~/ 2, 2),
      BoothFrameLayout.template => (0, 0),
    };

    final String copiesDirection = hasBg
        ? (frame.backgroundAspect > 1 ? 'column' : 'row')
        : (inner.layout == BoothFrameLayout.stripHorizontal
            ? 'column'
            : 'row');

    final int rgb = frame.borderColor.toARGB32() & 0xFFFFFF;

    return <String, dynamic>{
      'version': 1,
      'frame_id': frame.id,
      'frame_name': frame.name,
      'remote_frame_id': frame.remoteId,
      'print_mode': _printMode.name,
      'layout': inner.layout.name,
      'cols': cols,
      'rows': rows,
      'cells': cells,
      'copies': frame.stripCopies(_printMode),
      'copies_direction': copiesDirection,
      'border_color': '#${rgb.toRadixString(16).padLeft(6, '0')}',
      'filter': filterToApiString(_activeFilter),
      'background': hasBg
          ? <String, dynamic>{
              'id': frame.background!.id,
              'aspect': frame.backgroundAspect,
              'area': <String, dynamic>{
                'x': frame.background!.areaX,
                'y': frame.background!.areaY,
                'w': frame.background!.areaW,
                'h': frame.background!.areaH,
              },
            }
          : null,
      'template': frame.isTemplate
          ? <String, dynamic>{
              'canvas_w': frame.canvasWidth,
              'canvas_h': frame.canvasHeight,
              'slots': <Map<String, dynamic>>[
                for (final BoothSlotRect r in frame.slots)
                  <String, dynamic>{'x': r.x, 'y': r.y, 'w': r.w, 'h': r.h},
              ],
            }
          : null,
    };
  }

  bool _printing = false;

  /// Context strip hasil akhir di layar filter/cetak, untuk memotret mock.
  /// (Sengaja bukan GlobalKey: GlobalKey bisa memicu error saat subtree
  /// berpindah/dilepas bersamaan dengan dialog.)
  BuildContext? _stripContext;

  /// Sembunyikan nomor slot saat memotret mock supaya hasilnya bersih.
  bool _hideSlotBadges = false;

  String? _lastEmail;

  /// Memotret strip yang tampil di layar jadi PNG (frame + background + foto
  /// + filter). Null bila layar saat ini tidak menampilkan strip.
  Future<Uint8List?> _captureStripPng() async {
    if (!(_stripContext?.mounted ?? false)) return null;
    setState(() => _hideSlotBadges = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!(_stripContext?.mounted ?? false)) return null;
      final Object? box = _stripContext?.findRenderObject();
      if (box is! RenderRepaintBoundary) return null;
      final ui.Image image = await box.toImage(pixelRatio: 3.0);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Gagal membuat mock strip: $e');
      return null;
    } finally {
      if (mounted) setState(() => _hideSlotBadges = false);
    }
  }

  /// Dialog masukkan email. Null = dilewati.
  Future<String?> _askEmail() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) => _EmailDialog(initial: _lastEmail),
    );
  }

  /// Dipanggil saat pelanggan menekan "Cetak":
  ///  1. simpan foto ke server + unggah mock strip + catat ke dashboard
  ///     (menu "Hasil Print"),
  ///  2. kirim ke printer (snackbar status),
  ///  3. tanya email, lalu kirim semua foto + mock strip ke email itu.
  Future<void> _printCurrentSession(String printedMessage) async {
    if (_printing || _shots.isEmpty) return;
    setState(() => _printing = true);

    try {
      if (!widget.config.apiEnabled) {
        // Mode offline: tidak ada server untuk menyimpan / mencetak.
        _showSnack(
            '$printedMessage (API belum aktif, tidak disimpan ke dashboard)');
        return;
      }

      // Potret mock selagi strip masih tampil di layar.
      final Uint8List? mock = await _captureStripPng();
      if (!mounted) return;

      // 1) Simpan foto ke server bila sesi ini belum pernah diunggah.
      final int? sessionId =
          _lastUploadedSessionId ?? await _uploadCurrentSessionToServer();
      if (sessionId == null) return; // gagal; alasannya sudah ditampilkan.

      final PhotoboothApiService? svc =
          PhotoboothApiService.fromConfig(widget.config);
      if (svc == null) {
        _showApiInactive();
        return;
      }

      try {
        // 2) Mock strip + catat ke dashboard "Hasil Print".
        if (mock != null) {
          try {
            await svc.uploadStrip(sessionId, mock);
          } catch (e) {
            _showSnack('Mock strip tidak terunggah: $e');
          }
        }
        try {
          await svc.markPrinted(
            sessionId,
            composition: _uploadedShotIndexes.isEmpty
                ? null
                : _buildComposition(_uploadedShotIndexes),
          );
        } on ApiException catch (e) {
          _showSnack('Foto tersimpan, tapi gagal mencatat cetak: ${e.message}');
        } catch (e) {
          _showSnack('Foto tersimpan, tapi gagal mencatat cetak: $e');
        }

        // 3) Kirim ke printer.
        _showSnack('Mengirim ke ${widget.config.primaryPrinter}...');
        try {
          await svc.printSession(
            sessionId: sessionId,
            print: true,
            markPrinted: false,
          );
          _showSnack(
              '$printedMessage Tersimpan juga di dashboard (Hasil Print).');
        } on ApiException catch (e) {
          _showSnack('Gagal mencetak: ${e.message}');
        } catch (e) {
          _showSnack('Gagal mencetak: $e');
        }

        // 4) Tanya email, lalu kirim semua foto + mock.
        if (!mounted) return;
        final String? email = await _askEmail();
        if (email == null || !mounted) return;
        _lastEmail = email;

        _showSnack('Mengirim email ke $email...');
        try {
          final PrintResult r = await svc.printSession(
            sessionId: sessionId,
            email: email,
            print: false,
            markPrinted: false,
          );
          _showSnack(r.emailSent ? 'Email terkirim ke $email.' : r.message);
        } on ApiException catch (e) {
          _showSnack('Gagal kirim email: ${e.message}');
        } catch (e) {
          _showSnack('Gagal kirim email: $e');
        }
      } finally {
        svc.close();
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _showApiInactive() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
            'Base URL API masih kosong. Buka menu API Monolith untuk mengisi.'),
        action: SnackBarAction(
          label: 'Buka',
          onPressed: () =>
              Navigator.of(context).pushNamed('/api-settings'),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------ layar capture
  /// Teks arahan untuk customer selama sesi berjalan.
  String get _capturePrompt {
    if (_isRetaking) {
      final String label =
          _retakeLabelFor(_retakeTargets[_retakeStep.clamp(0, _retakeTargets.length - 1)]);
      return _countdown > 0
          ? 'Retake $label — lihat kamera'
          : 'Foto baru untuk $label';
    }
    final int total = _photosTotal;
    if (_countdown > 0) {
      return _shots.length >= total - 1
          ? 'Foto terakhir, senyum!'
          : 'Siap-siap, lihat kamera';
    }
    return _shots.isEmpty ? 'Bersiap...' : 'Bagus! Ganti pose';
  }

  /// Gambar thumbnail dari satu hasil foto.
  Widget _shotImage(BoothShot shot) {
    if (shot.bytes != null) {
      return Image.memory(shot.bytes!, fit: BoxFit.cover, gaplessPlayback: true);
    }
    if (!kIsWeb && shot.filePath != null) {
      return Image.file(
        File(shot.filePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26),
      );
    }
    return const ColoredBox(color: Colors.black26);
  }

  Widget _buildCaptureHeader(
    BuildContext context, {
    required int taken,
    required int total,
  }) {
    return Row(
      children: <Widget>[
        IconButton.filledTonal(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.config.boothName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                'Siap memulai sesi foto',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        StatusBadge(
          label: _useCanon
              ? (widget.canon.state.isConnected
                  ? 'Canon EOS R100'
                  : 'Canon offline')
              : 'Kamera perangkat',
          color: _useCanon
              ? (widget.canon.state.isConnected
                  ? AppTheme.mint
                  : AppTheme.danger)
              : AppTheme.sky,
          icon: Icons.camera,
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          onPressed: _bootCamera,
          icon: const Icon(Icons.refresh),
          tooltip: 'Reload kamera',
        ),
      ],
    );
  }

  Widget _buildCaptureScreen(BuildContext context) {
    final int total = _photosTotal;
    final int taken = _shots.length;
    final bool running = _sessionRunning;
    final BoothFrameOption frame = widget.config.frame;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(running ? 14 : 20),
            child: Column(
              children: <Widget>[
                // Header admin disembunyikan saat sesi berjalan supaya
                // customer hanya melihat kamera + progres.
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: running
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _buildCaptureHeader(
                              context,
                              taken: taken,
                              total: total,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: frame.borderColor.withValues(alpha: 0.35),
                          blurRadius: 40,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: frame.borderColor,
                            width: 6,
                          ),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusXl),
                          gradient: LinearGradient(colors: frame.gradient),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            _buildLiveSource(context),
                            if (widget.config.showGrid && !running)
                              const _GridOverlay(),
                            ViewfinderCorners(
                              color: _countdown > 0
                                  ? AppTheme.accent
                                  : Colors.white70,
                            ),
                            Positioned(
                              left: 18,
                              top: 18,
                              child: _isRetaking
                                  ? _RetakePill(
                                      label: _retakeTargets.length == 1
                                          ? 'Retake ${_retakeLabelFor(_retakeTargets.first)}'
                                          : 'Retake ${_retakeStep + 1} dari ${_retakeTargets.length} • ${_retakeLabelFor(_retakeTargets[_retakeStep.clamp(0, _retakeTargets.length - 1)])}',
                                    )
                                  : CaptureProgressPill(
                                      total: total,
                                      taken: taken,
                                      running: running,
                                    ),
                            ),
                            if (running)
                              Positioned(
                                right: 22,
                                top: 24,
                                child: Text(
                                  widget.config.boothName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                    shadows: <Shadow>[
                                      Shadow(
                                          color: Colors.black87,
                                          blurRadius: 10),
                                    ],
                                  ),
                                ),
                              ),
                            if (running && _countdown == 0)
                              Positioned(
                                left: 18,
                                right: 18,
                                bottom: 26,
                                child: Center(
                                  child: CapturePromptBanner(
                                    text: _capturePrompt,
                                  ),
                                ),
                              ),
                            if (!running)
                              Positioned(
                                left: 18,
                                right: 18,
                                bottom: 18,
                                child: Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: _InfoPill(
                                        icon: Icons.filter_alt,
                                        text: widget.config.filter.label,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _InfoPill(
                                        icon: Icons.border_outer,
                                        text: frame.name,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _InfoPill(
                                        icon: Icons.timer,
                                        text:
                                            '${widget.config.countdownSeconds}s',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_countdown > 0)
                              CaptureCountdown(
                                value: _countdown,
                                prompt: _capturePrompt,
                              ),
                            CaptureFlash(on: _flashOn),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (running) ...<Widget>[
                  const SizedBox(height: 14),
                  CaptureShotTray(
                    total: total,
                    taken: taken,
                    thumbBuilder: (int index) => _shotImage(_shots[index]),
                  ),
                  const SizedBox(height: 2),
                ] else ...<Widget>[
                  if (_captureError != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(
                            color: AppTheme.danger.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.error_outline,
                              color: AppTheme.danger, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _captureError!,
                              style: const TextStyle(color: AppTheme.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/canon'),
                          icon: const Icon(Icons.camera),
                          label: const Text('Canon Setup'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/settings'),
                          icon: const Icon(Icons.settings),
                          label: const Text('Settings'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: GradientButton(
                          expand: true,
                          label: 'Mulai Capture ($total foto, jeda ${kBoothShotDelaySeconds}s)',
                          icon: Icons.camera_alt_rounded,
                          onPressed: _startSession,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------- layar compose (mockup)
  Widget _buildComposeScreen(BuildContext context) {
    final int filled = _slotAssignments.where((int? v) => v != null).length;
    final int total = _slotTotal;
    final bool allFilled = filled == total && total > 0;
    final int? selected = _selectedSlot;
    final bool selectionHasPhoto = selected != null &&
        selected < _slotAssignments.length &&
        _slotAssignments[selected] != null;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: 'Susun Frame',
                  subtitle: _bulkRetakeMode
                      ? (_bulkSlots.isEmpty
                          ? 'Tap foto di frame yang ingin diulang (bisa lebih dari satu).'
                          : '${_bulkSlots.length} foto dipilih untuk retake.')
                      : selected == null
                          ? 'Pilih $total foto terbaik dari ${_shots.length} jepretan. $filled/$total slot terisi.'
                          : 'Slot ${selected + 1} dipilih — tap foto di bawah untuk menempatkan.',
                  trailing: StatusBadge(
                    label: '$filled/$total slot',
                    color: allFilled
                        ? _activeFrame.borderColor
                        : AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  children: <Widget>[
                    for (final BoothPhotoMode mode in BoothPhotoMode.values)
                      ChoiceChip(
                        label: Text(mode.label),
                        selected: _printMode == mode,
                        onSelected: (_) => _switchPrintMode(mode),
                      ),
                    if (widget.config.enableRetakeButton)
                      FilterChip(
                        avatar: const Icon(Icons.checklist_rounded, size: 18),
                        label: const Text('Retake banyak foto'),
                        selected: _bulkRetakeMode,
                        onSelected: _setBulkRetakeMode,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Center(
                    child: _StripPreview(
                      frame: _styledFrame(),
                      printMode: _printMode,
                      shots: _shots,
                      assignments: _slotAssignments,
                      selectedSlot: _selectedSlot,
                      multiSelected: _bulkSlots,
                      onSlotTap: _handleSlotTap,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 96,
                  child: _shots.isEmpty
                      ? const Center(
                          child: Text(
                            'Belum ada foto pada sesi ini.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _shots.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (BuildContext ctx, int i) {
                            final int slotIndex =
                                _slotAssignments.indexOf(i);
                            return _ShotThumb(
                              shot: _shots[i],
                              index: i,
                              usedInSlot:
                                  slotIndex == -1 ? null : slotIndex + 1,
                              enabled: _selectedSlot != null,
                              onTap: _selectedSlot == null
                                  ? null
                                  : () => _assignShotToSelectedSlot(i),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _resetSession,
                        icon: const Icon(Icons.replay),
                        label: const Text('Sesi Baru'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: selectionHasPhoto ? _clearSelectedSlot : null,
                        icon: const Icon(Icons.close),
                        label: const Text('Kosongkan slot'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: !widget.config.enableRetakeButton
                            ? null
                            : _bulkRetakeMode
                                ? (_bulkSlots.isEmpty
                                    ? null
                                    : () => _retakeShots(<int>[
                                          for (final int slot
                                              in (_bulkSlots.toList()..sort()))
                                            if (_slotAssignments[slot] != null)
                                              _slotAssignments[slot]!,
                                        ]))
                                : (selectionHasPhoto
                                    ? () => _retakeShot(
                                        _slotAssignments[selected]!)
                                    : null),
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          _bulkRetakeMode
                              ? (_bulkSlots.isEmpty
                                  ? 'Pilih foto dulu'
                                  : 'Retake ${_bulkSlots.length} foto')
                              : 'Retake foto',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GradientButton(
                        expand: true,
                        label: allFilled
                            ? (_hasDesignChoice
                                ? 'Pilih Background'
                                : 'Lanjut ke Filter')
                            : 'Isi semua slot dulu',
                        icon: _hasDesignChoice
                            ? Icons.palette_outlined
                            : Icons.auto_fix_high,
                        onPressed: allFilled
                            ? () => setState(() => _stage = _hasDesignChoice
                                ? _BoothStage.background
                                : _BoothStage.filterSelect)
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------- layar pemilihan desain
  Widget _buildBackgroundScreen(BuildContext context) {
    final List<FrameBackgroundInfo> designs = _designs;
    final FrameBackgroundInfo? selected = _selectedDesign;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: 'Pilih Background',
                  subtitle:
                      'Pilih gambar background untuk frame kamu. Foto tetap sama, hanya backgroundnya yang berubah.',
                  trailing: StatusBadge(
                    label: selected?.name ?? 'Default',
                    color: _activeFrame.borderColor,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Center(
                    child: _StripPreview(
                      frame: _styledFrame(),
                      printMode: _printMode,
                      shots: _shots,
                      assignments: _slotAssignments,
                      selectedSlot: null,
                      onSlotTap: null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: designs.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (BuildContext ctx, int i) {
                      if (i == 0) {
                        return _DesignCard(
                          label: 'Default',
                          accent: _activeFrame.borderColor,
                          selected: selected == null,
                          onTap: () => setState(() => _designKey = null),
                        );
                      }
                      final FrameBackgroundInfo d = designs[i - 1];
                      return _DesignCard(
                        label: d.name,
                        info: d,
                        accent: _activeFrame.borderColor,
                        selected: identical(d, selected),
                        onTap: () =>
                            setState(() => _designKey = _designKeyOf(d)),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _stage = _BoothStage.compose),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Kembali Compose'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GradientButton(
                        expand: true,
                        label: 'Lanjut ke Filter',
                        icon: Icons.auto_fix_high,
                        onPressed: () => setState(
                            () => _stage = _BoothStage.filterSelect),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Foto contoh untuk kartu filter: foto pertama yang sudah ditaruh di slot
  /// (atau jepretan pertama). Di-decode kecil supaya 26 kartu tetap ringan.
  Widget? _filterSample() {
    BoothShot? shot;
    for (final int? a in _slotAssignments) {
      if (a != null && a < _shots.length) {
        shot = _shots[a];
        break;
      }
    }
    shot ??= _shots.isEmpty ? null : _shots.first;
    if (shot == null) return null;

    if (shot.bytes != null) {
      return Image.memory(shot.bytes!,
          fit: BoxFit.cover, cacheWidth: 240, gaplessPlayback: true);
    }
    if (!kIsWeb && shot.filePath != null) {
      return Image.file(File(shot.filePath!),
          fit: BoxFit.cover,
          cacheWidth: 240,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26));
    }
    return null;
  }

  // -------------------------------------------------- layar pemilihan filter
  Widget _buildFilterSlideScreen(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: 'Pilih Filter',
                  subtitle:
                      'Geser filter di bawah untuk melihat efeknya pada seluruh strip.',
                  trailing: StatusBadge(
                    label: _activeFrame.name,
                    color: _activeFrame.borderColor,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Center(
                    child: Builder(
                      builder: (BuildContext stripCtx) {
                        _stripContext = stripCtx;
                        return RepaintBoundary(
                          child: _StripPreview(
                            frame: _styledFrame(),
                            printMode: _printMode,
                            shots: _shots,
                            assignments: _slotAssignments,
                            selectedSlot: null,
                            filter: _activeFilter,
                            showBadges: !_hideSlotBadges,
                            onSlotTap: null,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 124,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: BoothFilter.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (BuildContext ctx, int i) {
                      final BoothFilter f = BoothFilter.values[i];
                      return _FilterCard(
                        filter: f,
                        selected: f == _activeFilter,
                        sample: _filterSample(),
                        onTap: () => setState(() => _activeFilter = f),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _stage =
                            _hasDesignChoice
                                ? _BoothStage.background
                                : _BoothStage.compose),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(_hasDesignChoice
                            ? 'Kembali ke Background'
                            : 'Kembali Compose'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GradientButton(
                        expand: true,
                        label: widget.config.disableAllPrinting
                            ? 'Printing dinonaktifkan'
                            : 'Cetak ke ${widget.config.primaryPrinter}',
                        icon: Icons.print,
                        onPressed: widget.config.disableAllPrinting || _printing
                            ? null
                            : () => _printCurrentSession(
                                  'Strip ${_activeFrame.name} + filter ${_activeFilter.label} dikirim ke ${widget.config.primaryPrinter}.',
                                ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- layar hasil
  Widget _buildResultScreen(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: 'Hasil Sesi',
                  subtitle:
                      '${_shots.length} foto siap dicetak dengan frame ${widget.config.frame.name}.',
                  trailing: StatusBadge(
                    label: 'Retake ${_retakeCount}x',
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: _shots.isEmpty
                      ? const Center(
                          child: Text(
                            'Belum ada foto pada sesi ini.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        )
                      : GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 320,
                            childAspectRatio: 3 / 4,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                          itemCount: _shots.length,
                          itemBuilder: (BuildContext context, int index) {
                            return _ShotCard(
                              shot: _shots[index],
                              index: index,
                              filter: widget.config.filter,
                              frame: widget.config.frame,
                              onRetake: widget.config.enableRetakeButton
                                  ? () => _retakeShot(index)
                                  : null,
                            );
                          },
                        ),
                ),
                const SizedBox(height: 18),
                if (widget.config.apiEnabled) ...<Widget>[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _uploading ||
                              _shots.isEmpty ||
                              (_paid != null && _lastUploadedSessionId != null)
                          ? null
                          : _uploadCurrentSessionToServer,
                      icon: _uploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _lastUploadedSessionId == null
                                  ? Icons.cloud_upload
                                  : Icons.cloud_done,
                            ),
                      label: Text(
                        _uploading
                            ? 'Mengunggah ke server...'
                            : _lastUploadedSessionId == null
                                ? 'Simpan ke Server (Monolith)'
                                : _paid != null
                                    ? 'Tersimpan #$_lastUploadedSessionId'
                                    : 'Tersimpan #$_lastUploadedSessionId – upload ulang',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _resetSession,
                        icon: const Icon(Icons.replay),
                        label: const Text('Sesi Baru'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/filters'),
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('Ganti Filter'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GradientButton(
                        expand: true,
                        label: widget.config.disableAllPrinting
                            ? 'Printing dinonaktifkan'
                            : 'Cetak ke ${widget.config.primaryPrinter}',
                        icon: Icons.print,
                        onPressed: widget.config.disableAllPrinting ||
                                _printing ||
                                _shots.isEmpty
                            ? null
                            : () => _printCurrentSession(
                                  '${_shots.length} foto dikirim ke ${widget.config.primaryPrinter}.',
                                ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Scaffold _buildStartScreen(BuildContext context) {
    final String? backgroundPath = _resolveBackgroundPath();

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _ConfiguredBackground(
            imagePath: backgroundPath,
            fallbackChild: const LandingBackdrop(),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundPath == null
                  ? Colors.transparent
                  : Colors.black.withValues(alpha: 0.08),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: <Widget>[
                    // Align(
                    //   alignment: Alignment.topRight,
                    //   child: Container(
                    //     padding: const EdgeInsets.symmetric(
                    //       horizontal: 28,
                    //       vertical: 26,
                    //     ),
                    //     decoration: BoxDecoration(
                    //       color: Colors.black87,
                    //       borderRadius: BorderRadius.circular(2),
                    //     ),
                    //     child: Text(
                    //       'Mikhael Darren',
                    //       style:
                    //           Theme.of(context).textTheme.labelLarge?.copyWith(
                    //                 color: Colors.white,
                    //                 fontWeight: FontWeight.w700,
                    //               ),
                    //     ),
                    //   ),
                    // ),
                    const Spacer(),
                    LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints c) {
                        // Kartu menyesuaikan lebar layar kecil.
                        final double w =
                            c.maxWidth < 600 ? c.maxWidth : 560.0;
                        return LandingCard(
                          width: w,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _ConfiguredLogo(
                                imagePath: widget.config.customLogoPath,
                                boothName: widget.config.boothName,
                              ),
                              const SizedBox(height: 22),
                              LandingTagline(text: widget.config.boothTagline),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    LandingStartButton(
                      onPressed: () async {
                        // Verifikasi pembayaran (scan QR) sebelum booth jalan.
                        if (!await _ensurePaid() || !mounted) {
                          return;
                        }
                        setState(() {
                          _stage = _BoothStage.frameSelection;
                        });
                      },
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _resolveBackgroundPath() {
    final String? homePagePath = widget.config.customHomePagePath;
    if (_isImagePath(homePagePath)) {
      return homePagePath;
    }

    final String? backgroundPath = widget.config.customBackgroundPath;
    if (_isImagePath(backgroundPath)) {
      return backgroundPath;
    }

    return null;
  }

  Scaffold _buildFrameSelectionScreen(BuildContext context) {
    final String? backgroundPath = _resolveBackgroundPath();

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _ConfiguredBackground(
            imagePath: backgroundPath,
            fallbackChild: const LandingBackdrop(),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundPath == null
                  ? Colors.transparent
                  : Colors.black.withValues(alpha: 0.08),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: <Widget>[
                    // Align(
                    //   alignment: Alignment.topRight,
                    //   child: Container(
                    //     padding: const EdgeInsets.symmetric(
                    //       horizontal: 28,
                    //       vertical: 26,
                    //     ),
                    //     decoration: BoxDecoration(
                    //       color: Colors.black87,
                    //       borderRadius: BorderRadius.circular(2),
                    //     ),
                    //     child: Text(
                    //       'Mikhael Darren',
                    //       style:
                    //           Theme.of(context).textTheme.labelLarge?.copyWith(
                    //                 color: Colors.white,
                    //                 fontWeight: FontWeight.w700,
                    //               ),
                    //     ),
                    //   ),
                    // ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9CDB7).withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Select Your Frame',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                                  color: const Color(0xFF2C2A26),
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: LayoutBuilder(
                        builder:
                            (BuildContext context, BoxConstraints constraints) {
                          final bool stacked = constraints.maxWidth < 1100;

                          final Widget listPanel = Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD9CDB7)
                                        .withValues(alpha: 0.96),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Wrap(
                                          spacing: 10,
                                          runSpacing: 6,
                                          children: <Widget>[
                                            for (final _FrameSource src
                                                in _FrameSource.values)
                                              ChoiceChip(
                                                label: Text(
                                                  '${src.label} (${_countFor(src)})',
                                                ),
                                                selected: _frameSource == src,
                                                onSelected: (_) => setState(
                                                    () => _frameSource = src),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      widget.config.remoteFramesLoading
                                          ? const Padding(
                                              padding: EdgeInsets.all(10),
                                              child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2.5),
                                              ),
                                            )
                                          : TextButton.icon(
                                              onPressed: () =>
                                                  PhotoboothApiService
                                                      .syncFrames(
                                                          widget.config),
                                              icon: const Icon(Icons.sync),
                                              label: const Text('Sync Server'),
                                            ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD9CDB7)
                                          .withValues(alpha: 0.96),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          if (_frameSource !=
                                                  _FrameSource.defaults &&
                                              widget.config.remoteFramesError !=
                                                  null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12),
                                              child: Text(
                                                'Template server gagal dimuat: '
                                                '${widget.config.remoteFramesError}',
                                                style: const TextStyle(
                                                  color: Color(0xFF9B2C2C),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          if (_frameSource ==
                                                  _FrameSource.server &&
                                              widget.config.remoteFrames
                                                  .isEmpty &&
                                              !widget.config
                                                  .remoteFramesLoading)
                                            const Padding(
                                              padding:
                                                  EdgeInsets.only(bottom: 12),
                                              child: Text(
                                                'Belum ada template aktif di server. '
                                                'Buat di dashboard monolith lalu tekan Sync Server.',
                                                style: TextStyle(
                                                  color: Color(0xFF4A443C),
                                                ),
                                              ),
                                            ),
                                          Wrap(
                                        spacing: 16,
                                        runSpacing: 16,
                                        children: _visibleFrames
                                            .map(
                                              (BoothFrameOption frame) =>
                                                  _FrameSelectionCard(
                                                frame: frame,
                                                selected: frame.id ==
                                                    _pendingFrame.id,
                                                onTap: () {
                                                  setState(() {
                                                    _pendingFrame = frame;
                                                  });
                                                },
                                              ),
                                            )
                                            .toList(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );

                          final Widget previewPanel = Expanded(
                            flex: 2,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD9CDB7)
                                    .withValues(alpha: 0.96),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: <Widget>[
                                  Text(
                                    _pendingFrame.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          color: const Color(0xFF2C2A26),
                                          fontWeight: FontWeight.w700,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Click on a frame to see it larger',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: const Color(0xFF4A443C),
                                          fontStyle: FontStyle.italic,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 24),
                                  Expanded(
                                    child: Center(
                                      child: _LargeFramePreview(
                                        frame: _fresh(_pendingFrame),
                                        printMode: _printMode,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 10,
                                    children: <Widget>[
                                      for (final BoothPhotoMode mode
                                          in BoothPhotoMode.values)
                                        ChoiceChip(
                                          label: Text(mode.label),
                                          selected: _printMode == mode,
                                          onSelected: (_) => setState(
                                              () => _printMode = mode),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${_printMode.hint} Pilih '
                                    '${_pendingFrame.uniqueSlotCount(_printMode)} '
                                    'foto dari $kBoothShotsPerSession jepretan.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF4A443C),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF2C2C2C),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                      ),
                                      onPressed: () {
                                        widget.config.setFrame(_pendingFrame);
                                        setState(() {
                                          _stage = _BoothStage.preview;
                                        });
                                      },
                                      child: const Text('Use This Frame'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );

                          return stacked
                              ? Column(
                                  children: <Widget>[
                                    listPanel,
                                    const SizedBox(height: 14),
                                    previewPanel,
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    listPanel,
                                    const SizedBox(width: 14),
                                    previewPanel,
                                  ],
                                );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _countFor(_FrameSource src) {
    switch (src) {
      case _FrameSource.defaults:
        return widget.config.defaultFrames.length;
      case _FrameSource.server:
        return widget.config.remoteFrames.length;
      case _FrameSource.all:
        return widget.config.allFrames.length;
    }
  }

  bool _isImagePath(String? path) {
    if (path == null || path.isEmpty) {
      return false;
    }

    final String lowerPath = path.toLowerCase();
    return lowerPath.endsWith('.png') ||
        lowerPath.endsWith('.jpg') ||
        lowerPath.endsWith('.jpeg') ||
        lowerPath.endsWith('.gif') ||
        lowerPath.endsWith('.bmp') ||
        lowerPath.endsWith('.webp');
  }

  Widget _buildPreview(CameraController controller) {
    Widget preview = CameraPreview(controller);
    preview = applyBoothFilter(preview, widget.config.filter);

    // cover: gambar kamera memenuhi seluruh bingkai (tanpa pita kosong di
    // sisi). Bagian yang berlebih terpotong oleh ClipRRect pembungkusnya.
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: 1000,
        height: 1000 / controller.value.aspectRatio,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translate(widget.config.cropOffsetX * 120,
                widget.config.cropOffsetY * 120)
            ..scale(
                widget.config.mirrorPreview
                    ? -widget.config.cropScale
                    : widget.config.cropScale,
                widget.config.cropScale),
          child: preview,
        ),
      ),
    );
  }
}

class _ZoomBounds {
  const _ZoomBounds({
    required this.minZoomLevel,
    required this.maxZoomLevel,
    required this.isSupported,
  });

  final double minZoomLevel;
  final double maxZoomLevel;
  final bool isSupported;
}

enum _BoothStage {
  landing,
  frameSelection,
  preview,
  compose,
  background,
  filterSelect,
  result,
}

/// Kartu hasil foto di halaman result, lengkap dengan tombol retake.
class _ShotCard extends StatelessWidget {
  const _ShotCard({
    required this.shot,
    required this.index,
    required this.filter,
    required this.frame,
    this.onRetake,
  });

  final BoothShot shot;
  final int index;
  final BoothFilter filter;
  final BoothFrameOption frame;
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (shot.bytes != null) {
      image = Image.memory(shot.bytes!, fit: BoxFit.cover);
    } else if (!kIsWeb && shot.filePath != null) {
      image = Image.file(
        File(shot.filePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Colors.black26,
          child: Center(
            child: Icon(Icons.broken_image_outlined,
                color: AppTheme.textMuted, size: 32),
          ),
        ),
      );
    } else {
      image = const ColoredBox(color: Colors.black26);
    }

    image = applyBoothFilter(image, filter);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: frame.borderColor, width: 4),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            image,
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Foto ${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (onRetake != null)
              Positioned(
                right: 10,
                bottom: 10,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onPressed: onRetake,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retake'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConfiguredBackground extends StatelessWidget {
  const _ConfiguredBackground({
    required this.imagePath,
    required this.fallbackChild,
  });

  final String? imagePath;
  final Widget fallbackChild;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || imagePath == null || imagePath!.isEmpty) {
      return fallbackChild;
    }

    return Image.file(
      File(imagePath!),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallbackChild,
    );
  }
}

class _ConfiguredLogo extends StatelessWidget {
  const _ConfiguredLogo({
    required this.imagePath,
    required this.boothName,
  });

  final String? imagePath;
  final String boothName;

  bool get _hasImage => !kIsWeb && imagePath != null && imagePath!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_hasImage) {
      return Image.file(
        File(imagePath!),
        height: 260,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _FallbackLogo(boothName: boothName),
      );
    }

    return _FallbackLogo(boothName: boothName);
  }
}

/// Asal frame pada layar pilih frame: bawaan Flutter atau template server.
enum _FrameSource {
  all('All'),
  defaults('Default'),
  server('Server');

  const _FrameSource(this.label);
  final String label;
}

class _FrameSelectionCard extends StatelessWidget {
  const _FrameSelectionCard({
    required this.frame,
    required this.selected,
    required this.onTap,
  });

  final BoothFrameOption frame;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF2C2C2C) : const Color(0xFFD6CCBD),
            width: selected ? 3 : 1,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: <Widget>[
            AspectRatio(
              aspectRatio: frame.previewAspect,
              child: _LargeFramePreview(
                frame: frame,
                compact: true,
                printMode: BoothPhotoMode.different,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              frame.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF2C2A26),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Menyisipkan jarak antar item pada Row/Column.
List<Widget> _withGaps(List<Widget> items, double gap) {
  final List<Widget> out = <Widget>[];
  for (int i = 0; i < items.length; i++) {
    out.add(items[i]);
    if (i != items.length - 1) {
      out.add(SizedBox(width: gap, height: gap));
    }
  }
  return out;
}

/// Ukuran maksimum lembar frame (strip / grid) pada layar.
/// Rasio lebar : tinggi SELURUH lembar ber-background. Strip double = dua
/// lembar berdampingan bila desain portrait, bertumpuk bila landscape.
double _backgroundSheetAspect(BoothFrameOption frame, BoothPhotoMode mode) {
  final double one = frame.backgroundAspect;
  final int copies = frame.stripCopies(mode);
  if (copies == 1) return one;
  return one > 1 ? one / copies : one * copies;
}

Size _sheetMaxSize(BoothFrameOption frame, BoothPhotoMode mode) {
  final bool doubled = frame.stripCopies(mode) == 2;
  if (frame.hasBackground) {
    // Lebar mengikuti rasio gambar (lihat [_backgroundSheetAspect]).
    final double total = _backgroundSheetAspect(frame, mode);
    return Size((560 * total).clamp(160.0, 760.0).toDouble(), 600);
  }
  switch (frame.layout) {
    case BoothFrameLayout.stripVertical:
      return Size(doubled ? 440 : 260, frame.slotCount >= 4 ? 580 : 470);
    case BoothFrameLayout.stripHorizontal:
      return Size(560, doubled ? 420 : 230);
    case BoothFrameLayout.gridPortrait:
      return Size(340, frame.slotCount >= 8 ? 600 : 500);
    case BoothFrameLayout.gridLandscape:
      return Size(
        frame.slotCount >= 8 ? 760 : (frame.slotCount >= 6 ? 620 : 480),
        380,
      );
    case BoothFrameLayout.template:
      {
        // Tinggi tetap, lebar mengikuti rasio kanvas template (vertikal ->
        // sempit & tinggi). 540 = tinggi lembar setelah padding/border/judul.
        const double sheetHeight = 540;
        final double one = sheetHeight * frame.canvasAspect + 40;
        final double width = doubled ? one * 2 - 26 : one;
        return Size(width.clamp(160.0, 760.0).toDouble(), 600);
      }
  }
}

/// Menyusun isi lembar frame sesuai layout. [slotBuilder] dipanggil dengan
/// index slot unik, jadi pada mode double dua sel bisa menampilkan foto yang
/// sama.
Widget _buildFrameSheet({
  required BoothFrameOption frame,
  required BoothPhotoMode mode,
  required Widget Function(int source) slotBuilder,
  double gap = 8,
  bool single = false,
}) {
  // Frame ber-background: gambar penuh jadi dasar lembar, foto hanya di area
  // yang diatur dari dashboard. Strip double = dua lembar yang sama.
  if (!single && frame.hasBackground && !frame.isTemplate) {
    // Susunan foto mengikuti BENTUK AREA foto pada desain: area portrait ->
    // foto tersusun tegak, area landscape -> mendatar. Dengan begitu satu
    // desain ("Semua Frame") cocok untuk semua frame, mis. "Spotlight 4x2"
    // di desain portrait tampil sebagai 2 kolom x 4 baris.
    final FrameBackgroundInfo info = frame.background!;
    final bool areaLandscape = info.areaH > 0 &&
        (info.areaW / info.areaH) * frame.backgroundAspect > 1;
    final BoothFrameOption inner = frame.isLandscape == areaLandscape
        ? frame
        : frame.withLayout(frame.layout.transposed);

    Widget one() => _BackgroundSheet(
          frame: frame,
          child: _buildFrameSheet(
            frame: inner,
            mode: mode,
            slotBuilder: slotBuilder,
            gap: gap,
            single: true,
          ),
        );
    if (frame.stripCopies(mode) == 1) return one();
    final List<Widget> copies = <Widget>[
      Expanded(child: one()),
      Expanded(child: one()),
    ];
    // Lembar landscape bertumpuk, lembar portrait berdampingan.
    return frame.backgroundAspect > 1
        ? Column(children: _withGaps(copies, gap))
        : Row(children: _withGaps(copies, gap));
  }

  final List<int> src = frame.cellSources(mode);
  Widget cell(int c) => slotBuilder(src[c]);

  switch (frame.layout) {
    case BoothFrameLayout.stripVertical:
      {
        Widget strip() => Column(
              children: _withGaps(<Widget>[
                for (int i = 0; i < frame.slotCount; i++)
                  Expanded(child: cell(i)),
              ], gap),
            );
        if (single || frame.stripCopies(mode) == 1) {
          return strip();
        }
        return Row(
          children: _withGaps(<Widget>[
            Expanded(child: strip()),
            Expanded(child: strip()),
          ], gap + 6),
        );
      }
    case BoothFrameLayout.stripHorizontal:
      {
        Widget strip() => Row(
              children: _withGaps(<Widget>[
                for (int i = 0; i < frame.slotCount; i++)
                  Expanded(child: cell(i)),
              ], gap),
            );
        if (single || frame.stripCopies(mode) == 1) {
          return strip();
        }
        return Column(
          children: _withGaps(<Widget>[
            Expanded(child: strip()),
            Expanded(child: strip()),
          ], gap + 6),
        );
      }
    case BoothFrameLayout.template:
      {
        Widget sheet() => _TemplateSheet(frame: frame, slotBuilder: cell);
        if (frame.stripCopies(mode) == 1) {
          return sheet();
        }
        return Row(
          children: _withGaps(<Widget>[
            Expanded(child: sheet()),
            Expanded(child: sheet()),
          ], gap + 6),
        );
      }
    case BoothFrameLayout.gridPortrait:
      {
        final int rows = frame.slotCount ~/ 2;
        return Column(
          children: _withGaps(<Widget>[
            for (int r = 0; r < rows; r++)
              Expanded(
                child: Row(
                  children: _withGaps(<Widget>[
                    Expanded(child: cell(r * 2)),
                    Expanded(child: cell(r * 2 + 1)),
                  ], gap + 4),
                ),
              ),
          ], gap),
        );
      }
    case BoothFrameLayout.gridLandscape:
      {
        final int cols = frame.slotCount ~/ 2;
        return Column(
          children: _withGaps(<Widget>[
            for (int r = 0; r < 2; r++)
              Expanded(
                child: Row(
                  children: _withGaps(<Widget>[
                    for (int c = 0; c < cols; c++)
                      Expanded(child: cell(r * cols + c)),
                  ], gap),
                ),
              ),
          ], gap),
        );
      }
  }
}

/// Lembar dengan gambar background penuh (logo, tulisan, hiasan). Foto hanya
/// ditempatkan di dalam kotak area yang diatur dari dashboard.
class _BackgroundSheet extends StatelessWidget {
  const _BackgroundSheet({required this.frame, required this.child});

  final BoothFrameOption frame;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final FrameBackgroundInfo info = frame.background!;
    return Center(
      child: AspectRatio(
        aspectRatio: frame.backgroundAspect,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double w = box.maxWidth;
            final double h = box.maxHeight;
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const ColoredBox(color: Colors.white),
                  Image.network(
                    info.url,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    errorBuilder: (_, Object error, ___) {
                      debugPrint('Gagal memuat background ${info.url}: $error');
                      return const SizedBox.shrink();
                    },
                  ),
                  Positioned(
                    left: w * info.areaX / 100,
                    top: h * info.areaY / 100,
                    width: w * info.areaW / 100,
                    height: h * info.areaH / 100,
                    child: child,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Lembar template dari server: kanvas dengan rasio asli (umumnya strip
/// vertikal), tiap slot diposisikan memakai persen `x/y/w/h` dari
/// `layout_json`, lalu PNG frame ditumpuk di atas foto - persis urutan
/// render di editor PHP (foto dulu, frame terakhir).
class _TemplateSheet extends StatelessWidget {
  const _TemplateSheet({
    required this.frame,
    required this.slotBuilder,
  });

  final BoothFrameOption frame;

  /// Dipanggil dengan index CELL (urutan slot di template).
  final Widget Function(int cell) slotBuilder;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: frame.canvasAspect,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double w = box.maxWidth;
            final double h = box.maxHeight;
            final String? url = frame.imageUrl;
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const ColoredBox(color: Colors.white),
                  for (int i = 0; i < frame.slots.length; i++)
                    Positioned(
                      left: w * frame.slots[i].x / 100,
                      top: h * frame.slots[i].y / 100,
                      width: w * frame.slots[i].w / 100,
                      height: h * frame.slots[i].h / 100,
                      child: slotBuilder(i),
                    ),
                  if (url != null && url.isNotEmpty)
                    IgnorePointer(
                      child: Image.network(
                        url,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LargeFramePreview extends StatelessWidget {
  const _LargeFramePreview({
    required this.frame,
    this.compact = false,
    this.printMode = BoothPhotoMode.different,
  });

  final BoothFrameOption frame;
  final bool compact;
  final BoothPhotoMode printMode;

  @override
  Widget build(BuildContext context) {
    const List<Color> palette = <Color>[
      Color(0xFFD9A8A1),
      Color(0xFF9FB1D0),
      Color(0xFFD8B08A),
      Color(0xFFA88BC6),
      Color(0xFF9DC0A4),
      Color(0xFFD59AA8),
    ];

    final Size sheet = _sheetMaxSize(frame, printMode);
    final bool hugsBackground = frame.hasBackground && !frame.isTemplate;

    final Widget box = Container(
      constraints: (compact || hugsBackground)
          ? null
          : BoxConstraints(
              maxWidth: sheet.width * 0.85,
              maxHeight: sheet.height * 0.85,
            ),
      padding: frame.hasBackground
          ? EdgeInsets.zero
          : EdgeInsets.all(compact ? 8 : 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: frame.hasBackground
            ? null
            : Border.all(color: frame.borderColor, width: compact ? 4 : 6),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: _buildFrameSheet(
        frame: frame,
        mode: printMode,
        gap: compact ? 4 : 8,
        slotBuilder: (int source) => _FrameSlot(
          color: palette[source % palette.length],
          label: '${source + 1}',
        ),
      ),
    );

    if (!hugsBackground) return box;

    // Pas seukuran gambar background (tanpa sisa putih).
    final Widget fitted = AspectRatio(
      aspectRatio: _backgroundSheetAspect(frame, printMode),
      child: box,
    );
    return compact
        ? fitted
        : ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: sheet.width * 0.85,
              maxHeight: sheet.height * 0.85,
            ),
            child: fitted,
          );
  }
}

class _FrameSlot extends StatelessWidget {
  const _FrameSlot({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
              ),
        ),
      ),
    );
  }
}

class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo({required this.boothName});

  final String boothName;

  @override
  Widget build(BuildContext context) {
    return DefaultBoothLogo(boothName: boothName, size: 300);
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Dialog "Kirim ke email?". Controller dimiliki & dibuang oleh State dialog
/// sendiri (bukan dibuang pemanggil sementara animasi tutup masih berjalan).
class _EmailDialog extends StatefulWidget {
  const _EmailDialog({this.initial});

  final String? initial;

  @override
  State<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<_EmailDialog> {
  static final RegExp _pattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  late final TextEditingController _input =
      TextEditingController(text: widget.initial ?? '');
  String? _error;
  bool _closing = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    if (_closing) return;
    _closing = true;
    FocusManager.instance.primaryFocus?.unfocus();
    // Tutup di frame berikutnya, bukan di tengah penanganan event input.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(value);
    });
  }

  void _submit() {
    final String v = _input.text.trim();
    if (!_pattern.hasMatch(v)) {
      setState(() => _error = 'Alamat email tidak valid');
      return;
    }
    _close(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kirim ke email?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Semua foto dan mock hasil strip akan dikirim ke email ini.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _input,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Alamat email',
                hintText: 'nama@email.com',
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _close,
          child: const Text('Lewati'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_rounded),
          label: const Text('Kirim'),
        ),
      ],
    );
  }
}

/// Label di layar kamera saat retake: menunjukkan slot yang sedang diulang.
class _RetakePill extends StatelessWidget {
  const _RetakePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white38),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 18, color: AppTheme.accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GridPainter(),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;

    for (int step = 1; step < 3; step++) {
      final double dx = size.width * step / 3;
      final double dy = size.height * step / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Preview strip yang menampilkan semua slot foto sesuai `frame.slotCount`.
/// Digunakan di stage compose (dengan tap slot) dan stage filter (read-only
/// dengan matrix filter ter-apply ke seluruh strip).
class _StripPreview extends StatelessWidget {
  const _StripPreview({
    required this.frame,
    required this.printMode,
    required this.shots,
    required this.assignments,
    required this.selectedSlot,
    this.multiSelected = const <int>{},
    this.filter = BoothFilter.none,
    this.showBadges = true,
    required this.onSlotTap,
  });

  final BoothFrameOption frame;
  final BoothPhotoMode printMode;
  final List<BoothShot> shots;
  final List<int?> assignments;
  final int? selectedSlot;

  /// Slot yang dipilih untuk retake banyak foto (mode bulk).
  final Set<int> multiSelected;
  final BoothFilter filter;

  /// Nomor slot (1, 2, ...) di pojok foto; dimatikan saat memotret mock.
  final bool showBadges;
  final ValueChanged<int>? onSlotTap;

  @override
  Widget build(BuildContext context) {
    final Size sheet = _sheetMaxSize(frame, printMode);
    final bool hugsBackground = frame.hasBackground && !frame.isTemplate;

    final Widget box = Container(
      constraints: hugsBackground
          ? null
          : BoxConstraints(maxWidth: sheet.width, maxHeight: sheet.height),
      padding: frame.hasBackground
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(14, 14, 14, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: frame.hasBackground
            ? null
            : Border.all(color: frame.borderColor, width: 6),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: _buildFrameSheet(
        frame: frame,
        mode: printMode,
        slotBuilder: (int source) => _buildSlot(context, source),
      ),
    );

    if (!hugsBackground) return box;

    // Wadah dipas persis seukuran gambar background (tidak ada sisa putih di
    // kiri/kanan walau tinggi layar berubah).
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: sheet.width, maxHeight: sheet.height),
      child: AspectRatio(
        aspectRatio: _backgroundSheetAspect(frame, printMode),
        child: box,
      ),
    );
  }

  Widget _buildSlot(BuildContext context, int slotIndex) {
    final int? shotIndex =
        slotIndex < assignments.length ? assignments[slotIndex] : null;
    final BoothShot? shot = (shotIndex != null && shotIndex < shots.length)
        ? shots[shotIndex]
        : null;
    final bool selected = selectedSlot == slotIndex;
    final bool bulk = multiSelected.contains(slotIndex);

    Widget content;
    if (shot == null) {
      content = ColoredBox(
        color: const Color(0xFFEDECE7),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.add_photo_alternate_outlined,
                color: Color(0xFF9C9689),
                size: 26,
              ),
              const SizedBox(height: 4),
              Text(
                'Slot ${slotIndex + 1}',
                style: const TextStyle(
                  color: Color(0xFF9C9689),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      Widget image;
      if (shot.bytes != null) {
        image = Image.memory(shot.bytes!, fit: BoxFit.cover);
      } else if (!kIsWeb && shot.filePath != null) {
        image = Image.file(
          File(shot.filePath!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: Colors.black26,
            child: Center(
              child: Icon(Icons.broken_image_outlined,
                  color: AppTheme.textMuted, size: 24),
            ),
          ),
        );
      } else {
        image = const ColoredBox(color: Colors.black26);
      }
      content = applyBoothFilter(image, filter);
    }

    return GestureDetector(
      onTap: onSlotTap == null ? null : () => onSlotTap!(slotIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: bulk
                ? AppTheme.danger
                : selected
                    ? frame.borderColor
                    : const Color(0x22000000),
            width: (selected || bulk) ? 3 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              content,
              if (showBadges)
                Positioned(
                  left: 6,
                  top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${slotIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (bulk)
                Positioned.fill(
                  child: ColoredBox(
                    color: AppTheme.danger.withValues(alpha: 0.18),
                  ),
                ),
              if (bulk)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.refresh, size: 10, color: Colors.white),
                        SizedBox(width: 3),
                        Text(
                          'RETAKE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (selected && !bulk)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: frame.borderColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'DIPILIH',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu thumbnail foto di tray bawah pada layar compose.
class _ShotThumb extends StatelessWidget {
  const _ShotThumb({
    required this.shot,
    required this.index,
    required this.usedInSlot,
    required this.enabled,
    required this.onTap,
  });

  final BoothShot shot;
  final int index;

  /// Nomor slot (1-based) tempat foto ini terpasang, atau null bila belum.
  final int? usedInSlot;

  /// Apakah thumbnail bisa ditap (yaitu ada slot yang sedang terpilih).
  final bool enabled;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (shot.bytes != null) {
      image = Image.memory(shot.bytes!, fit: BoxFit.cover);
    } else if (!kIsWeb && shot.filePath != null) {
      image = Image.file(
        File(shot.filePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26),
      );
    } else {
      image = const ColoredBox(color: Colors.black26);
    }

    return Opacity(
      opacity: enabled ? 1.0 : 0.65,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: usedInSlot != null
                  ? const Color(0xFF2C2A26)
                  : const Color(0x33000000),
              width: usedInSlot != null ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                image,
                Positioned(
                  left: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Foto ${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (usedInSlot != null)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Slot $usedInSlot',
                        style: const TextStyle(
                          color: Color(0xFF2C2A26),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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

/// Kartu di carousel filter (layar filterSelect).
/// Kartu filter ala Instagram: thumbnail foto asli yang sudah terfilter + nama.
class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.filter,
    required this.selected,
    required this.onTap,
    this.sample,
  });

  final BoothFilter filter;
  final bool selected;
  final VoidCallback onTap;

  /// Foto contoh (belum terfilter). Null -> tampilkan gradient warna filter.
  final Widget? sample;

  @override
  Widget build(BuildContext context) {
    final Widget thumb = sample != null
        ? applyBoothFilter(sample!, filter)
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  filter.accentColor.withValues(alpha: 0.9),
                  filter.accentColor.withValues(alpha: 0.35),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 88,
        child: Column(
          children: <Widget>[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? filter.accentColor : Colors.white24,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.expand(child: thumb),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filter.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu pilihan background: thumbnail gambar + nama. [info] null = "Default"
/// (tampilan frame bawaan, tanpa gambar background).
class _DesignCard extends StatelessWidget {
  const _DesignCard({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.info,
  });

  final String label;
  final FrameBackgroundInfo? info;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final FrameBackgroundInfo? design = info;
    final Widget thumb = design == null
        ? const ColoredBox(
            color: Colors.white,
            child: Center(
              child: Icon(Icons.crop_portrait, color: Color(0xFFB0A89A)),
            ),
          )
        : Image.network(
            design.url,
            fit: BoxFit.cover,
            cacheWidth: 300,
            gaplessPlayback: true,
            errorBuilder: (_, Object error, ___) {
              debugPrint('Gagal memuat desain ${design.url}: $error');
              return const ColoredBox(
                color: Colors.black26,
                child: Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: AppTheme.textMuted),
                ),
              );
            },
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 96,
        child: Column(
          children: <Widget>[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? accent : Colors.white24,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.expand(child: thumb),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
