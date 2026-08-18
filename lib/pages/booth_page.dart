import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/booth_models.dart';
import '../services/canon_camera_service.dart';
import '../state/photo_booth_config.dart';
import '../theme/app_theme.dart';

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

  // --- state sesi capture ---
  final List<BoothShot> _shots = <BoothShot>[];
  int _countdown = 0;
  bool _sessionRunning = false;
  bool _flashOn = false;
  int _retakeCount = 0;
  String? _captureError;

  @override
  void initState() {
    super.initState();
    _pendingFrame = widget.config.frame;
    _stage = widget.config.enableTapToStartOverlayScreen
        ? _BoothStage.landing
        : _BoothStage.frameSelection;
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
        fit: BoxFit.contain,
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

    setState(() {
      _sessionRunning = true;
      _captureError = null;
      _shots.clear();
      _retakeCount = 0;
    });

    final int total = widget.config.photosPerSession;
    for (int index = 0; index < total; index++) {
      final int seconds = index == 0
          ? widget.config.firstPhotoCountdownSeconds
          : widget.config.countdownSeconds;

      await _runCountdown(seconds);
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
      _stage = _BoothStage.result;
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

    await _runCountdown(widget.config.countdownSeconds);
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
      _stage = _BoothStage.result;
    });
  }

  void _resetSession() {
    setState(() {
      _shots.clear();
      _countdown = 0;
      _retakeCount = 0;
      _captureError = null;
      _sessionRunning = false;
      _stage = widget.config.enableTapToStartOverlayScreen
          ? _BoothStage.landing
          : _BoothStage.frameSelection;
    });
  }

  // ------------------------------------------------------------ layar capture
  Widget _buildCaptureScreen(BuildContext context) {
    final int total = widget.config.photosPerSession;
    final int taken = _shots.length;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconButton.filledTonal(
                      onPressed: _sessionRunning
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.config.boothName,
                            style:
                                Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                          ),
                          Text(
                            _sessionRunning
                                ? 'Sesi berjalan \u2014 foto ${taken + 1} dari $total'
                                : 'Siap memulai sesi foto',
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
                      onPressed: _sessionRunning ? null : _bootCamera,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Reload kamera',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: widget.config.frame.borderColor,
                          width: 6,
                        ),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusXl),
                        gradient: LinearGradient(
                          colors: widget.config.frame.gradient,
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          _buildLiveSource(context),
                          if (widget.config.showGrid) const _GridOverlay(),
                          if (_flashOn)
                            const ColoredBox(color: Colors.white),
                          if (_countdown > 0)
                            _CountdownOverlay(value: _countdown),
                          Positioned(
                            left: 18,
                            top: 18,
                            child: _ShotProgress(total: total, taken: taken),
                          ),
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
                                    text: widget.config.frame.name,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _InfoPill(
                                    icon: Icons.timer,
                                    text: '${widget.config.countdownSeconds}s',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                        onPressed: _sessionRunning
                            ? null
                            : () => Navigator.of(context).pushNamed('/canon'),
                        icon: const Icon(Icons.camera),
                        label: const Text('Canon Setup'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _sessionRunning
                            ? null
                            : () => Navigator.of(context).pushNamed('/settings'),
                        icon: const Icon(Icons.settings),
                        label: const Text('Settings'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GradientButton(
                        expand: true,
                        label: _sessionRunning
                            ? 'Mengambil foto...'
                            : 'Mulai Capture ($total foto)',
                        icon: Icons.camera_alt_rounded,
                        onPressed: _sessionRunning ? null : _startSession,
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
                      onPressed: () {
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
                                  child: const Align(
                                    alignment: Alignment.centerLeft,
                                    child: _FrameCategoryChip(label: 'All'),
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
                                      child: Wrap(
                                        spacing: 16,
                                        runSpacing: 16,
                                        children: kFrameOptions
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
                                          frame: _pendingFrame),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
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

    return FittedBox(
      fit: BoxFit.contain,
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
  result,
}

/// Angka countdown besar di tengah live view.
class _CountdownOverlay extends StatelessWidget {
  const _CountdownOverlay({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.35),
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: ValueKey<int>(value),
          tween: Tween<double>(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          builder: (BuildContext context, double scale, Widget? child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: 168,
            height: 168,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppTheme.accentGradient,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.45),
                  blurRadius: 60,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: Text(
              '$value',
              style: const TextStyle(
                fontSize: 86,
                fontWeight: FontWeight.w900,
                color: Color(0xFF17130A),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Indikator titik untuk menunjukkan progres jumlah foto.
class _ShotProgress extends StatelessWidget {
  const _ShotProgress({required this.total, required this.taken});

  final int total;
  final int taken;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$taken/$total',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 10),
          ...List<Widget>.generate(
            total,
            (int index) => Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index < taken ? AppTheme.accent : Colors.white24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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

class _FrameCategoryChip extends StatelessWidget {
  const _FrameCategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
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
              aspectRatio: 0.78,
              child: _LargeFramePreview(frame: frame, compact: true),
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

class _LargeFramePreview extends StatelessWidget {
  const _LargeFramePreview({
    required this.frame,
    this.compact = false,
  });

  final BoothFrameOption frame;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool horizontal = frame.id == 'minimal-slate';
    final List<Color> palette = <Color>[
      const Color(0xFFD9A8A1),
      const Color(0xFF9FB1D0),
      const Color(0xFFD8B08A),
      const Color(0xFFA88BC6),
      const Color(0xFF9DC0A4),
      const Color(0xFFD59AA8),
    ];

    return Container(
      width: compact ? null : 320,
      constraints: compact
          ? null
          : BoxConstraints(
              maxWidth: horizontal ? 360 : 250,
              maxHeight: horizontal ? 230 : 420,
            ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: frame.borderColor, width: compact ? 4 : 6),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: horizontal
          ? Column(
              children: <Widget>[
                const SizedBox(height: 6),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            const _FrameTextBlock(),
                            const _FrameTextBlock(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 6,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemBuilder: (BuildContext context, int index) {
                            return _FrameSlot(
                              color: palette[index],
                              label: '${index + 1}',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: <Widget>[
                Expanded(
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 6,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemBuilder: (BuildContext context, int index) {
                      return _FrameSlot(
                        color: palette[index],
                        label: '${index + 1}',
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                const Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _FrameTextBlock(),
                    _FrameTextBlock(),
                    _FrameTextBlock(),
                  ],
                ),
              ],
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

class _FrameTextBlock extends StatelessWidget {
  const _FrameTextBlock();

  @override
  Widget build(BuildContext context) {
    return Text(
      'The Mystery\nPhoto Booth',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: const Color(0xFF656565),
            fontWeight: FontWeight.w600,
            height: 1.2,
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
        color: Colors.black45,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
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
