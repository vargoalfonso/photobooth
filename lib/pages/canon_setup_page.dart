import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/booth_models.dart';
import '../services/canon_camera_service.dart';
import '../state/photo_booth_config.dart';
import '../theme/app_theme.dart';

/// Halaman setup koneksi Canon EOS R100.
///
/// Di sini operator booth mengatur mode koneksi (USB tether bridge atau CCAPI
/// Wi-Fi), tes koneksi, cek live view, dan mengirim setting eksposur ke kamera.
class CanonSetupPage extends StatefulWidget {
  const CanonSetupPage({
    super.key,
    required this.config,
    required this.canon,
  });

  final PhotoBoothConfig config;
  final CanonCameraService canon;

  @override
  State<CanonSetupPage> createState() => _CanonSetupPageState();
}

class _CanonSetupPageState extends State<CanonSetupPage> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _folderController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.canon.host);
    _portController = TextEditingController(text: '${widget.canon.port}');
    _folderController =
        TextEditingController(text: widget.canon.downloadDirectory);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.danger : AppTheme.surfaceHigh,
      ),
    );
  }

  Future<void> _applyEndpoint() async {
    widget.canon.setHost(_hostController.text);
    widget.canon.setPort(
      int.tryParse(_portController.text) ?? widget.canon.mode.defaultPort,
    );
    widget.canon.setDownloadDirectory(_folderController.text.trim());
  }

  Future<void> _testConnection() async {
    setState(() => _busy = true);
    await _applyEndpoint();
    final bool ok = await widget.canon.connect();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    _snack(
      ok
          ? 'Kamera terhubung: ${widget.canon.deviceInfo.model}'
          : widget.canon.statusMessage,
      error: !ok,
    );
  }

  Future<void> _toggleLiveView() async {
    if (widget.canon.liveViewRunning) {
      widget.canon.stopLiveView();
      return;
    }
    setState(() => _busy = true);
    await widget.canon.startLiveView(fps: widget.config.canonLiveViewFps);
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _pushExposure() async {
    setState(() => _busy = true);
    final bool ok = await widget.canon.applyExposureSettings(
      iso: widget.config.isoSetting.label,
      aperture: widget.config.apertureSetting.label,
      shutterSpeed: widget.config.shutterSpeed.label,
      whiteBalance: widget.config.whiteBalancePreset.label,
    );
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    _snack(widget.canon.statusMessage, error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[widget.canon, widget.config]),
      builder: (BuildContext context, _) {
        final CanonCameraService canon = widget.canon;

        return Scaffold(
          body: AppBackground(
            child: SafeArea(
              child: Column(
                children: <Widget>[
                  _buildHeader(context, canon),
                  Expanded(
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                        final bool wide = constraints.maxWidth >= 1080;
                        final Widget left = Column(
                          children: <Widget>[
                            _buildConnectionCard(context, canon),
                            const SizedBox(height: 16),
                            _buildBehaviourCard(context, canon),
                            const SizedBox(height: 16),
                            _buildExposureCard(context),
                          ],
                        );
                        final Widget right = Column(
                          children: <Widget>[
                            _buildLiveViewCard(context, canon),
                            const SizedBox(height: 16),
                            _buildChecklistCard(context, canon),
                            const SizedBox(height: 16),
                            _buildLogCard(context, canon),
                          ],
                        );

                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
                          child: wide
                              ? Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(flex: 5, child: left),
                                    const SizedBox(width: 18),
                                    Expanded(flex: 4, child: right),
                                  ],
                                )
                              : Column(
                                  children: <Widget>[
                                    left,
                                    const SizedBox(height: 16),
                                    right,
                                  ],
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, CanonCameraService canon) {
    final Color statusColor = switch (canon.state) {
      CanonConnectionState.connected => AppTheme.mint,
      CanonConnectionState.connecting => AppTheme.sky,
      CanonConnectionState.error => AppTheme.danger,
      CanonConnectionState.disconnected => AppTheme.textMuted,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      child: Row(
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
                  'Canon EOS R100 Setup',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Sambungkan lensa Canon sebagai sumber utama live view & capture booth.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          StatusBadge(
            label: switch (canon.state) {
              CanonConnectionState.connected => 'Connected',
              CanonConnectionState.connecting => 'Connecting',
              CanonConnectionState.error => 'Error',
              CanonConnectionState.disconnected => 'Offline',
            },
            color: statusColor,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(BuildContext context, CanonCameraService canon) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'Koneksi Kamera',
            subtitle: canon.statusMessage,
            trailing: Switch(
              value: canon.enabled,
              onChanged: (bool value) {
                canon.setEnabled(value);
                widget.config.setUseCanonCamera(value);
              },
            ),
          ),
          const SizedBox(height: 18),
          ...CanonConnectionMode.values.map(
            (CanonConnectionMode mode) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ModeTile(
                mode: mode,
                selected: canon.mode == mode,
                onTap: () {
                  canon.setMode(mode);
                  _portController.text = '${canon.port}';
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _hostController,
                  decoration: InputDecoration(
                    labelText: canon.mode == CanonConnectionMode.ccapiWifi
                        ? 'IP kamera (lihat di menu Wi-Fi kamera)'
                        : 'Host bridge (biasanya 127.0.0.1)',
                    prefixIcon: const Icon(Icons.lan_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _folderController,
            decoration: const InputDecoration(
              labelText: 'Folder simpan hasil foto (opsional)',
              hintText: r'contoh: C:\Booth\Captures',
              prefixIcon: Icon(Icons.folder_open),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              GradientButton(
                label: _busy ? 'Menghubungkan...' : 'Test Connection',
                icon: Icons.sensors,
                onPressed: _busy ? null : _testConnection,
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: canon.state.isConnected
                    ? () => canon.disconnect()
                    : null,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBehaviourCard(BuildContext context, CanonCameraService canon) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(
            title: 'Perilaku Booth',
            subtitle: 'Bagaimana kamera dipakai saat sesi berjalan.',
          ),
          const SizedBox(height: 8),
          _SwitchRow(
            title: 'Pakai Canon sebagai kamera booth',
            subtitle:
                'Live view dan hasil foto diambil dari EOS R100, bukan webcam.',
            value: widget.config.useCanonCamera,
            onChanged: (bool value) {
              widget.config.setUseCanonCamera(value);
              canon.setEnabled(value);
            },
          ),
          _SwitchRow(
            title: 'Auto connect saat aplikasi dibuka',
            subtitle: 'Booth langsung mencari kamera ketika start.',
            value: canon.autoConnectOnStart,
            onChanged: canon.setAutoConnectOnStart,
          ),
          _SwitchRow(
            title: 'Autofocus sebelum jepret',
            subtitle: 'AF dijalankan saat countdown mencapai 1 detik.',
            value: widget.config.canonAutoFocusBeforeShot,
            onChanged: widget.config.setCanonAutoFocusBeforeShot,
          ),
          _SwitchRow(
            title: 'Simpan juga ke kartu memori kamera',
            subtitle: 'Backup file RAW/JPG tetap ada di SD card.',
            value: canon.saveToCameraCard,
            onChanged: canon.setSaveToCameraCard,
          ),
          _SwitchRow(
            title: 'Download foto ke PC setelah jepret',
            subtitle: 'Dibutuhkan untuk preview, filter, dan cetak.',
            value: canon.downloadAfterCapture,
            onChanged: canon.setDownloadAfterCapture,
          ),
          const SizedBox(height: 8),
          Text(
            'Live view FPS: ${widget.config.canonLiveViewFps}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Slider(
            value: widget.config.canonLiveViewFps.toDouble(),
            min: 5,
            max: 30,
            divisions: 25,
            label: '${widget.config.canonLiveViewFps} fps',
            onChanged: (double value) =>
                widget.config.setCanonLiveViewFps(value.round()),
          ),
        ],
      ),
    );
  }

  Widget _buildExposureCard(BuildContext context) {
    final PhotoBoothConfig config = widget.config;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(
            title: 'Eksposur Kamera',
            subtitle: 'Nilai ini dikirim langsung ke Canon saat disimpan.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _MiniDropdown<BoothIsoSetting>(
                label: 'ISO',
                value: config.isoSetting,
                items: BoothIsoSetting.values,
                labelBuilder: (BoothIsoSetting v) => v.label,
                onChanged: (BoothIsoSetting v) => config.setIsoSetting(v),
              ),
              _MiniDropdown<BoothApertureSetting>(
                label: 'Aperture',
                value: config.apertureSetting,
                items: BoothApertureSetting.values,
                labelBuilder: (BoothApertureSetting v) => v.label,
                onChanged: (BoothApertureSetting v) =>
                    config.setApertureSetting(v),
              ),
              _MiniDropdown<BoothShutterSpeed>(
                label: 'Shutter',
                value: config.shutterSpeed,
                items: BoothShutterSpeed.values,
                labelBuilder: (BoothShutterSpeed v) => v.label,
                onChanged: (BoothShutterSpeed v) => config.setShutterSpeed(v),
              ),
              _MiniDropdown<BoothWhiteBalancePreset>(
                label: 'White Balance',
                value: config.whiteBalancePreset,
                items: BoothWhiteBalancePreset.values,
                labelBuilder: (BoothWhiteBalancePreset v) => v.label,
                onChanged: (BoothWhiteBalancePreset v) =>
                    config.setWhiteBalancePreset(v),
              ),
            ],
          ),
          const SizedBox(height: 18),
          GradientButton(
            label: 'Kirim ke Kamera',
            icon: Icons.upload,
            gradient: AppTheme.coolGradient,
            onPressed: _busy ? null : _pushExposure,
          ),
        ],
      ),
    );
  }

  Widget _buildLiveViewCard(BuildContext context, CanonCameraService canon) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'Live View Test',
            subtitle: canon.liveViewRunning
                ? 'Streaming aktif dari lensa Canon.'
                : 'Jalankan untuk memastikan lensa Canon tampil di booth.',
            trailing: StatusBadge(
              label: canon.liveViewRunning ? 'Live' : 'Idle',
              color: canon.liveViewRunning ? AppTheme.mint : AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 3 / 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: canon.liveViewFrame != null
                    ? Image.memory(
                        canon.liveViewFrame!,
                        gaplessPlayback: true,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.camera_outlined,
                              size: 44, color: AppTheme.textMuted),
                          const SizedBox(height: 10),
                          Text(
                            'Belum ada frame dari kamera',
                            style: Theme.of(context).textTheme.bodyMedium,
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
                child: FilledButton.icon(
                  onPressed: canon.state.isConnected && !_busy
                      ? _toggleLiveView
                      : null,
                  icon: Icon(canon.liveViewRunning
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline),
                  label: Text(
                      canon.liveViewRunning ? 'Stop Live View' : 'Start Live View'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canon.state.isConnected && !_busy
                      ? () async {
                          final CanonCaptureResult result =
                              await canon.capture();
                          _snack(
                            result.success
                                ? 'Test shot berhasil${result.filePath != null ? ': ${result.filePath}' : ''}'
                                : result.message ?? 'Test shot gagal.',
                            error: !result.success,
                          );
                        }
                      : null,
                  icon: const Icon(Icons.camera),
                  label: const Text('Test Shot'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistCard(BuildContext context, CanonCameraService canon) {
    final List<_ChecklistItem> items = <_ChecklistItem>[
      _ChecklistItem(
        'Mode kamera di posisi M / Av dan lensa terpasang',
        canon.deviceInfo.lens != '-',
      ),
      _ChecklistItem(
        'Kamera terdeteksi aplikasi',
        canon.state.isConnected,
      ),
      _ChecklistItem(
        'Live view aktif',
        canon.liveViewRunning,
      ),
      _ChecklistItem(
        'Auto power off kamera dimatikan (menu kamera)',
        canon.state.isConnected,
      ),
      _ChecklistItem(
        'Folder penyimpanan hasil sudah diisi',
        canon.downloadDirectory.isNotEmpty,
      ),
    ];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(
            title: 'Checklist Setup',
            subtitle: 'Pastikan semua hijau sebelum booth dibuka.',
          ),
          const SizedBox(height: 14),
          ...items.map(
            (_ChecklistItem item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: <Widget>[
                  Icon(
                    item.done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 20,
                    color: item.done ? AppTheme.mint : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: item.done
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.sky.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.sky.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.info_outline,
                        size: 18, color: AppTheme.sky),
                    const SizedBox(width: 8),
                    Text(
                      'Info perangkat',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _InfoLine('Model', canon.deviceInfo.model),
                _InfoLine('Lensa', canon.deviceInfo.lens),
                _InfoLine('Firmware', canon.deviceInfo.firmware),
                _InfoLine('Baterai', canon.deviceInfo.batteryLevel),
                _InfoLine('Sisa kartu', canon.deviceInfo.storageRemaining),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(BuildContext context, CanonCameraService canon) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'Log Koneksi',
            subtitle: 'Riwayat terakhir komunikasi dengan kamera.',
            trailing: IconButton(
              onPressed: () => canon.refreshStatus(),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh status',
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 160,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: canon.log.isEmpty
                ? const Center(
                    child: Text(
                      'Belum ada aktivitas.',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: canon.log.length,
                    itemBuilder: (BuildContext context, int index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        canon.log[index],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistItem {
  const _ChecklistItem(this.label, this.done);

  final String label;
  final bool done;
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final CanonConnectionMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.stroke,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              mode == CanonConnectionMode.ccapiWifi
                  ? Icons.wifi
                  : Icons.usb,
              color: selected ? AppTheme.accent : AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    mode.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textMuted,
                        ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppTheme.accent, size: 20),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _MiniDropdown<T> extends StatelessWidget {
  const _MiniDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        dropdownColor: AppTheme.surfaceHigh,
        items: items
            .map(
              (T item) => DropdownMenuItem<T>(
                value: item,
                child: Text(
                  labelBuilder(item),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (T? selected) {
          if (selected != null) {
            onChanged(selected);
          }
        },
      ),
    );
  }
}
