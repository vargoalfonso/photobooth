import 'package:flutter/material.dart';

import '../services/canon_camera_service.dart';
import '../state/photo_booth_config.dart';
import '../theme/app_theme.dart';

/// Setup wizard 5 langkah: branding, kamera Canon, sesi foto, printer, siap buka.
class SetupWizardPage extends StatefulWidget {
  const SetupWizardPage({
    super.key,
    required this.config,
    required this.canon,
  });

  final PhotoBoothConfig config;
  final CanonCameraService canon;

  @override
  State<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends State<SetupWizardPage> {
  int _step = 0;
  late final TextEditingController _nameController;
  late final TextEditingController _taglineController;

  static const List<String> _titles = <String>[
    'Branding Booth',
    'Kamera Canon',
    'Alur Sesi Foto',
    'Printer & Output',
    'Siap Beroperasi',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.config.boothName);
    _taglineController =
        TextEditingController(text: widget.config.boothTagline);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[widget.config, widget.canon]),
      builder: (BuildContext context, _) {
        return Scaffold(
          body: AppBackground(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            IconButton.filledTonal(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.close),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'Setup Wizard',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                  Text(
                                    'Langkah ${_step + 1} dari ${_titles.length} — ${_titles[_step]}',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: List<Widget>.generate(
                            _titles.length,
                            (int index) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  height: 6,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    gradient: index <= _step
                                        ? AppTheme.accentGradient
                                        : null,
                                    color: index <= _step
                                        ? null
                                        : const Color(0xFF232C45),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Expanded(
                          child: SingleChildScrollView(
                            child: GlassCard(
                              padding: const EdgeInsets.all(24),
                              child: _buildStep(context),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: _step == 0
                                  ? null
                                  : () => setState(() => _step -= 1),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Kembali'),
                            ),
                            const Spacer(),
                            GradientButton(
                              label: _step == _titles.length - 1
                                  ? 'Selesai & Buka Booth'
                                  : 'Lanjut',
                              icon: _step == _titles.length - 1
                                  ? Icons.rocket_launch
                                  : Icons.arrow_forward,
                              onPressed: () {
                                if (_step == _titles.length - 1) {
                                  widget.config
                                      .setBoothName(_nameController.text);
                                  widget.config
                                      .setBoothTagline(_taglineController.text);
                                  Navigator.of(context)
                                      .pushReplacementNamed('/booth');
                                } else {
                                  setState(() => _step += 1);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
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

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(
              title: 'Identitas booth',
              subtitle: 'Nama dan tagline tampil di layar Tap to Start.',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nama booth'),
              onChanged: widget.config.setBoothName,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _taglineController,
              decoration: const InputDecoration(labelText: 'Tagline'),
              onChanged: widget.config.setBoothTagline,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/appearance'),
              icon: const Icon(Icons.palette_outlined),
              label: const Text('Atur warna, logo, dan background'),
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: 'Canon EOS R100',
              subtitle: widget.canon.statusMessage,
              trailing: StatusBadge(
                label: widget.canon.state.isConnected ? 'Connected' : 'Offline',
                color: widget.canon.state.isConnected
                    ? AppTheme.mint
                    : AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            const _Bullet(
                'Colok kamera ke PC booth lewat USB, atau aktifkan CCAPI Wi-Fi.'),
            const _Bullet('Set mode kamera ke M / Av, matikan auto power off.'),
            const _Bullet('Pastikan lensa terpasang dan tutup lensa dilepas.'),
            const _Bullet('Gunakan adaptor listrik / dummy battery untuk event panjang.'),
            const SizedBox(height: 18),
            GradientButton(
              label: 'Buka Canon Setup',
              icon: Icons.camera,
              gradient: AppTheme.coolGradient,
              onPressed: () => Navigator.of(context).pushNamed('/canon'),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(
              title: 'Alur sesi foto',
              subtitle: 'Jumlah foto dan countdown per pengambilan.',
            ),
            const SizedBox(height: 16),
            Text('Jumlah foto per sesi: ${widget.config.photosPerSession}',
                style: Theme.of(context).textTheme.titleSmall),
            Slider(
              value: widget.config.photosPerSession.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              label: '${widget.config.photosPerSession}',
              onChanged: (double value) =>
                  widget.config.setPhotosPerSession(value.round()),
            ),
            const SizedBox(height: 10),
            Text('Countdown: ${widget.config.countdownSeconds} detik',
                style: Theme.of(context).textTheme.titleSmall),
            Slider(
              value: widget.config.countdownSeconds.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '${widget.config.countdownSeconds}s',
              onChanged: (double value) =>
                  widget.config.setCountdownSeconds(value.round()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.config.enableRetakeButton,
              onChanged: widget.config.setEnableRetakeButton,
              title: const Text('Izinkan retake foto'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.config.showFlashOverlay,
              onChanged: widget.config.setShowFlashOverlay,
              title: const Text('Efek flash saat jepret'),
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(
              title: 'Printer & output',
              subtitle: 'Atur printer utama dan mode cetak.',
            ),
            const SizedBox(height: 16),
            _Bullet('Printer aktif: ${widget.config.primaryPrinter}'),
            _Bullet('Mode cetak: ${widget.config.printMode.label}'),
            _Bullet(
                'Auto print di halaman hasil: ${widget.config.autoPrintOnOutputPage ? 'Aktif' : 'Nonaktif'}'),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/settings'),
              icon: const Icon(Icons.print),
              label: const Text('Buka pengaturan printer'),
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(
              title: 'Semua siap!',
              subtitle: 'Ringkasan konfigurasi booth kamu.',
            ),
            const SizedBox(height: 16),
            _Bullet('Booth: ${widget.config.boothName}'),
            _Bullet(
                'Kamera: ${widget.config.useCanonCamera ? 'Canon EOS R100' : 'Kamera perangkat'}'),
            _Bullet('Frame: ${widget.config.frame.name}'),
            _Bullet('Filter: ${widget.config.filter.label}'),
            _Bullet(
                'Sesi: ${widget.config.photosPerSession} foto, countdown ${widget.config.countdownSeconds}s'),
          ],
        );
    }
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.check_circle_outline,
                size: 16, color: AppTheme.mint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    )),
          ),
        ],
      ),
    );
  }
}
