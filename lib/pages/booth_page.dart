import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
    if (_useCanon) {
      setState(() {});
      return;
    }

    if (_activeCameraId != widget.config.preferredCameraId ||
        _activePreset != widget.config.resolutionPreset) {
      _initializeCamera();
    } else {
      setState(() {});
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

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

      await _controller?.dispose();
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

      final List<double>? matrix = widget.config.filter.matrix;
      if (matrix != null) {
        image = ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix),
          child: image,
        );
      }

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

  /// Retake satu foto tertentu dari halaman hasil.
  Future<void> _retakeShot(int index) async {
    if (!widget.config.enableRetakeButton) {
      return;
    }
    if (!widget.config.unlimitedRetakes &&
        _retakeCount >= widget.config.retakeLimitPerPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Batas retake tercapai (${widget.config.retakeLimitPerPhoto}x).'),
        ),
      );
      return;
    }

    setState(() {
      _stage = _BoothStage.preview;
      _sessionRunning = true;
      _retakeCount += 1;
    });

    await _runCountdown(kBoothShotDelaySeconds);
    final BoothShot? shot = await _captureOne();
    if (!mounted) {
      return;
    }

    setState(() {
      if (shot != null && index < _shots.length) {
        _shots[index] = shot;
      } else if (shot != null) {
        _shots.add(shot);
      }
      _sessionRunning = false;
      // Kembali ke layar compose supaya user langsung lihat hasil retake di
      // dalam frame mockup.
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

  /// Pindah ke frame lain di layar compose. Berusaha mempertahankan urutan
  /// assignment sebelumnya; kelebihan slot dipotong, slot tambahan kosong.
  void _switchComposeFrame(BoothFrameOption frame) {
    final List<int?> previous = List<int?>.from(_slotAssignments);
    final int count = frame.uniqueSlotCount(_printMode);
    final List<int?> next = List<int?>.filled(count, null);

    // Salin assignment lama sebanyak mungkin.
    final int copy = count < previous.length ? count : previous.length;
    for (int i = 0; i < copy; i++) {
      next[i] = previous[i];
    }

    // Slot tambahan dibiarkan kosong; customer mengisinya dari tray.
    setState(() {
      _activeFrame = frame;
      _slotAssignments = next;
      _selectedSlot = _firstEmptySlot();
    });
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
      _selectedSlot = _firstEmptySlot();
    });
  }

  /// Tap sebuah slot untuk memilihnya (highlight); tap lagi untuk unselect.
  void _handleSlotTap(int slotIndex) {
    setState(() {
      _selectedSlot = _selectedSlot == slotIndex ? null : slotIndex;
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
      _activeFrame = widget.config.frame;
      _activeFilter = widget.config.filter;
      _captureError = null;
      _sessionRunning = false;
      _uploading = false;
      _lastUploadedSessionId = null;
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
  Future<void> _uploadCurrentSessionToServer() async {
    if (_uploading || _shots.isEmpty) return;

    final PhotoboothApiService? svc =
        PhotoboothApiService.fromConfig(widget.config);
    if (svc == null) {
      _showApiInactive();
      return;
    }

    setState(() => _uploading = true);

    try {
      // 1) Tentukan template di server. Frame yang dipilih dari /api/templates
      //    sudah membawa id-nya; frame bawaan Flutter dicocokkan berdasarkan
      //    jumlah slot seperti sebelumnya.
      int? frameId = _activeFrame.remoteId;
      if (frameId == null) {
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

      if (frameId == null) {
        _showSnack(
          'Tidak ada template aktif di server. Buat dulu di dashboard monolith.',
        );
        return;
      }

      // 2) Siapkan payload photos[]. Tanpa pembayaran, server mewajibkan
      //    jumlah foto == jumlah slot template, jadi kirim foto sesuai urutan
      //    slot. Sesi berbayar mengirim semua jepretan (dibatasi paket).
      final bool slotOrdered = _activeFrame.isRemote && _paid == null;
      final List<BoothShot> source = slotOrdered
          ? <BoothShot>[
              for (final int? a in _slotAssignments)
                if (a != null && a < _shots.length) _shots[a],
            ]
          : _shots;
      if (slotOrdered && source.length != _activeFrame.slotCount) {
        _showSnack(
          'Isi semua ${_activeFrame.slotCount} slot template dulu sebelum upload.',
        );
        return;
      }

      final List<PhotoUpload> uploads = <PhotoUpload>[];
      for (int i = 0; i < source.length; i++) {
        final BoothShot shot = source[i];
        final Uint8List? bytes = shot.bytes;
        final String? path = shot.filePath;
        final String filename =
            'shot_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        if (bytes != null) {
          uploads.add(PhotoUpload(filename: filename, bytes: bytes));
        } else if (path != null && !kIsWeb) {
          uploads.add(PhotoUpload(filename: filename, filePath: path));
        }
      }

      if (uploads.isEmpty) {
        _showSnack('Tidak ada foto yang bisa dibaca untuk diupload.');
        return;
      }

      // 3) Simpan ke server.
      //    - Sudah bayar: foto masuk ke sesi yang dibuat saat pembayaran
      //      (POST /photo-sessions/{id}/photos + PUT metadata). Server menolak
      //      sesi yang belum paid dan membatasi jumlah foto sesuai paket.
      //    - Tanpa pembayaran (mode lama): POST /api/photo-sessions.
      final PaidSession? paid = _paid;
      final PhotoSessionDto session;
      if (paid != null) {
        if (!_paidPhotosSent) {
          await svc.addPhotos(sessionId: paid.sessionId, photos: uploads);
          _paidPhotosSent = true;
        }
        session = await svc.updateSession(
          sessionId: paid.sessionId,
          photoFrameId: frameId,
          filter: filterToApiString(_activeFilter),
          layout: _activeFrame.id,
          takenAt: DateTime.now(),
        );
      } else {
        session = await svc.createSession(
          boothId: widget.config.apiBoothId,
          photoFrameId: frameId,
          photos: uploads,
          filter: filterToApiString(_activeFilter),
          layout: _activeFrame.id,
          takenAt: DateTime.now(),
        );
      }

      if (!mounted) return;
      setState(() => _lastUploadedSessionId = session.id);
      _showSnack(
        'Sesi ${session.sessionCode} tersimpan ke server (id #${session.id}).',
      );
    } on ApiException catch (e) {
      _showSnack('Upload gagal: ${e.message}');
    } catch (e) {
      _showSnack('Upload gagal: $e');
    } finally {
      svc.close();
      if (mounted) setState(() => _uploading = false);
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
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------ layar capture
  /// Teks arahan untuk customer selama sesi berjalan.
  String get _capturePrompt {
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
                              child: CaptureProgressPill(
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
                  subtitle: selected == null
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
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.config.allFrames.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (BuildContext ctx, int i) {
                      final BoothFrameOption f = widget.config.allFrames[i];
                      return _FrameChip(
                        frame: f,
                        selected: f.id == _activeFrame.id,
                        onTap: () => _switchComposeFrame(f),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: <Widget>[
                    for (final BoothPhotoMode mode in BoothPhotoMode.values)
                      ChoiceChip(
                        label: Text(mode.label),
                        selected: _printMode == mode,
                        onSelected: (_) => _switchPrintMode(mode),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Center(
                    child: _StripPreview(
                      frame: _fresh(_activeFrame),
                      printMode: _printMode,
                      shots: _shots,
                      assignments: _slotAssignments,
                      selectedSlot: _selectedSlot,
                      filterMatrix: null,
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
                        onPressed: selectionHasPhoto &&
                                widget.config.enableRetakeButton
                            ? () => _retakeShot(
                                _slotAssignments[selected]!)
                            : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retake foto'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GradientButton(
                        expand: true,
                        label: allFilled
                            ? 'Lanjut ke Filter'
                            : 'Isi semua slot dulu',
                        icon: Icons.auto_fix_high,
                        onPressed: allFilled
                            ? () => setState(
                                () => _stage = _BoothStage.filterSelect)
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
                    child: _StripPreview(
                      frame: _fresh(_activeFrame),
                      printMode: _printMode,
                      shots: _shots,
                      assignments: _slotAssignments,
                      selectedSlot: null,
                      filterMatrix: _activeFilter.matrix,
                      onSlotTap: null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 130,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: BoothFilter.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (BuildContext ctx, int i) {
                      final BoothFilter f = BoothFilter.values[i];
                      return _FilterCard(
                        filter: f,
                        selected: f == _activeFilter,
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
                        onPressed: () => setState(
                            () => _stage = _BoothStage.compose),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Kembali Compose'),
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
                        onPressed: widget.config.disableAllPrinting
                            ? null
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Strip ${_activeFrame.name} + filter ${_activeFilter.label} dikirim ke ${widget.config.primaryPrinter}.'),
                                  ),
                                );
                              },
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
                              filterMatrix: widget.config.filter.matrix,
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
                                _shots.isEmpty
                            ? null
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '${_shots.length} foto dikirim ke ${widget.config.primaryPrinter}.'),
                                  ),
                                );
                              },
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
            fallbackChild: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[Color(0xFF214F7D), Color(0xFF1B3D60)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: const SizedBox.expand(),
            ),
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
                    Container(
                      width: 560,
                      constraints:
                          const BoxConstraints(maxWidth: double.infinity),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _ConfiguredLogo(
                            imagePath: widget.config.customLogoPath,
                            boothName: widget.config.boothName,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.config.boothTagline,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: const Color(0xFF2A2A2A),
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2C2C2C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 42,
                          vertical: 18,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        textStyle:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      onPressed: () async {
                        // Verifikasi pembayaran (scan QR) sebelum booth jalan.
                        if (!await _ensurePaid() || !mounted) {
                          return;
                        }
                        setState(() {
                          _stage = _BoothStage.frameSelection;
                        });
                      },
                      child: const Text('Tap to Start!'),
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
            fallbackChild: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[Color(0xFF214F7D), Color(0xFF1B3D60)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: const SizedBox.expand(),
            ),
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
    final List<double>? matrix = widget.config.filter.matrix;
    if (matrix != null) {
      preview = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: preview,
      );
    }

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
  filterSelect,
  result,
}

/// Kartu hasil foto di halaman result, lengkap dengan tombol retake.
class _ShotCard extends StatelessWidget {
  const _ShotCard({
    required this.shot,
    required this.index,
    required this.filterMatrix,
    required this.frame,
    this.onRetake,
  });

  final BoothShot shot;
  final int index;
  final List<double>? filterMatrix;
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

    if (filterMatrix != null) {
      image = ColorFiltered(
        colorFilter: ColorFilter.matrix(filterMatrix!),
        child: image,
      );
    }

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
Size _sheetMaxSize(BoothFrameOption frame, BoothPhotoMode mode) {
  final bool doubled = frame.stripCopies(mode) == 2;
  if (frame.hasBackground) {
    // Lebar mengikuti rasio gambar; strip double = dua lembar berdampingan
    // (vertikal) atau bertumpuk (horizontal).
    final double one = frame.backgroundAspect;
    final double total = !doubled
        ? one
        : (frame.isHorizontal ? one / 2 : one * 2);
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
  bool showCaptions = true,
  double gap = 8,
  bool single = false,
}) {
  // Frame ber-background: gambar penuh jadi dasar lembar, foto hanya di area
  // yang diatur dari dashboard. Strip double = dua lembar yang sama.
  if (!single && frame.hasBackground && !frame.isTemplate) {
    Widget one() => _BackgroundSheet(
          frame: frame,
          child: _buildFrameSheet(
            frame: frame,
            mode: mode,
            slotBuilder: slotBuilder,
            showCaptions: showCaptions,
            gap: gap,
            single: true,
          ),
        );
    if (frame.stripCopies(mode) == 1) return one();
    final List<Widget> copies = <Widget>[
      Expanded(child: one()),
      Expanded(child: one()),
    ];
    return frame.isHorizontal
        ? Column(children: _withGaps(copies, gap))
        : Row(children: _withGaps(copies, gap));
  }

  final List<int> src = frame.cellSources(mode);
  Widget cell(int c) => slotBuilder(src[c]);

  const TextStyle captionStyle = TextStyle(
    color: Color(0xFF656565),
    fontSize: 9,
    fontWeight: FontWeight.w600,
    height: 1.15,
  );

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
        Widget captioned(int c) {
          final String caption = frame.captionFor(src[c]);
          return Row(
            children: <Widget>[
              Expanded(child: cell(c)),
              if (showCaptions && caption.isNotEmpty) ...<Widget>[
                const SizedBox(width: 4),
                SizedBox(
                  width: 46,
                  child: Text(
                    caption,
                    style: captionStyle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          );
        }

        return Column(
          children: _withGaps(<Widget>[
            for (int r = 0; r < rows; r++)
              Expanded(
                child: Row(
                  children: _withGaps(<Widget>[
                    Expanded(child: captioned(r * 2)),
                    Expanded(child: captioned(r * 2 + 1)),
                  ], gap + 4),
                ),
              ),
          ], gap),
        );
      }
    case BoothFrameLayout.gridLandscape:
      {
        final int cols = frame.slotCount ~/ 2;
        String rowCaption(int r) => <String>[
              for (int c = 0; c < cols; c++) frame.captionFor(src[r * cols + c]),
            ].where((String t) => t.isNotEmpty).join('\n');

        return Column(
          children: _withGaps(<Widget>[
            for (int r = 0; r < 2; r++)
              Expanded(
                child: Row(
                  children: <Widget>[
                    if (showCaptions) ...<Widget>[
                      SizedBox(
                        width: 84,
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: Text(
                            rowCaption(r),
                            textAlign: TextAlign.right,
                            style: captionStyle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Row(
                        children: _withGaps(<Widget>[
                          for (int c = 0; c < cols; c++)
                            Expanded(child: cell(r * cols + c)),
                        ], gap),
                      ),
                    ),
                  ],
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
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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

    return Container(
      constraints: compact
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
        showCaptions: !compact,
        gap: compact ? 4 : 8,
        slotBuilder: (int source) => _FrameSlot(
          color: palette[source % palette.length],
          label: '${source + 1}',
        ),
      ),
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
    return Container(
      width: 320,
      height: 320,
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            boothName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: const Color(0xFFFFC156),
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
      ),
    );
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
    required this.filterMatrix,
    required this.onSlotTap,
  });

  final BoothFrameOption frame;
  final BoothPhotoMode printMode;
  final List<BoothShot> shots;
  final List<int?> assignments;
  final int? selectedSlot;
  final List<double>? filterMatrix;
  final ValueChanged<int>? onSlotTap;

  @override
  Widget build(BuildContext context) {
    final Size sheet = _sheetMaxSize(frame, printMode);

    return Container(
      constraints: BoxConstraints(maxWidth: sheet.width, maxHeight: sheet.height),
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
      child: Column(
        children: <Widget>[
          Expanded(
            child: _buildFrameSheet(
              frame: frame,
              mode: printMode,
              slotBuilder: (int source) => _buildSlot(context, source),
            ),
          ),
          if (!frame.hasBackground) const SizedBox(height: 8),
          if (!frame.hasBackground)
          Text(
            'The Mystery Photo Booth',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF656565),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
          ),
        ],
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
      if (filterMatrix != null) {
        image = ColorFiltered(
          colorFilter: ColorFilter.matrix(filterMatrix!),
          child: image,
        );
      }
      content = image;
    }

    return GestureDetector(
      onTap: onSlotTap == null ? null : () => onSlotTap!(slotIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? frame.borderColor : const Color(0x22000000),
            width: selected ? 3 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              content,
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
              if (selected)
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

/// Chip untuk mengganti frame aktif di layar compose.
class _FrameChip extends StatelessWidget {
  const _FrameChip({
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
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? frame.borderColor : const Color(0xFFD6CCBD),
            width: selected ? 2.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: frame.borderColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            if (frame.isRemote) ...<Widget>[
              const SizedBox(width: 6),
              const Icon(Icons.cloud_done_outlined,
                  size: 14, color: Color(0xFF7A7266)),
            ],
            const SizedBox(width: 8),
            Text(
              frame.name,
              style: const TextStyle(
                color: Color(0xFF2C2A26),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${frame.slotCount} foto',
              style: const TextStyle(
                color: Color(0xFF7A7266),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final BoothFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? filter.accentColor : const Color(0xFFD6CCBD),
            width: selected ? 3 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      filter.accentColor.withValues(alpha: 0.85),
                      filter.accentColor.withValues(alpha: 0.35),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              filter.label,
              style: const TextStyle(
                color: Color(0xFF2C2A26),
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              filter.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF7A7266),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
