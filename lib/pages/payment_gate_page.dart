// Gerbang pembayaran: tampil di awal sesi booth.
//
// Alur:
//   1. Ambil paket dari dashboard (GET /api/packages) -> pelanggan pilih paket.
//   2. Buat pembayaran (POST /api/payments) -> dashboard mengembalikan link
//      pembayaran Midtrans yang ditampilkan sebagai QR.
//   3. Polling status (GET /api/payments/{order_id}) sampai `paid`.
//   4. Setelah paid, halaman ini pop dengan [PaidSession]. Selama belum paid,
//      booth tidak boleh lanjut (tombol back dikunci, hanya bisa Batal).
//
// Return: `PaidSession` bila lunas, `null` bila dibatalkan.

import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/payment_models.dart';
import '../services/monolith_api_client.dart';
import '../services/photobooth_api_service.dart';
import '../state/photo_booth_config.dart';
import '../theme/app_theme.dart';

enum _GateStep { loadingPackages, choosePackage, creating, waiting, paid, failed }

class PaymentGatePage extends StatefulWidget {
  const PaymentGatePage({super.key, required this.config});

  final PhotoBoothConfig config;

  @override
  State<PaymentGatePage> createState() => _PaymentGatePageState();
}

class _PaymentGatePageState extends State<PaymentGatePage> {
  static const Duration _pollInterval = Duration(seconds: 2);

  /// Toleransi setelah countdown habis sebelum kiosk menganggap kedaluwarsa
  /// (memberi waktu callback Midtrans / status terakhir masuk).
  static const Duration _expiryGrace = Duration(seconds: 20);

  PhotoboothApiService? _svc;
  _GateStep _step = _GateStep.loadingPackages;
  List<PackageDto> _packages = const <PackageDto>[];
  PaymentDto? _payment;
  String? _message;
  bool _apiMissing = false;
  bool _cancelling = false;
  bool _finished = false;

  Timer? _pollTimer;
  Timer? _tickTimer;
  bool _polling = false;
  int _pollErrors = 0;

  /// Selisih jam server - perangkat, supaya countdown akurat walau jam
  /// perangkat kiosk meleset.
  Duration _clockOffset = Duration.zero;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  @override
  void dispose() {
    _stopTimers();
    _svc?.close();
    super.dispose();
  }

  // ------------------------------------------------------------- lifecycle

  void _initService() {
    _svc?.close();
    _svc = PhotoboothApiService.fromConfig(widget.config);
    if (_svc == null) {
      _apiMissing = true;
      _step = _GateStep.failed;
      _message =
          'Base URL API masih kosong, jadi pembayaran tidak bisa diverifikasi ke dashboard.';
      return;
    }
    _apiMissing = false;
    _loadPackages();
  }

  void _retry() {
    setState(() {
      _payment = null;
      _message = null;
      _pollErrors = 0;
    });
    _initService();
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _pollTimer = null;
    _tickTimer = null;
  }

  void _fail(String message) {
    if (!mounted) return;
    _stopTimers();
    setState(() {
      _step = _GateStep.failed;
      _message = message;
    });
  }

  // -------------------------------------------------------------- packages

  Future<void> _loadPackages() async {
    final PhotoboothApiService? svc = _svc;
    if (svc == null) return;

    setState(() {
      _step = _GateStep.loadingPackages;
      _message = null;
    });

    try {
      final List<PackageDto> list = await svc.listPackages();
      if (!mounted) return;

      if (list.isEmpty) {
        _fail('Belum ada paket aktif di dashboard. Buat paket dulu.');
        return;
      }

      setState(() {
        _packages = list;
        _step = _GateStep.choosePackage;
      });

      // Satu paket saja -> langsung buat pembayaran.
      if (list.length == 1) {
        unawaited(_startPayment(list.first));
      }
    } on ApiException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Tidak bisa terhubung ke dashboard: $e');
    }
  }

  // --------------------------------------------------------------- payment

  Future<void> _startPayment(PackageDto package) async {
    final PhotoboothApiService? svc = _svc;
    if (svc == null) return;

    setState(() {
      _step = _GateStep.creating;
      _message = null;
      _pollErrors = 0;
    });

    try {
      final PaymentDto payment = await svc.createPayment(
        packageId: package.id,
        boothId: widget.config.apiBoothId,
      );
      if (!mounted) return;

      final String? url = payment.paymentUrl;
      if (url == null || url.isEmpty) {
        // Jangan biarkan transaksi menggantung.
        unawaited(svc.cancelPayment(payment.orderId).then((_) {}).catchError((_) {}));
        _fail('Dashboard tidak mengembalikan link pembayaran. Cek konfigurasi Midtrans.');
        return;
      }

      _applyPayment(payment);
      setState(() => _step = _GateStep.waiting);
      _startTimers();
    } on ApiException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Gagal membuat pembayaran: $e');
    }
  }

  void _applyPayment(PaymentDto payment) {
    _payment = payment;
    final DateTime? serverTime = payment.serverTime;
    if (serverTime != null) {
      _clockOffset = serverTime.difference(DateTime.now());
    }
    _recomputeRemaining();
  }

  DateTime get _serverNow => DateTime.now().add(_clockOffset);

  void _recomputeRemaining() {
    final DateTime? expiresAt = _payment?.expiresAt;
    if (expiresAt == null) {
      _remaining = Duration.zero;
      return;
    }
    final Duration diff = expiresAt.difference(_serverNow);
    _remaining = diff.isNegative ? Duration.zero : diff;
  }

  void _startTimers() {
    _stopTimers();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _step != _GateStep.waiting) return;
      setState(_recomputeRemaining);
    });
  }

  Future<void> _poll() async {
    final PhotoboothApiService? svc = _svc;
    final PaymentDto? current = _payment;
    if (_polling ||
        svc == null ||
        current == null ||
        _step != _GateStep.waiting) {
      return;
    }

    _polling = true;
    try {
      final PaymentDto latest = await svc.getPayment(current.orderId);
      if (!mounted || _step != _GateStep.waiting) return;

      setState(() {
        _pollErrors = 0;
        _message = null;
        _applyPayment(latest);
      });

      if (latest.paid && latest.session != null) {
        _onPaid(latest);
        return;
      }
      if (latest.expired) {
        _onExpired();
        return;
      }

      final DateTime? expiresAt = latest.expiresAt;
      if (expiresAt != null &&
          _serverNow.isAfter(expiresAt.add(_expiryGrace))) {
        await _expireWithServer(svc, latest.orderId);
      }
    } catch (_) {
      // Gangguan jaringan sesaat tidak boleh menggagalkan pembayaran;
      // polling terus berjalan. Beri tahu bila terputus agak lama.
      _pollErrors++;
      if (mounted && _pollErrors >= 5 && _step == _GateStep.waiting) {
        setState(() => _message =
            'Koneksi ke dashboard terputus, mencoba menghubungkan lagi...');
      }
    } finally {
      _polling = false;
    }
  }

  /// Waktu habis tapi server masih "pending": batalkan di server. Kalau
  /// ternyata sudah dibayar pada detik terakhir, tetap lanjut.
  Future<void> _expireWithServer(
    PhotoboothApiService svc,
    String orderId,
  ) async {
    try {
      final PaymentDto result = await svc.cancelPayment(orderId);
      if (!mounted) return;
      if (result.paid && result.session != null) {
        _onPaid(result);
        return;
      }
    } catch (_) {
      // abaikan; tetap tampilkan kedaluwarsa.
    }
    if (mounted) _onExpired();
  }

  void _onPaid(PaymentDto payment) {
    final PaymentSessionDto? session = payment.session;
    if (session == null || _finished) return;

    _stopTimers();
    setState(() {
      _payment = payment;
      _step = _GateStep.paid;
    });

    final PaidSession result = PaidSession(
      sessionId: session.id,
      sessionCode: session.sessionCode,
      allowedTakes:
          session.allowedTakes > 0 ? session.allowedTakes : payment.takes,
      orderId: payment.orderId,
    );

    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted || _finished) return;
      _finished = true;
      Navigator.of(context).pop(result);
    });
  }

  void _onExpired() {
    _fail('Waktu pembayaran habis atau dibatalkan. Silakan coba lagi.');
  }

  // ------------------------------------------------------------------ exit

  Future<void> _requestExit() async {
    if (_finished || _cancelling) return;

    switch (_step) {
      case _GateStep.paid:
      case _GateStep.creating:
        return; // tidak bisa keluar saat transaksi dibuat / sudah lunas.
      case _GateStep.waiting:
        final bool? confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Batalkan pembayaran?'),
            content: const Text(
                'QR yang sedang tampil tidak akan berlaku lagi.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Lanjut bayar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Batalkan'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        await _cancelAndExit();
      case _GateStep.loadingPackages:
      case _GateStep.choosePackage:
      case _GateStep.failed:
        await _cancelAndExit();
    }
  }

  Future<void> _cancelAndExit() async {
    if (_finished || _cancelling) return;
    setState(() => _cancelling = true);
    _stopTimers();

    final PhotoboothApiService? svc = _svc;
    final PaymentDto? payment = _payment;
    if (svc != null && payment != null && !payment.paid) {
      try {
        // Ditunggu dulu (bukan fire-and-forget) karena client ditutup di dispose.
        final PaymentDto result = await svc
            .cancelPayment(payment.orderId)
            .timeout(const Duration(seconds: 6));
        if (mounted && result.paid && result.session != null) {
          // Ternyata sudah dibayar: jangan dibuang, lanjutkan sesi.
          setState(() => _cancelling = false);
          _onPaid(result);
          return;
        }
      } catch (_) {
        // best effort.
      }
    }

    if (!mounted) return;
    _finished = true;
    Navigator.of(context).pop();
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          unawaited(_requestExit());
        }
      },
      child: Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: GlassCard(
                    padding: const EdgeInsets.all(28),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(
                        key: ValueKey<_GateStep>(_step),
                        child: _buildBody(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (_step) {
      _GateStep.loadingPackages =>
        _buildBusy(context, 'Memuat paket dari dashboard...'),
      _GateStep.creating => _buildBusy(context, 'Membuat QR pembayaran...'),
      _GateStep.choosePackage => _buildPackages(context),
      _GateStep.waiting => _buildWaiting(context),
      _GateStep.paid => _buildPaid(context),
      _GateStep.failed => _buildFailed(context),
    };
  }

  Widget _buildBusy(BuildContext context, String label) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            label,
            style: text.titleMedium?.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPackages(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Pilih Paket Foto',
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Bayar dulu dengan scan QR, lalu sesi foto dimulai.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 22),
        for (final PackageDto package in _packages) ...<Widget>[
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            onTap: () => _startPayment(package),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        package.name,
                        style: text.titleMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${package.takes} foto'
                        '${package.description == null || package.description!.isEmpty ? '' : ' • ${package.description}'}',
                        style: text.bodyMedium
                            ?.copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  _rupiah(package.price),
                  style: text.titleLarge?.copyWith(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        TextButton(
          onPressed: _cancelling ? null : _requestExit,
          child: const Text('Kembali'),
        ),
      ],
    );
  }

  Widget _buildWaiting(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final PaymentDto? payment = _payment;
    final String url = payment?.paymentUrl ?? '';

    final int minutes = _remaining.inMinutes;
    final int seconds = _remaining.inSeconds % 60;
    final String countdown =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Scan untuk Membayar',
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Scan QR dengan kamera HP, lalu selesaikan pembayaran '
          '(QRIS / e-wallet / transfer).',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: QrImageView(
              data: url,
              version: QrVersions.auto,
              size: 280,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              _rupiah(payment?.amount ?? 0),
              style: text.titleLarge?.copyWith(
                color: AppTheme.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 18),
            const Icon(Icons.timer_outlined,
                size: 20, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              countdown,
              style: text.titleLarge?.copyWith(
                color: _remaining.inSeconds <= 30
                    ? AppTheme.danger
                    : AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _message ?? 'Menunggu pembayaran...',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: _message == null
                      ? AppTheme.textSecondary
                      : AppTheme.accentAlt,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: _cancelling ? null : _requestExit,
            child: Text(_cancelling ? 'Membatalkan...' : 'Batal'),
          ),
        ),
      ],
    );
  }

  Widget _buildPaid(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.check_circle_rounded,
              size: 88, color: AppTheme.mint),
          const SizedBox(height: 16),
          Text(
            'Pembayaran Berhasil',
            style: text.headlineSmall?.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Menyiapkan sesi foto...',
            style: text.bodyMedium?.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildFailed(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Icon(Icons.error_outline_rounded,
            size: 64, color: AppTheme.danger),
        const SizedBox(height: 14),
        Text(
          'Pembayaran Belum Bisa Dilanjutkan',
          textAlign: TextAlign.center,
          style: text.titleLarge?.copyWith(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _message ?? 'Terjadi kesalahan.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 22),
        GradientButton(
          label: 'Coba Lagi',
          icon: Icons.refresh_rounded,
          expand: true,
          onPressed: _cancelling ? null : _retry,
        ),
        const SizedBox(height: 8),
        if (_apiMissing)
          TextButton(
            onPressed: () async {
              await Navigator.of(context).pushNamed('/api-settings');
              // Balik dari pengaturan: coba lagi otomatis dengan config terbaru.
              if (mounted && !_finished) _retry();
            },
            child: const Text('Buka Pengaturan API'),
          ),
        TextButton(
          onPressed: _cancelling ? null : _requestExit,
          child: const Text('Kembali'),
        ),
      ],
    );
  }
}

/// 35000 -> "Rp35.000".
String _rupiah(int value) {
  final String digits = value.toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    final int fromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      buffer.write('.');
    }
  }
  return 'Rp$buffer';
}
