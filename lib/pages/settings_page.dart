import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/booth_models.dart';
import '../state/photo_booth_config.dart';
import '../utils/file_picker_helper.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.config,
  });

  final PhotoBoothConfig config;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<String> _tabs = <String>[
    'Camera',
    'Printer',
    'Timer',
    'Payment',
    'Multi Print Discount',
    'Extra Print',
    'General',
    'Transaction',
    'License',
  ];

  List<CameraDescription> _cameras = const <CameraDescription>[];
  CameraController? _previewController;
  bool _loadingDevices = true;
  bool _loadingPreview = true;
  String _activeTab = 'Camera';
  String? _deviceError;
  String? _previewError;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 4.0;
  bool _zoomSupported = true;
  late final TextEditingController _photoCountController;

  @override
  void initState() {
    super.initState();
    _photoCountController = TextEditingController(
      text: widget.config.photoCountOverride?.toString() ?? '',
    );
    _loadCameras();
  }

  @override
  void dispose() {
    _photoCountController.dispose();
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _loadCameras() async {
    setState(() {
      _loadingDevices = true;
      _deviceError = null;
    });

    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (!mounted) {
        return;
      }

      setState(() {
        _cameras = cameras;
      });

      if (cameras.isNotEmpty && widget.config.preferredCameraId == null) {
        final CameraDescription firstCamera = cameras.first;
        widget.config.setPreferredCamera(
          id: firstCamera.name,
          name: firstCamera.lensDirection.name,
        );
      }

      await _initializePreview();
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceError = error.description ?? error.code;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDevices = false;
        });
      }
    }
  }

  Future<void> _initializePreview() async {
    setState(() {
      _loadingPreview = true;
      _previewError = null;
    });

    try {
      if (_cameras.isEmpty) {
        throw StateError('Select a camera to see live preview');
      }

      final CameraDescription selectedCamera = _resolveSelectedCamera();
      final CameraController controller = CameraController(
        selectedCamera,
        widget.config.resolutionPreset,
        enableAudio: false,
      );

      await _previewController?.dispose();
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
        _previewController = controller;
        _minZoomLevel = minZoomLevel;
        _maxZoomLevel = maxZoomLevel;
        _zoomSupported = zoomBounds.isSupported;
      });

      if (appliedZoom != widget.config.cameraZoomLevel) {
        widget.config.setCameraZoomLevel(appliedZoom);
      }
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _previewError = error.description ?? error.code;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _previewError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPreview = false;
        });
      }
    }
  }

  CameraDescription _resolveSelectedCamera() {
    return _cameras.firstWhere(
      (CameraDescription camera) =>
          camera.name == widget.config.preferredCameraId,
      orElse: () => _cameras.first,
    );
  }

  Future<void> _updateCamera(CameraDescription camera) async {
    widget.config.setPreferredCamera(
      id: camera.name,
      name: camera.lensDirection.name,
    );
    await _initializePreview();
  }

  Future<void> _updateResolution(ResolutionPreset preset) async {
    widget.config.setResolutionPreset(preset);
    await _initializePreview();
  }

  Future<void> _updateZoom(double value) async {
    if (!_zoomSupported) {
      if (widget.config.cameraZoomLevel != _minZoomLevel) {
        widget.config.setCameraZoomLevel(_minZoomLevel);
      }
      return;
    }

    final double resolvedZoom = value.clamp(_minZoomLevel, _maxZoomLevel);
    widget.config.setCameraZoomLevel(resolvedZoom);
    final CameraController? controller = _previewController;
    if (controller != null && controller.value.isInitialized) {
      try {
        final double appliedZoom = await _applyZoomSafely(
          controller,
          preferredZoom: resolvedZoom,
          fallbackZoom: _minZoomLevel,
        );
        if (appliedZoom != resolvedZoom) {
          widget.config.setCameraZoomLevel(appliedZoom);
        }
      } catch (error) {
        debugPrint('Failed to set zoom level: $error');
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

  void _savePhotoCount(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      widget.config.setPhotoCountOverride(null);
      return;
    }
    widget.config.setPhotoCountOverride(int.tryParse(trimmed));
  }

  Future<void> _pickCustomLogo() async {
    final String? path = await FilePickerHelper.pickCustomPath(
      allowedExtensions: const <String>['png', 'jpg', 'jpeg', 'gif'],
      dialogTitle: 'Choose custom logo',
    );
    if (!mounted || path == null) {
      return;
    }

    widget.config.setCustomLogoPath(path);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Custom logo selected.')),
    );
  }

  Future<void> _openMaximizedPreview() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(title: const Text('Live Camera Preview')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: _PreviewSurface(
                controller: _previewController,
                isLoading: _loadingPreview,
                error: _previewError,
                config: widget.config,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _takePhoto() async {
    final CameraController? controller = _previewController;
    if (controller == null || !controller.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera preview belum siap.')),
      );
      return;
    }

    try {
      final XFile file = await controller.takePicture();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo captured: ${file.name}')),
      );
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.description ?? error.code)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.config,
      builder: (BuildContext context, _) {
        final CameraDescription? selectedCamera =
            _cameras.isEmpty ? null : _resolveSelectedCamera();
        final String desiredPhotoText =
            widget.config.photoCountOverride?.toString() ?? '';
        if (_photoCountController.text != desiredPhotoText) {
          _photoCountController.text = desiredPhotoText;
          _photoCountController.selection = TextSelection.fromPosition(
            TextPosition(offset: _photoCountController.text.length),
          );
        }

        final ThemeData baseTheme = Theme.of(context);
        final ThemeData settingsTheme = baseTheme.copyWith(
          scaffoldBackgroundColor: const Color(0xFF0F2640),
          cardTheme: baseTheme.cardTheme.copyWith(
            color: const Color(0xFFFDFDFD),
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE9EDF3)),
            ),
          ),
          dividerColor: const Color(0xFFE6EAF0),
          inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
            filled: true,
            fillColor: const Color(0xFFFFFFFF),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE1E5EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: baseTheme.colorScheme.primary),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            helperStyle: const TextStyle(color: Color(0xFF8993A4)),
          ),
          textTheme: baseTheme.textTheme.apply(
            bodyColor: const Color(0xFF2B3648),
            displayColor: const Color(0xFF2B3648),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith<Color>(
                (Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFF173A63);
              }
              return Colors.white;
            }),
            trackColor: WidgetStateProperty.resolveWith<Color>(
                (Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFFF3D064);
              }
              return const Color(0xFFD9DCE2);
            }),
          ),
        );

        return Theme(
          data: settingsTheme,
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1220),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 30,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E4A73),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Settings updated successfully.'),
                                      ),
                                    );
                                  },
                                  child: const Text('Save Changes'),
                                ),
                                const Spacer(),
                                Text(
                                  'Booth Settings',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF344F72),
                                      ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  icon: const Icon(Icons.close,
                                      color: Color(0xFF8B94A3)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const _VersionBanner(),
                            const SizedBox(height: 14),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _tabs.map((String tab) {
                                  final bool selected = _activeTab == tab;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _SettingsTabButton(
                                      label: tab,
                                      selected: selected,
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
                            const SizedBox(height: 8),
                            const Divider(height: 1),
                            const SizedBox(height: 22),
                            if (_activeTab == 'Camera')
                              LayoutBuilder(
                                builder: (BuildContext context,
                                    BoxConstraints constraints) {
                                  final bool stacked =
                                      constraints.maxWidth < 1180;
                                  final Widget leftPanel = _SettingsLeftPanel(
                                    config: widget.config,
                                    cameras: _cameras,
                                    selectedCamera: selectedCamera,
                                    loadingDevices: _loadingDevices,
                                    deviceError: _deviceError,
                                    photoCountController: _photoCountController,
                                    onPhotoCountChanged: _savePhotoCount,
                                    onDetectCamera: _loadCameras,
                                    onResolutionChanged: _updateResolution,
                                    onZoomChanged: _updateZoom,
                                    minZoomLevel: _minZoomLevel,
                                    maxZoomLevel: _maxZoomLevel,
                                    zoomSupported: _zoomSupported,
                                    onCameraChanged:
                                        (CameraDescription? value) {
                                      if (value != null) {
                                        _updateCamera(value);
                                      }
                                    },
                                  );

                                  final Widget rightPanel = _SettingsRightPanel(
                                    config: widget.config,
                                    controller: _previewController,
                                    loadingPreview: _loadingPreview,
                                    previewError: _previewError,
                                    onRefresh: _initializePreview,
                                    onMaximize: _openMaximizedPreview,
                                    onTakePhoto: _takePhoto,
                                  );

                                  if (stacked) {
                                    return Column(
                                      children: <Widget>[
                                        leftPanel,
                                        const SizedBox(height: 20),
                                        rightPanel,
                                      ],
                                    );
                                  }

                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      SizedBox(width: 370, child: leftPanel),
                                      const SizedBox(width: 20),
                                      Expanded(child: rightPanel),
                                    ],
                                  );
                                },
                              )
                            else if (_activeTab == 'Printer')
                              _PrinterSettingsSection(config: widget.config)
                            else if (_activeTab == 'Timer')
                              _TimerSettingsSection(config: widget.config)
                            else if (_activeTab == 'Payment')
                              _PaymentSettingsSection(config: widget.config)
                            else if (_activeTab == 'Multi Print Discount')
                              _MultiPrintDiscountSection(config: widget.config)
                            else if (_activeTab == 'Extra Print')
                              _ExtraPrintSection(config: widget.config)
                            else if (_activeTab == 'General')
                              _GeneralSettingsSection(
                                config: widget.config,
                                onPickCustomLogo: _pickCustomLogo,
                              )
                            else if (_activeTab == 'Transaction')
                              _TransactionSettingsSection(config: widget.config)
                            else if (_activeTab == 'License')
                              _LicenseSettingsSection(config: widget.config)
                            else
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'Section $_activeTab belum diimplementasikan.',
                                    style:
                                        Theme.of(context).textTheme.bodyLarge,
                                  ),
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
      },
    );
  }
}

class _SettingsLeftPanel extends StatelessWidget {
  const _SettingsLeftPanel({
    required this.config,
    required this.cameras,
    required this.selectedCamera,
    required this.loadingDevices,
    required this.deviceError,
    required this.photoCountController,
    required this.onPhotoCountChanged,
    required this.onDetectCamera,
    required this.onResolutionChanged,
    required this.onZoomChanged,
    required this.minZoomLevel,
    required this.maxZoomLevel,
    required this.zoomSupported,
    required this.onCameraChanged,
  });

  final PhotoBoothConfig config;
  final List<CameraDescription> cameras;
  final CameraDescription? selectedCamera;
  final bool loadingDevices;
  final String? deviceError;
  final TextEditingController photoCountController;
  final ValueChanged<String> onPhotoCountChanged;
  final Future<void> Function() onDetectCamera;
  final Future<void> Function(ResolutionPreset) onResolutionChanged;
  final Future<void> Function(double) onZoomChanged;
  final double minZoomLevel;
  final double maxZoomLevel;
  final bool zoomSupported;
  final ValueChanged<CameraDescription?> onCameraChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _FieldLabel('Camera Resolution'),
              DropdownButtonFormField<ResolutionPreset>(
                value: config.resolutionPreset,
                items: ResolutionPreset.values.map((ResolutionPreset preset) {
                  return DropdownMenuItem<ResolutionPreset>(
                    value: preset,
                    child: Text(_resolutionLabel(preset)),
                  );
                }).toList(),
                onChanged: (ResolutionPreset? preset) {
                  if (preset != null) {
                    onResolutionChanged(preset);
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  const Expanded(child: _FieldLabel('Camera Device')),
                  FilledButton.tonal(
                    onPressed: loadingDevices ? null : onDetectCamera,
                    child: const Text('Detect Camera'),
                  ),
                ],
              ),
              DropdownButtonFormField<CameraDescription>(
                value: selectedCamera,
                items: cameras.map((CameraDescription camera) {
                  return DropdownMenuItem<CameraDescription>(
                    value: camera,
                    child: Text(camera.name),
                  );
                }).toList(),
                onChanged: cameras.isEmpty ? null : onCameraChanged,
                hint: Text(loadingDevices
                    ? 'Detecting cameras...'
                    : 'No camera detected'),
              ),
              if (deviceError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  deviceError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              const _FieldLabel('Number of Photos Taken'),
              TextField(
                controller: photoCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Leave empty to use frame slot count',
                  helperText:
                      'If not set, booth uses the number of slots in the selected frame.',
                ),
                onChanged: onPhotoCountChanged,
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Camera Zoom'),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Slider(
                      value: config.cameraZoomLevel
                          .clamp(minZoomLevel, maxZoomLevel),
                      min: minZoomLevel,
                      max: maxZoomLevel,
                      divisions: zoomSupported && maxZoomLevel > minZoomLevel
                          ? ((maxZoomLevel - minZoomLevel) * 10)
                              .round()
                              .clamp(1, 100)
                          : null,
                      label: '${config.cameraZoomLevel.toStringAsFixed(1)}x',
                      onChanged: zoomSupported && maxZoomLevel > minZoomLevel
                          ? (double value) {
                              onZoomChanged(value);
                            }
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${config.cameraZoomLevel.toStringAsFixed(1)}x',
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              Text(
                zoomSupported
                    ? 'Gunakan zoom lebih kecil jika preview terasa terlalu dekat.'
                    : 'Kamera ini tidak mendukung kontrol zoom dari aplikasi.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Camera Aspect Ratio'),
              DropdownButtonFormField<BoothAspectRatio>(
                value: config.aspectRatio,
                items: BoothAspectRatio.values.map((BoothAspectRatio value) {
                  return DropdownMenuItem<BoothAspectRatio>(
                    value: value,
                    child: Text(value.label),
                  );
                }).toList(),
                onChanged: (BoothAspectRatio? value) {
                  if (value != null) {
                    config.setAspectRatio(value);
                  }
                },
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Horizontal Flip Mode (Mirror Effect)'),
              DropdownButtonFormField<BoothFlipMode>(
                value: config.flipMode,
                items: BoothFlipMode.values.map((BoothFlipMode value) {
                  return DropdownMenuItem<BoothFlipMode>(
                    value: value,
                    child: Text(value.label),
                  );
                }).toList(),
                onChanged: (BoothFlipMode? value) {
                  if (value != null) {
                    config.setFlipMode(value);
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                config.flipMode.description,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              Text(
                'Camera Crop Controls (Percentage)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _CropControlRow(
                  label: 'Top',
                  value: config.cropTopPercent,
                  onChanged: config.setCropTopPercent),
              _CropControlRow(
                  label: 'Bottom',
                  value: config.cropBottomPercent,
                  onChanged: config.setCropBottomPercent),
              _CropControlRow(
                  label: 'Left',
                  value: config.cropLeftPercent,
                  onChanged: config.setCropLeftPercent),
              _CropControlRow(
                  label: 'Right',
                  value: config.cropRightPercent,
                  onChanged: config.setCropRightPercent),
              const SizedBox(height: 8),
              Text(
                'Adjust crop to eliminate black bars or unwanted areas.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('External Flash (Canon DSLR)'),
                subtitle:
                    const Text('Enable external flash when taking photos.'),
                value: config.enableExternalFlash,
                onChanged: config.setEnableExternalFlash,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Image Compression'),
                subtitle:
                    const Text('Enable image compression to reduce file size.'),
                value: config.enableImageCompression,
                onChanged: config.setEnableImageCompression,
              ),
              DropdownButtonFormField<BoothCompressionProfile>(
                value: config.imageCompressionProfile,
                onChanged: config.enableImageCompression
                    ? (BoothCompressionProfile? value) {
                        if (value != null) {
                          config.setImageCompressionProfile(value);
                        }
                      }
                    : null,
                items: BoothCompressionProfile.values
                    .map((BoothCompressionProfile value) {
                  return DropdownMenuItem<BoothCompressionProfile>(
                    value: value,
                    child: Text(_imageCompressionLabel(value)),
                  );
                }).toList(),
                decoration:
                    const InputDecoration(labelText: 'Compression Ratio'),
              ),
              const SizedBox(height: 8),
              Text(
                config.imageCompressionProfile.description,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Photostrip Sharpening'),
                subtitle: const Text(
                    'Apply a sharpening pass to the final photostrip.'),
                value: config.enablePhotostripSharpening,
                onChanged: config.setEnablePhotostripSharpening,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Live Photo Compression (BTS Video)'),
                subtitle: const Text(
                    'Enable compression for captured live photo videos.'),
                value: config.enableLivePhotoCompression,
                onChanged: config.setEnableLivePhotoCompression,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<BoothCompressionProfile>(
                value: config.movingStripCompressionProfile,
                onChanged: config.enableLivePhotoCompression
                    ? (BoothCompressionProfile? value) {
                        if (value != null) {
                          config.setMovingStripCompressionProfile(value);
                        }
                      }
                    : null,
                items: BoothCompressionProfile.values
                    .map((BoothCompressionProfile value) {
                  return DropdownMenuItem<BoothCompressionProfile>(
                    value: value,
                    child: Text(_movingStripLabel(value)),
                  );
                }).toList(),
                decoration: const InputDecoration(
                    labelText: 'Animation/Moving Strip Compression'),
              ),
              const SizedBox(height: 8),
              Text(
                'High compression significantly reduces file size for faster uploads.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Screen Orientation'),
              DropdownButtonFormField<BoothScreenOrientation>(
                value: config.screenOrientation,
                items: BoothScreenOrientation.values
                    .map((BoothScreenOrientation value) {
                  return DropdownMenuItem<BoothScreenOrientation>(
                    value: value,
                    child: Text(value.label),
                  );
                }).toList(),
                onChanged: (BoothScreenOrientation? value) {
                  if (value != null) {
                    config.setScreenOrientation(value);
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how the live view is displayed on the screen.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Crop Preview in Live View'),
                subtitle: const Text(
                    'Show a dark overlay indicating the photo safe zone.'),
                value: config.showCropPreviewInLiveView,
                onChanged: config.setShowCropPreviewInLiveView,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _resolutionLabel(ResolutionPreset preset) {
    switch (preset) {
      case ResolutionPreset.low:
        return '640x480';
      case ResolutionPreset.medium:
        return '1280x720';
      case ResolutionPreset.high:
        return '1920x1080';
      case ResolutionPreset.veryHigh:
        return '3840x2160';
      case ResolutionPreset.ultraHigh:
        return 'Ultra High';
      case ResolutionPreset.max:
        return 'Maximum';
    }
  }

  String _imageCompressionLabel(BoothCompressionProfile value) {
    switch (value) {
      case BoothCompressionProfile.none:
        return 'Original Quality';
      case BoothCompressionProfile.medium:
        return 'Medium Compression';
      case BoothCompressionProfile.high:
        return 'High Compression (max_width: 2000)';
    }
  }

  String _movingStripLabel(BoothCompressionProfile value) {
    switch (value) {
      case BoothCompressionProfile.none:
        return 'No Compression';
      case BoothCompressionProfile.medium:
        return 'Medium Compression (~40% smaller)';
      case BoothCompressionProfile.high:
        return 'High Compression (~70% smaller file size)';
    }
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

class _SettingsRightPanel extends StatelessWidget {
  const _SettingsRightPanel({
    required this.config,
    required this.controller,
    required this.loadingPreview,
    required this.previewError,
    required this.onRefresh,
    required this.onMaximize,
    required this.onTakePhoto,
  });

  final PhotoBoothConfig config;
  final CameraController? controller;
  final bool loadingPreview;
  final String? previewError;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onMaximize;
  final Future<void> Function() onTakePhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'Live Camera Preview',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  FilledButton.tonal(
                      onPressed: onRefresh,
                      child: const Text('Refresh Buttons')),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: onTakePhoto, child: const Text('Take Photo')),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: onMaximize, child: const Text('Maximize')),
                ],
              ),
              const SizedBox(height: 12),
              _PreviewSurface(
                controller: controller,
                isLoading: loadingPreview,
                error: previewError,
                config: config,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Canon DSLR Settings',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool stacked = constraints.maxWidth < 860;
                  final Widget isoCard = _DslrControlCard(
                    title: 'ISO',
                    value: config.isoSetting.label,
                    children: BoothIsoSetting.values.map((BoothIsoSetting iso) {
                      return ChoiceChip(
                        label: Text(iso.label),
                        selected: config.isoSetting == iso,
                        onSelected: (_) => config.setIsoSetting(iso),
                      );
                    }).toList(),
                  );
                  final Widget apertureCard = _DslrControlCard(
                    title: 'Aperture',
                    value: config.apertureSetting.label,
                    children: BoothApertureSetting.values
                        .map((BoothApertureSetting aperture) {
                      return ChoiceChip(
                        label: Text(aperture.label),
                        selected: config.apertureSetting == aperture,
                        onSelected: (_) => config.setApertureSetting(aperture),
                      );
                    }).toList(),
                  );
                  final Widget shutterCard = _DslrControlCard(
                    title: 'Shutter Speed',
                    value: config.shutterSpeed.label,
                    children:
                        BoothShutterSpeed.values.map((BoothShutterSpeed speed) {
                      return ChoiceChip(
                        label: Text(speed.label),
                        selected: config.shutterSpeed == speed,
                        onSelected: (_) => config.setShutterSpeed(speed),
                      );
                    }).toList(),
                  );
                  final Widget whiteBalanceCard = _DslrControlCard(
                    title: 'White Balance',
                    value: config.whiteBalancePreset.label,
                    children: BoothWhiteBalancePreset.values
                        .map((BoothWhiteBalancePreset preset) {
                      return ChoiceChip(
                        label: Text(preset.label),
                        selected: config.whiteBalancePreset == preset,
                        onSelected: (_) => config.setWhiteBalancePreset(preset),
                      );
                    }).toList(),
                  );

                  if (stacked) {
                    return Column(
                      children: <Widget>[
                        isoCard,
                        const SizedBox(height: 16),
                        apertureCard,
                        const SizedBox(height: 16),
                        shutterCard,
                        const SizedBox(height: 16),
                        whiteBalanceCard,
                      ],
                    );
                  }

                  return Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(child: isoCard),
                          const SizedBox(width: 16),
                          Expanded(child: apertureCard),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(child: shutterCard),
                          const SizedBox(width: 16),
                          Expanded(child: whiteBalanceCard),
                        ],
                      ),
                    ],
                  );
                },
              ),
              Text(
                'Adjust DSLR camera settings. Changes are reflected in the simulated live view overlay.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface({
    required this.controller,
    required this.isLoading,
    required this.error,
    required this.config,
  });

  final CameraController? controller;
  final bool isLoading;
  final String? error;
  final PhotoBoothConfig config;

  @override
  Widget build(BuildContext context) {
    final CameraController? activeController = controller;
    final double resolvedAspectRatio = config.aspectRatio.value ??
        activeController?.value.aspectRatio ??
        (config.screenOrientation == BoothScreenOrientation.landscape
            ? 16 / 9
            : 9 / 16);

    Widget content;
    if (isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      content = _PreviewMessage(message: error!);
    } else if (activeController == null ||
        !activeController.value.isInitialized) {
      content =
          const _PreviewMessage(message: 'Select a camera to see live preview');
    } else {
      Widget preview = CameraPreview(activeController);
      final List<double>? matrix = config.filter.matrix;
      if (matrix != null) {
        preview = ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix),
          child: preview,
        );
      }

      preview = ColorFiltered(
        colorFilter: ColorFilter.mode(
          config.whiteBalancePreset.tintColor,
          BlendMode.softLight,
        ),
        child: preview,
      );

      content = LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double topInset = constraints.maxHeight * config.cropTopPercent;
          final double bottomInset =
              constraints.maxHeight * config.cropBottomPercent;
          final double leftInset =
              constraints.maxWidth * config.cropLeftPercent;
          final double rightInset =
              constraints.maxWidth * config.cropRightPercent;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Positioned.fill(
                left: leftInset,
                right: rightInset,
                top: topInset,
                bottom: bottomInset,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..scale(config.mirrorPreview ? -1.0 : 1.0, 1.0),
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: activeController.value.previewSize?.height ?? 1080,
                      height: activeController.value.previewSize?.width ?? 1920,
                      child: preview,
                    ),
                  ),
                ),
              ),
              if (config.showCropPreviewInLiveView)
                _CropOverlay(
                  topInset: topInset,
                  bottomInset: bottomInset,
                  leftInset: leftInset,
                  rightInset: rightInset,
                ),
              if (config.showGrid) const _GridOverlay(),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _PreviewBadge(text: config.resolutionPreset.name),
                    _PreviewBadge(
                        text: '${config.cameraZoomLevel.toStringAsFixed(1)}x'),
                    _PreviewBadge(text: config.flipMode.label),
                    _PreviewBadge(text: config.shutterSpeed.label),
                    _PreviewBadge(text: config.whiteBalancePreset.label),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }

    return AspectRatio(
      aspectRatio: resolvedAspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(18),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: content,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: child,
      ),
    );
  }
}

class _DslrControlCard extends StatelessWidget {
  const _DslrControlCard({
    required this.title,
    required this.value,
    required this.children,
  });

  final String title;
  final String value;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: children,
          ),
        ],
      ),
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: Colors.white70),
        ),
      ),
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(text),
      ),
    );
  }
}

class _CropOverlay extends StatelessWidget {
  const _CropOverlay({
    required this.topInset,
    required this.bottomInset,
    required this.leftInset,
    required this.rightInset,
  });

  final double topInset;
  final double bottomInset;
  final double leftInset;
  final double rightInset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CropOverlayPainter(
          topInset: topInset,
          bottomInset: bottomInset,
          leftInset: leftInset,
          rightInset: rightInset,
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.topInset,
    required this.bottomInset,
    required this.leftInset,
    required this.rightInset,
  });

  final double topInset;
  final double bottomInset;
  final double leftInset;
  final double rightInset;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35);
    final Paint guidePaint = Paint()
      ..color = Colors.white60
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, topInset), shadowPaint);
    canvas.drawRect(
        Rect.fromLTWH(0, size.height - bottomInset, size.width, bottomInset),
        shadowPaint);
    canvas.drawRect(
        Rect.fromLTWH(
            0, topInset, leftInset, size.height - topInset - bottomInset),
        shadowPaint);
    canvas.drawRect(
      Rect.fromLTWH(size.width - rightInset, topInset, rightInset,
          size.height - topInset - bottomInset),
      shadowPaint,
    );

    final Rect safeRect = Rect.fromLTWH(
      leftInset,
      topInset,
      size.width - leftInset - rightInset,
      size.height - topInset - bottomInset,
    );
    canvas.drawRect(safeRect, guidePaint);
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.topInset != topInset ||
        oldDelegate.bottomInset != bottomInset ||
        oldDelegate.leftInset != leftInset ||
        oldDelegate.rightInset != rightInset;
  }
}

class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _GridPainter()),
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

class _CropControlRow extends StatelessWidget {
  const _CropControlRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final int percent = (value * 100).round();
    return Row(
      children: <Widget>[
        SizedBox(width: 58, child: Text('$label:')),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 0.45,
            divisions: 45,
            label: '$percent%',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            '$percent%',
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

class _GeneralSettingsSection extends StatelessWidget {
  const _GeneralSettingsSection({
    required this.config,
    required this.onPickCustomLogo,
  });

  final PhotoBoothConfig config;
  final Future<void> Function() onPickCustomLogo;

  static const List<String> _languages = <String>[
    'English',
    'Bahasa',
  ];

  static const List<String> _performanceModes = <String>[
    'Auto (Detect PC specs)',
    'Low Spec Mode',
    'Balanced',
    'High Quality',
  ];

  static const List<String> _loopCounts = <String>[
    '1 Loop (~5s)',
    '2 Loops (~10s) - Default',
    '3 Loops (~15s)',
    '4 Loops (~20s)',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stacked = constraints.maxWidth < 1100;
        final Widget left = Column(
          children: <Widget>[
            _SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _TextValueField(
                    label: 'Booth Name',
                    value: config.boothName,
                    onChanged: config.setBoothName,
                    hintText: 'Enter booth name',
                  ),
                  const SizedBox(height: 16),
                  _TextValueField(
                    label: 'Tagline',
                    value: config.boothTagline,
                    onChanged: config.setBoothTagline,
                    hintText: 'Enter tagline',
                  ),
                  const SizedBox(height: 16),
                  _TextValueField(
                    label: 'Admin PIN',
                    value: config.adminPin,
                    onChanged: config.setAdminPin,
                    hintText: 'Enter admin PIN',
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel('Custom Logo'),
                  Row(
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: onPickCustomLogo,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Choose File'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          config.customLogoPath ?? 'No file chosen',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: const Color(0xFF8C96A6)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Upload a custom logo to replace the default logo on the kiosk page. Supported formats: PNG, JPG, JPEG, GIF. Max size: 2MB',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: const Color(0xFF8C96A6)),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: <Widget>[
                        Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FA),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E7EE)),
                          ),
                          alignment: Alignment.center,
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(
                                Icons.photo_camera_back_rounded,
                                size: 42,
                                color: Color(0xFF9A8742),
                              ),
                              SizedBox(height: 8),
                              Text('Current logo'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('Logo Size: ${config.logoSizePx.round()}px'),
                        Slider(
                          value: config.logoSizePx,
                          min: 300,
                          max: 1800,
                          divisions: 150,
                          label: '${config.logoSizePx.round()}px',
                          onChanged: config.setLogoSizePx,
                        ),
                        Text(
                          'Adjust the logo size displayed on the kiosk page (300px - 1800px)',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF8C96A6)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _GeneralToggleTile(
                    title: 'Enable Print Button',
                    description:
                        'If enabled, the print button will be shown on the output page. If disabled, auto print will also be disabled.',
                    value: config.enablePrintButton,
                    onChanged: config.setEnablePrintButton,
                  ),
                  const SizedBox(height: 12),
                  _GeneralToggleTile(
                    title: 'Upload Original Photos to Luminash Drive',
                    description:
                        'If enabled, all original photos from each session will be automatically uploaded after the photo session is complete.',
                    value: config.uploadOriginalPhotosToLuminashDrive,
                    onChanged: config.setUploadOriginalPhotosToLuminashDrive,
                  ),
                  if (config.uploadOriginalPhotosToLuminashDrive) ...<Widget>[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x2233C26B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x6633C26B)),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.check_box, color: Color(0xFF33C26B)),
                          SizedBox(width: 10),
                          Expanded(
                              child: Text('Photo upload is enabled and ready')),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _GeneralToggleTile(
                    title: 'Auto Sync Frames on Startup',
                    description:
                        'If enabled, frames will be automatically synced from the cloud when the application starts.',
                    value: config.autoSyncFramesOnStartup,
                    onChanged: config.setAutoSyncFramesOnStartup,
                  ),
                  const SizedBox(height: 12),
                  _GeneralToggleTile(
                    title: 'Show Photo Count Modal',
                    description:
                        'If enabled, shows a modal at the start of photo session telling customers how many photos will be taken.',
                    value: config.showPhotoCountModal,
                    onChanged: config.setShowPhotoCountModal,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Remote Settings Sync',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _GeneralToggleTile(
                    title: 'Enable Remote Settings Sync',
                    description:
                        'If enabled, settings will be synced from Firebase or dashboard on app startup. Disable to use local settings only.',
                    value: config.enableRemoteSettingsSync,
                    onChanged: config.setEnableRemoteSettingsSync,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: config.enableRemoteSettingsSync ? () {} : null,
                      child: const Text('Push Settings to Dashboard'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Manually push current local settings to dashboard. Use this if you have made local changes that you want to apply globally.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: const Color(0xFF8C96A6)),
                  ),
                ],
              ),
            ),
          ],
        );

        final Widget right = Column(
          children: <Widget>[
            _SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _FieldLabel('Language / Bahasa'),
                  DropdownButtonFormField<String>(
                    value: config.language,
                    items: _languages
                        .map((String language) => DropdownMenuItem<String>(
                            value: language, child: Text(language)))
                        .toList(),
                    onChanged: (String? value) {
                      if (value != null) {
                        config.setLanguage(value);
                      }
                    },
                    decoration: const InputDecoration(
                        helperText:
                            'Select display language for the photobooth interface'),
                  ),
                  const SizedBox(height: 16),
                  _GeneralToggleTile(
                    title: 'Auto Print on Output Page',
                    description:
                        'If enabled, printing starts automatically on the output page using the default printer settings.',
                    value: config.autoPrintOnOutputPage,
                    onChanged: config.enablePrintButton
                        ? config.setAutoPrintOnOutputPage
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _GeneralToggleTile(
                    title: 'Enable Email on Output Page',
                    description:
                        'If enabled, guests can send their download link via email from the output page.',
                    value: config.enableEmailOnOutputPage,
                    onChanged: config.setEnableEmailOnOutputPage,
                  ),
                  const SizedBox(height: 12),
                  _GeneralToggleTile(
                    title: 'Enable Consent Form',
                    description:
                        'If enabled, a consent form will appear on the output page asking if photos can be used for marketing purposes.',
                    value: config.enableConsentForm,
                    onChanged: config.setEnableConsentForm,
                  ),
                  const SizedBox(height: 12),
                  _GeneralToggleTile(
                    title: 'Enable Moving Strip Mode (Ultimate Tier Only)',
                    description:
                        'If enabled, creates animated moving photostrips from behind-the-scenes videos.',
                    value: config.enableMovingStripMode,
                    onChanged: config.setEnableMovingStripMode,
                  ),
                  const SizedBox(height: 12),
                  _GeneralToggleTile(
                    title: 'Skip Photostrip Creation',
                    description:
                        'If enabled, photos will be automatically assigned to frame slots without manual selection.',
                    value: config.skipPhotostripCreation,
                    onChanged: config.setSkipPhotostripCreation,
                  ),
                  const SizedBox(height: 12),
                  _GeneralToggleTile(
                    title: 'Enable Photo Zoom/Pan',
                    description:
                        'Enable zoom and reposition for photos in photostrip slots using touch gestures.',
                    value: config.enablePhotoZoomPan,
                    onChanged: config.setEnablePhotoZoomPan,
                  ),
                  const SizedBox(height: 12),
                  _GeneralToggleTile(
                    title: 'Auto-select Single Frame',
                    description:
                        'If enabled and only 1 frame exists in all category, it will be selected automatically and session starts immediately.',
                    value: config.autoSelectSingleFrame,
                    onChanged: config.setAutoSelectSingleFrame,
                  ),
                  const SizedBox(height: 12),
                  _GeneralToggleTile(
                    title: 'Skip Filter Selection',
                    description:
                        'If enabled, skip filter selection and use Original filter automatically. Photos go directly to output page.',
                    value: config.skipFilterSelection,
                    onChanged: config.setSkipFilterSelection,
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel('Moving Strip Performance Mode'),
                  DropdownButtonFormField<String>(
                    value: config.movingStripPerformanceMode,
                    items: _performanceModes
                        .map((String mode) => DropdownMenuItem<String>(
                            value: mode, child: Text(mode)))
                        .toList(),
                    onChanged: config.enableMovingStripMode
                        ? (String? value) {
                            if (value != null) {
                              config.setMovingStripPerformanceMode(value);
                            }
                          }
                        : null,
                    decoration: const InputDecoration(
                      helperText:
                          'Choose performance mode based on your PC specs. Low-spec mode reduces resolution and frame rate.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel('Moving Strip Loop Count'),
                  DropdownButtonFormField<String>(
                    value: config.movingStripLoopCount,
                    items: _loopCounts
                        .map((String mode) => DropdownMenuItem<String>(
                            value: mode, child: Text(mode)))
                        .toList(),
                    onChanged: config.enableMovingStripMode
                        ? (String? value) {
                            if (value != null) {
                              config.setMovingStripLoopCount(value);
                            }
                          }
                        : null,
                    decoration: const InputDecoration(
                      helperText:
                          'Choose how many loops of BTS video to use when creating moving photostrip animation.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _TextValueField(
                    label: 'Activation Code',
                    value: config.activationCode,
                    onChanged: config.setActivationCode,
                    enabled: config.enableMovingStripMode,
                    hintText: 'Enter your activation code',
                  ),
                ],
              ),
            ),
          ],
        );

        if (stacked) {
          return Column(
            children: <Widget>[
              left,
              const SizedBox(height: 16),
              right,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _GeneralToggleTile extends StatelessWidget {
  const _GeneralToggleTile({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF8C96A6)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _TransactionSettingsSection extends StatelessWidget {
  const _TransactionSettingsSection({required this.config});

  final PhotoBoothConfig config;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Reprint Logging',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFFD1A520),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'Log reprint transactions to Firebase for tracking and analytics.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF8C96A6)),
          ),
          const SizedBox(height: 18),
          _GeneralToggleTile(
            title: 'Enable Reprint Logging',
            description:
                'When enabled, reprints from Session Reprint will be logged to Firebase transactions.',
            value: config.enableReprintLogging,
            onChanged: config.setEnableReprintLogging,
          ),
          const SizedBox(height: 22),
          _NumberField(
            label: 'Reprint Amount (Rp)',
            value: config.reprintAmountIdr,
            onChanged: config.setReprintAmountIdr,
            enabled: config.enableReprintLogging,
            helperText:
                'Amount to record for each reprint transaction (0 for free reprints).',
          ),
        ],
      ),
    );
  }
}

class _LicenseSettingsSection extends StatelessWidget {
  const _LicenseSettingsSection({required this.config});

  final PhotoBoothConfig config;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'License Information',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF334F72),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 18),
        _SettingsCard(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFCFCFD),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE6EAF0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _LicenseInfoRow(
                  label: 'Expires At:',
                  value: config.licenseExpiryText,
                ),
                const SizedBox(height: 22),
                _LicenseInfoRow(
                  label: 'Version:',
                  value: config.licenseVersion,
                ),
                const SizedBox(height: 22),
                _LicenseInfoRow(
                  label: 'Max Devices:',
                  value: '${config.licenseMaxDevices}',
                ),
                const SizedBox(height: 22),
                Text(
                  'Used Devices:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                if (config.licenseUsedDevices.isEmpty)
                  Text(
                    'No registered devices',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF8C96A6),
                        ),
                  )
                else
                  ...config.licenseUsedDevices.map(
                    (String device) => Padding(
                      padding: const EdgeInsets.only(left: 18, bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('• '),
                          Expanded(
                            child: Text(
                              device,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: const Color(0xFF5D6675),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF24476F),
              foregroundColor: const Color(0xFFF1D065),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('License info refreshed.')),
              );
            },
            child: const Text('Refresh License Info'),
          ),
        ),
      ],
    );
  }
}

class _LicenseInfoRow extends StatelessWidget {
  const _LicenseInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF5D6675),
              height: 1.4,
            ),
        children: <InlineSpan>[
          TextSpan(
            text: label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF2B3648),
            ),
          ),
          TextSpan(text: ' $value'),
        ],
      ),
    );
  }
}

class _VersionBanner extends StatelessWidget {
  const _VersionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E5424),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: <Widget>[
          const Text('🚀', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          //Expanded(
            // child: Column(
            //   crossAxisAlignment: CrossAxisAlignment.start,
            //   children: <Widget>[
            //     // Text(
            //     //   'New version available: v1.39',
            //     //   style: Theme.of(context).textTheme.titleSmall?.copyWith(
            //     //         color: const Color(0xFF67F091),
            //     //         fontWeight: FontWeight.w700,
            //     //       ),
            //     // ),
            //     const SizedBox(height: 2),
            //     Text(
            //       'Enhance portrait orientation',
            //       style: Theme.of(context).textTheme.bodySmall?.copyWith(
            //             color: const Color(0xFFE4F3E4),
            //           ),
            //     ),
            //   ],
            // ),
          //),
          // FilledButton.icon(
          //   style: FilledButton.styleFrom(
          //     backgroundColor: const Color(0xFF1CC260),
          //     foregroundColor: Colors.white,
          //     shape: RoundedRectangleBorder(
          //       borderRadius: BorderRadius.circular(6),
          //     ),
          //   ),
          //   onPressed: () {},
          //   icon: const Icon(Icons.flash_on, size: 16),
          //   label: const Text('Install v1.39'),
          // ),
          const SizedBox(width: 10),
          Text(
            'Current: v1.38',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB7C5B8),
                ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTabButton extends StatelessWidget {
  const _SettingsTabButton({
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
                      : const Color(0xFF8B94A3),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}

class _PrinterSettingsSection extends StatelessWidget {
  const _PrinterSettingsSection({required this.config});

  final PhotoBoothConfig config;

  static const List<String> _printers = <String>[
    'DS-RX1 (Default)',
    'DNP DS620A',
    'Canon SELPHY CP1500',
    'Mitsubishi CP-D90DW',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x22F1C24C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x66F1C24C)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Disable All Printing',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'When enabled, all printing functionality is disabled. The print button will be hidden and auto-print will be turned off.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Switch(
                value: config.disableAllPrinting,
                onChanged: config.setDisableAllPrinting,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool stacked = constraints.maxWidth < 1000;
            final Widget left = Column(
              children: <Widget>[
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Primary Printer',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),
                      const _FieldLabel('Primary Printer'),
                      DropdownButtonFormField<String>(
                        value: config.primaryPrinter,
                        items: _printers
                            .map((String printer) => DropdownMenuItem<String>(
                                value: printer, child: Text(printer)))
                            .toList(),
                        onChanged: config.disableAllPrinting
                            ? null
                            : (String? value) {
                                if (value != null) {
                                  config.setPrimaryPrinter(value);
                                }
                              },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          FilledButton.tonal(
                              onPressed:
                                  config.disableAllPrinting ? null : () {},
                              child: const Text('Configure Printer')),
                          const SizedBox(width: 12),
                          FilledButton.tonal(
                              onPressed:
                                  config.disableAllPrinting ? null : () {},
                              child: const Text('Test Printer')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Primary: ${config.primaryPrinter}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Print Options',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),
                      const _FieldLabel('Print Mode'),
                      DropdownButtonFormField<BoothPrintMode>(
                        value: config.printMode,
                        items: BoothPrintMode.values
                            .map((BoothPrintMode mode) =>
                                DropdownMenuItem<BoothPrintMode>(
                                    value: mode, child: Text(mode.label)))
                            .toList(),
                        onChanged: config.disableAllPrinting
                            ? null
                            : (BoothPrintMode? value) {
                                if (value != null) {
                                  config.setPrintMode(value);
                                }
                              },
                      ),
                      const SizedBox(height: 8),
                      Text(config.printMode.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white70)),
                      const SizedBox(height: 20),
                      const _FieldLabel('Print Scale'),
                      Slider(
                        value: config.printScalePercent,
                        min: 50,
                        max: 100,
                        divisions: 50,
                        label: '${config.printScalePercent.round()}%',
                        onChanged: config.disableAllPrinting
                            ? null
                            : config.setPrintScalePercent,
                      ),
                      Row(
                        children: <Widget>[
                          Text('${config.printScalePercent.round()}%',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(
                              'Scale: ${config.printScalePercent.round()}% | Border: ${config.printScalePercent >= 100 ? 'No border' : 'White border'}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                          '100% = Full paper size. Smaller values = Smaller image with white border around it.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white70)),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('2R to 4R Conversion'),
                        subtitle: const Text(
                            'Automatically duplicate vertical strips side-by-side for 4R layout.'),
                        value: config.enable2Rto4RConversion,
                        onChanged: config.disableAllPrinting
                            ? null
                            : config.setEnable2Rto4RConversion,
                      ),
                    ],
                  ),
                ),
              ],
            );

            final Widget right = Column(
              children: <Widget>[
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Secondary Printer',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable Secondary Printer'),
                        subtitle: const Text(
                            'Disable to force all printing to use Primary printer.'),
                        value: config.enableSecondaryPrinter,
                        onChanged: config.disableAllPrinting
                            ? null
                            : config.setEnableSecondaryPrinter,
                      ),
                      const _FieldLabel('Secondary Printer'),
                      DropdownButtonFormField<String>(
                        value: config.secondaryPrinter,
                        items: _printers
                            .where((String printer) =>
                                printer != config.primaryPrinter)
                            .map((String printer) => DropdownMenuItem<String>(
                                value: printer, child: Text(printer)))
                            .toList(),
                        onChanged: config.disableAllPrinting ||
                                !config.enableSecondaryPrinter
                            ? null
                            : config.setSecondaryPrinter,
                        hint: const Text('-- Select Secondary Printer --'),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          FilledButton.tonal(
                              onPressed: (!config.enableSecondaryPrinter ||
                                      config.disableAllPrinting)
                                  ? null
                                  : () {},
                              child: const Text('Configure Printer')),
                          const SizedBox(width: 12),
                          FilledButton.tonal(
                              onPressed: (!config.enableSecondaryPrinter ||
                                      config.disableAllPrinting)
                                  ? null
                                  : () {},
                              child: const Text('Test Printer')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        config.enableSecondaryPrinter
                            ? 'Secondary printer ready for fallback or print splitting.'
                            : 'Secondary printer is disabled (using Primary only).',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Print Position Alignment',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),
                      const _FieldLabel('Horizontal Position'),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Slider(
                              value: config.printHorizontalOffset,
                              min: -50,
                              max: 50,
                              divisions: 100,
                              label:
                                  '${config.printHorizontalOffset.round()} px',
                              onChanged: config.disableAllPrinting
                                  ? null
                                  : config.setPrintHorizontalOffset,
                            ),
                          ),
                          SizedBox(
                              width: 56,
                              child: Text(
                                  '${config.printHorizontalOffset.round()}')),
                        ],
                      ),
                      Text('0px (Negative = Left, Positive = Right)',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white70)),
                      const SizedBox(height: 16),
                      const _FieldLabel('Vertical Position'),
                      Row(
                        children: <Widget>[
                          RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              value: config.printVerticalOffset,
                              min: -50,
                              max: 50,
                              divisions: 100,
                              label: '${config.printVerticalOffset.round()} px',
                              onChanged: config.disableAllPrinting
                                  ? null
                                  : config.setPrintVerticalOffset,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            children: <Widget>[
                              SizedBox(
                                  width: 56,
                                  child: Text(
                                      '${config.printVerticalOffset.round()}',
                                      textAlign: TextAlign.center)),
                              Text('0px',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.white70)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );

            if (stacked) {
              return Column(
                children: <Widget>[
                  left,
                  const SizedBox(height: 16),
                  right,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: left),
                const SizedBox(width: 16),
                Expanded(child: right),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TimerSettingsSection extends StatelessWidget {
  const _TimerSettingsSection({required this.config});

  final PhotoBoothConfig config;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _NumberField(
            label: 'First Photo Countdown Timer (seconds)',
            value: config.firstPhotoCountdownSeconds,
            onChanged: config.setFirstPhotoCountdownSeconds,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Disable Preview Countdown Timer'),
            subtitle: const Text(
                'If checked, there will be no countdown in photo preview after photo taken.'),
            value: config.disablePreviewCountdownTimer,
            onChanged: config.setDisablePreviewCountdownTimer,
          ),
          const SizedBox(height: 8),
          _NumberField(
            label: 'Preview Countdown Timer (seconds)',
            value: config.previewCountdownSeconds,
            onChanged: config.setPreviewCountdownSeconds,
            enabled: !config.disablePreviewCountdownTimer,
          ),
          const SizedBox(height: 16),
          _NumberField(
            label: 'Next Photo Countdown Timer (seconds)',
            value: config.nextPhotoCountdownSeconds,
            onChanged: config.setNextPhotoCountdownSeconds,
          ),
          const SizedBox(height: 16),
          _NumberField(
            label: 'Output Result Page Countdown Timer (seconds)',
            value: config.outputResultPageCountdownSeconds,
            onChanged: config.setOutputResultPageCountdownSeconds,
            helperText: 'Time before redirecting to kiosk after printing',
          ),
          const SizedBox(height: 16),
          _NumberField(
            label: 'Session Timer (minutes)',
            value: config.sessionTimerMinutes,
            onChanged: config.setSessionTimerMinutes,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Global Countdown Timer Session'),
            value: config.enableGlobalCountdownTimerSession,
            onChanged: config.setEnableGlobalCountdownTimerSession,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Retake Button'),
            subtitle: const Text(
                'When disabled, retake button will be hidden during photo preview'),
            value: config.enableRetakeButton,
            onChanged: config.setEnableRetakeButton,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Unlimited Retakes'),
                  subtitle: const Text(
                      'When checked, users can retake photos without any limit'),
                  value: config.unlimitedRetakes,
                  onChanged: config.enableRetakeButton
                      ? config.setUnlimitedRetakes
                      : null,
                ),
                _NumberField(
                  label: 'Retake Limit (per photo)',
                  value: config.retakeLimitPerPhoto,
                  onChanged: config.setRetakeLimitPerPhoto,
                  enabled:
                      config.enableRetakeButton && !config.unlimitedRetakes,
                  helperText:
                      'Maximum number of retakes allowed for each photo',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable "Tap to Screen to Start" Overlay Screen'),
            value: config.enableTapToStartOverlayScreen,
            onChanged: config.setEnableTapToStartOverlayScreen,
          ),
        ],
      ),
    );
  }
}

class _PaymentSettingsSection extends StatelessWidget {
  const _PaymentSettingsSection({required this.config});

  final PhotoBoothConfig config;

  static const List<String> _gateways = <String>[
    'Midtrans (Default)',
    'Xendit',
    'QRIS Static',
    'Manual / Cashier',
  ];

  static const List<String> _voucherModes = <String>[
    'Use 0 (Free)',
    'Use Payment Amount',
    'Fixed Discount 5000',
    'Fixed Discount 10000',
  ];

  static const List<String> _methodVisibility = <String>[
    'Show Both (QRIS & Voucher)',
    'Show QRIS Only',
    'Show Voucher Only',
  ];

  static const List<String> _environments = <String>[
    'Production',
    'Sandbox',
  ];

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Payment'),
            value: config.enablePayment,
            onChanged: config.setEnablePayment,
          ),
          const SizedBox(height: 12),
          _NumberField(
            label: 'Payment Amount (IDR)',
            value: config.paymentAmountIdr,
            onChanged: config.setPaymentAmountIdr,
            enabled: config.enablePayment,
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Payment Gateway'),
          DropdownButtonFormField<String>(
            value: config.paymentGateway,
            items: _gateways
                .map((String value) =>
                    DropdownMenuItem<String>(value: value, child: Text(value)))
                .toList(),
            onChanged: config.enablePayment
                ? (String? value) {
                    if (value != null) {
                      config.setPaymentGateway(value);
                    }
                  }
                : null,
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Voucher Amount'),
          DropdownButtonFormField<String>(
            value: config.voucherAmountMode,
            items: _voucherModes
                .map((String value) =>
                    DropdownMenuItem<String>(value: value, child: Text(value)))
                .toList(),
            onChanged: config.enablePayment
                ? (String? value) {
                    if (value != null) {
                      config.setVoucherAmountMode(value);
                    }
                  }
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose voucher mechanism: 0 = Free, payment = Use Payment Amount',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Payment Method Visibility (Plus/Ultimate Only)'),
          DropdownButtonFormField<String>(
            value: config.paymentMethodVisibility,
            items: _methodVisibility
                .map((String value) =>
                    DropdownMenuItem<String>(value: value, child: Text(value)))
                .toList(),
            onChanged: config.enablePayment
                ? (String? value) {
                    if (value != null) {
                      config.setPaymentMethodVisibility(value);
                    }
                  }
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            'Control which payment methods are shown in payment options page.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Midtrans Environment'),
          DropdownButtonFormField<String>(
            value: config.midtransEnvironment,
            items: _environments
                .map((String value) =>
                    DropdownMenuItem<String>(value: value, child: Text(value)))
                .toList(),
            onChanged: config.enablePayment
                ? (String? value) {
                    if (value != null) {
                      config.setMidtransEnvironment(value);
                    }
                  }
                : null,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show/Hide Keys'),
            value: config.showPaymentKeys,
            onChanged: config.enablePayment ? config.setShowPaymentKeys : null,
          ),
          const SizedBox(height: 12),
          _TextValueField(
            label: 'Midtrans Server Key',
            value: config.midtransServerKey,
            onChanged: config.setMidtransServerKey,
            enabled: config.enablePayment,
            obscure: !config.showPaymentKeys,
            hintText: 'Enter server key',
          ),
          const SizedBox(height: 16),
          _TextValueField(
            label: 'Midtrans Client Key',
            value: config.midtransClientKey,
            onChanged: config.setMidtransClientKey,
            enabled: config.enablePayment,
            obscure: !config.showPaymentKeys,
            hintText: 'Enter client key',
          ),
          const SizedBox(height: 16),
          _TextValueField(
            label: 'Merchant Token',
            value: config.merchantToken,
            onChanged: config.setMerchantToken,
            enabled: config.enablePayment,
            obscure: !config.showPaymentKeys,
            hintText: 'Enter merchant token',
          ),
        ],
      ),
    );
  }
}

class _MultiPrintDiscountSection extends StatelessWidget {
  const _MultiPrintDiscountSection({required this.config});

  final PhotoBoothConfig config;

  int _discountedTotal(int quantity) {
    final int unitPrice = config.paymentAmountIdr;
    final int cappedQuantity =
        quantity.clamp(1, config.maximumPrintsForDiscount);
    final int subtotal = unitPrice * cappedQuantity;
    if (!config.enableMultiplePrintDiscount ||
        cappedQuantity < config.discountThresholdPrints) {
      return subtotal;
    }
    final double multiplier = (100 - config.discountPercentage) / 100;
    return (subtotal * multiplier).round();
  }

  @override
  Widget build(BuildContext context) {
    final List<int> previewQuantities = <int>{
      config.discountThresholdPrints,
      (config.discountThresholdPrints + 1)
          .clamp(1, config.maximumPrintsForDiscount),
      config.maxPrintQuantity,
    }.toList()
      ..sort();

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
                'Enable Multi Print Functionality (Ultimate Tier Only)'),
            subtitle: const Text('Allow customers to buy more than 1 print'),
            value: config.enableMultiPrintFunctionality,
            onChanged: config.setEnableMultiPrintFunctionality,
          ),
          const SizedBox(height: 12),
          _NumberField(
            label: 'Max Print Quantity',
            value: config.maxPrintQuantity,
            onChanged: config.setMaxPrintQuantity,
            enabled: config.enableMultiPrintFunctionality,
            helperText:
                'Maximum number of prints a user can select during their session',
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Multiple Print Discount'),
            subtitle: const Text(
                'Enable discount for multiple prints to encourage bulk orders'),
            value: config.enableMultiplePrintDiscount,
            onChanged: config.enableMultiPrintFunctionality
                ? config.setEnableMultiplePrintDiscount
                : null,
          ),
          const SizedBox(height: 12),
          _NumberField(
            label: 'Discount Threshold (Prints)',
            value: config.discountThresholdPrints,
            onChanged: config.setDiscountThresholdPrints,
            enabled: config.enableMultiPrintFunctionality &&
                config.enableMultiplePrintDiscount,
            helperText:
                'Minimum number of prints required to trigger the discount',
          ),
          const SizedBox(height: 16),
          _NumberField(
            label: 'Discount Percentage (%)',
            value: config.discountPercentage,
            onChanged: config.setDiscountPercentage,
            enabled: config.enableMultiPrintFunctionality &&
                config.enableMultiplePrintDiscount,
            helperText:
                'Percentage discount applied to total amount when threshold is met',
          ),
          const SizedBox(height: 16),
          _NumberField(
            label: 'Maximum Prints for Discount',
            value: config.maximumPrintsForDiscount,
            onChanged: config.setMaximumPrintsForDiscount,
            enabled: config.enableMultiPrintFunctionality &&
                config.enableMultiplePrintDiscount,
            helperText: 'Maximum number of prints that can receive discount',
          ),
          const SizedBox(height: 16),
          Text('Discount Preview',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: previewQuantities.map((int quantity) {
                return ListTile(
                  title: Text('$quantity prints:'),
                  trailing: Text(
                    'Rp ${_discountedTotal(quantity)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Preview of discounted prices based on current settings',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _ExtraPrintSection extends StatelessWidget {
  const _ExtraPrintSection({required this.config});

  final PhotoBoothConfig config;

  int _totalFor(int quantity) {
    final int cappedQuantity = quantity.clamp(1, config.maximumExtraPrints);
    final int subtotal = cappedQuantity * config.extraPrintPriceIdr;
    if (cappedQuantity < config.extraPrintDiscountThreshold) {
      return subtotal;
    }
    final double multiplier = (100 - config.extraPrintDiscountPercentage) / 100;
    return (subtotal * multiplier).round();
  }

  int _savedFor(int quantity) {
    final int cappedQuantity = quantity.clamp(1, config.maximumExtraPrints);
    final int subtotal = cappedQuantity * config.extraPrintPriceIdr;
    return subtotal - _totalFor(cappedQuantity);
  }

  @override
  Widget build(BuildContext context) {
    final List<int> previewQuantities = <int>{
      1,
      config.extraPrintDiscountThreshold,
      config.maximumExtraPrints
    }.toList()
      ..sort();

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Extra Print (Ultimate Version Only)'),
            subtitle: const Text(
                'If enabled, guests can purchase additional prints after their photo session.'),
            value: config.enableExtraPrint,
            onChanged: config.setEnableExtraPrint,
          ),
          const SizedBox(height: 12),
          _NumberField(
            label: 'Extra Print Price (IDR)',
            value: config.extraPrintPriceIdr,
            onChanged: config.setExtraPrintPriceIdr,
            enabled: config.enableExtraPrint,
            helperText: 'Price per extra print in Indonesian Rupiah.',
          ),
          const SizedBox(height: 16),
          _NumberField(
            label: 'Discount Percentage (%)',
            value: config.extraPrintDiscountPercentage,
            onChanged: config.setExtraPrintDiscountPercentage,
            enabled: config.enableExtraPrint,
            helperText:
                'Discount percentage applied when threshold is reached.',
          ),
          const SizedBox(height: 16),
          _NumberField(
            label: 'Discount Threshold (Minimum Quantity)',
            value: config.extraPrintDiscountThreshold,
            onChanged: config.setExtraPrintDiscountThreshold,
            enabled: config.enableExtraPrint,
            helperText:
                'Minimum number of extra prints to qualify for discount.',
          ),
          const SizedBox(height: 16),
          _NumberField(
            label: 'Maximum Extra Prints',
            value: config.maximumExtraPrints,
            onChanged: config.setMaximumExtraPrints,
            enabled: config.enableExtraPrint,
            helperText: 'Maximum number of extra prints a guest can purchase.',
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Extra Print Payment'),
            subtitle: const Text(
                'Enable payment for extra prints when main payment is disabled.'),
            value: config.enableExtraPrintPayment,
            onChanged: config.enableExtraPrint
                ? config.setEnableExtraPrintPayment
                : null,
          ),
          const SizedBox(height: 16),
          Text('Price Preview', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: previewQuantities.map((int quantity) {
                final int total = _totalFor(quantity);
                final int saved = _savedFor(quantity);
                return ListTile(
                  title: Text('$quantity print${quantity > 1 ? 's' : ''}:'),
                  subtitle: saved > 0 ? Text('Save Rp $saved') : null,
                  trailing: Text(
                    'Rp $total',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Preview of extra print prices with discount applied',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.helperText,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FieldLabel(label),
        TextFormField(
          key: ValueKey<String>('$label-$value-$enabled'),
          initialValue: '$value',
          enabled: enabled,
          keyboardType: TextInputType.number,
          onChanged: (String next) {
            final int? parsed = int.tryParse(next);
            if (parsed != null) {
              onChanged(parsed);
            }
          },
          decoration: InputDecoration(helperText: helperText),
        ),
      ],
    );
  }
}

class _TextValueField extends StatelessWidget {
  const _TextValueField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.obscure = false,
    this.hintText,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool obscure;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FieldLabel(label),
        TextFormField(
          key: ValueKey<String>('$label-$value-$enabled-$obscure'),
          initialValue: value,
          enabled: enabled,
          obscureText: obscure,
          onChanged: onChanged,
          decoration: InputDecoration(hintText: hintText),
        ),
      ],
    );
  }
}
