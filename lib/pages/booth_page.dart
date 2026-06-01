import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/booth_models.dart';
import '../state/photo_booth_config.dart';

class BoothPage extends StatefulWidget {
  const BoothPage({
    super.key,
    required this.config,
  });

  final PhotoBoothConfig config;

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

  @override
  void initState() {
    super.initState();
    _pendingFrame = widget.config.frame;
    _stage = widget.config.enableTapToStartOverlayScreen
        ? _BoothStage.landing
        : _BoothStage.frameSelection;
    widget.config.addListener(_handleConfigChanged);
    _initializeCamera();
  }

  @override
  void dispose() {
    widget.config.removeListener(_handleConfigChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _handleConfigChanged() {
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

    final CameraController? controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Booth'),
        actions: <Widget>[
          IconButton(
            onPressed: _initializeCamera,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: widget.config.frame.borderColor, width: 8),
                    gradient:
                        LinearGradient(colors: widget.config.frame.gradient),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (_error != null)
                        _StatusMessage(
                          icon: Icons.error_outline,
                          title: 'Camera unavailable',
                          message: _error!,
                        )
                      else if (controller == null ||
                          !controller.value.isInitialized)
                        const _StatusMessage(
                          icon: Icons.videocam_off,
                          title: 'Camera not initialized',
                          message:
                              'Open Settings to choose another camera or retry.',
                        )
                      else
                        _buildPreview(controller),
                      if (widget.config.showGrid) const _GridOverlay(),
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
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
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
                  child: FilledButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Capture flow placeholder ready for integration.')),
                      );
                    },
                    icon: const Icon(Icons.camera),
                    label: const Text('Start Capture'),
                  ),
                ),
              ],
            ),
          ],
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
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.previewSize?.height ?? 1080,
        height: controller.value.previewSize?.width ?? 1920,
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
    if (imagePath == null || imagePath!.isEmpty) {
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

  bool get _hasImage => imagePath != null && imagePath!.isNotEmpty;

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
