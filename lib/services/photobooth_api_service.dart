// High-level service yang membungkus MonolithApiClient sesuai kontrak
// endpoint monolith Laravel (routes/api.php + Api/PhotoboothController.php).
//
// Semua fungsi menerjemahkan JSON menjadi DTO Dart yang bersih supaya UI
// Flutter tidak perlu tahu bentuk paginator/response Laravel.

import 'dart:typed_data';

import '../models/api_models.dart';
import '../models/booth_models.dart';
import '../models/payment_models.dart';
import '../state/photo_booth_config.dart';
import 'monolith_api_client.dart';

class PhotoboothApiService {
  PhotoboothApiService(this._client);

  final MonolithApiClient _client;

  MonolithApiClient get client => _client;

  /// Factory dari config booth. Return null bila API dimatikan / baseUrl
  /// kosong sehingga caller tidak perlu handle kondisi "belum di-setup".
  static PhotoboothApiService? fromConfig(PhotoBoothConfig config) {
    if (!config.apiEnabled) return null;
    final String base = config.apiBaseUrl.trim();
    if (base.isEmpty) return null;
    final MonolithApiClient client = MonolithApiClient(
      baseUrl: base,
      token: config.apiAuthToken.isEmpty ? null : config.apiAuthToken,
    );
    return PhotoboothApiService(client);
  }

  void close() => _client.close();

  // ----------------------------------------------------------------- Health

  /// Ping ringan: cek apakah endpoint `templates` bisa diakses.
  Future<bool> ping() async {
    try {
      await _client.getJson('templates');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- Frames

  /// GET /api/templates?category=... — daftar frame aktif.
  Future<List<PhotoFrameDto>> listTemplates({String? category}) async {
    final Map<String, dynamic> raw = await _client.getJson(
      'templates',
      query: category == null || category.isEmpty
          ? null
          : <String, dynamic>{'category': category},
    );

    final Object? data = raw['data'];
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(PhotoFrameDto.fromJson)
          .toList(growable: false);
    }
    return const <PhotoFrameDto>[];
  }

  /// GET /api/templates lalu ubah jadi [BoothFrameOption] bertipe template
  /// (strip vertikal dengan posisi slot dari `layout_json`). Template tanpa
  /// slot dilewati karena tidak bisa diisi foto.
  Future<List<BoothFrameOption>> listRemoteFrames({String? category}) async {
    final List<PhotoFrameDto> dtos = await listTemplates(category: category);
    final String host = _client.hostBaseUrl;
    return dtos
        .where((PhotoFrameDto d) => d.isActive && d.slotCount > 0)
        .map((PhotoFrameDto d) =>
            BoothFrameOption.fromTemplate(d, hostBaseUrl: host))
        .where((BoothFrameOption f) => f.slotCount > 0)
        .toList(growable: false);
  }

  /// GET /api/frame-backgrounds -> peta `frame_key` ke [FrameBackgroundInfo]
  /// (gambar background + area foto) untuk frame bawaan Flutter.
  Future<Map<String, FrameBackgroundInfo>> listFrameBackgrounds() async {
    final Map<String, dynamic> raw = await _client.getJson('frame-backgrounds');
    final Object? data = raw['data'];
    final RegExp leadingSlashes = RegExp(r'^/+');
    final String host = _client.hostBaseUrl;
    final Map<String, FrameBackgroundInfo> result =
        <String, FrameBackgroundInfo>{};

    double num0(Object? v, double fallback) =>
        v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? fallback);

    if (data is List) {
      for (final Map<String, dynamic> item
          in data.whereType<Map<String, dynamic>>()) {
        final String key = item['frame_key']?.toString() ?? '';
        String url = item['image_url']?.toString() ?? '';
        if (key.isEmpty || url.isEmpty) continue;
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          url = '$host/${url.replaceAll(leadingSlashes, '')}';
        }

        final double w = num0(item['width'], 0);
        final double h = num0(item['height'], 0);
        final Object? area = item['area'];
        final Map<String, dynamic> a =
            area is Map<String, dynamic> ? area : const <String, dynamic>{};

        result[key] = FrameBackgroundInfo(
          url: url,
          aspect: (w > 0 && h > 0) ? w / h : null,
          areaX: num0(a['x'], 4),
          areaY: num0(a['y'], 3),
          areaW: num0(a['w'], 92),
          areaH: num0(a['h'], 94),
        );
      }
    }
    return result;
  }

  /// Ambil template dari server dan simpan ke [config.remoteFrames].
  /// Aman dipanggil kapan saja: gagal koneksi hanya mengisi `remoteFramesError`
  /// dan frame bawaan tetap bisa dipakai.
  static Future<void> syncFrames(PhotoBoothConfig config) async {
    final PhotoboothApiService? svc = PhotoboothApiService.fromConfig(config);
    if (svc == null) {
      config.setRemoteFrames(const <BoothFrameOption>[]);
      config.setFrameBackgrounds(const <String, FrameBackgroundInfo>{});
      return;
    }
    config.setRemoteFramesLoading(true);
    try {
      try {
        config.setRemoteFrames(await svc.listRemoteFrames());
      } on ApiException catch (e) {
        config.setRemoteFrames(config.remoteFrames, error: e.message);
      } catch (e) {
        config.setRemoteFrames(
          config.remoteFrames,
          error: 'Tidak bisa menghubungi server: $e',
        );
      }

      // Background frame bawaan. Gagal/belum ada endpoint -> pakai yang lama.
      try {
        config.setFrameBackgrounds(await svc.listFrameBackgrounds());
      } catch (_) {}
    } finally {
      svc.close();
    }
  }

  // -------------------------------------------------------------- Payments

  /// GET /api/packages — paket foto aktif.
  Future<List<PackageDto>> listPackages() async {
    final Map<String, dynamic> raw = await _client.getJson('packages');
    final Object? data = raw['data'];
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(PackageDto.fromJson)
          .toList(growable: false);
    }
    return const <PackageDto>[];
  }

  /// POST /api/payments — buat sesi pending + transaksi Midtrans.
  /// `paymentUrl` pada hasilnya adalah isi QR yang harus ditampilkan.
  Future<PaymentDto> createPayment({
    required int packageId,
    int? boothId,
    String? customerName,
  }) async {
    final Map<String, dynamic> raw = await _client.postJson(
      'payments',
      body: <String, dynamic>{
        'photo_package_id': packageId,
        if (boothId != null) 'booth_id': boothId,
        if (customerName != null && customerName.isNotEmpty)
          'customer_name': customerName,
      },
    );
    return _extractPayment(raw);
  }

  /// GET /api/payments/{order_id} — polling status.
  Future<PaymentDto> getPayment(String orderId) async {
    final Map<String, dynamic> raw =
        await _client.getJson('payments/$orderId');
    return _extractPayment(raw);
  }

  /// POST /api/payments/{order_id}/cancel — batalkan bila masih pending.
  Future<PaymentDto> cancelPayment(String orderId) async {
    final Map<String, dynamic> raw =
        await _client.postJson('payments/$orderId/cancel');
    return _extractPayment(raw);
  }

  PaymentDto _extractPayment(Map<String, dynamic> raw) {
    final Object? data = raw['data'];
    if (data is Map<String, dynamic>) {
      return PaymentDto.fromJson(data);
    }
    return PaymentDto.fromJson(raw);
  }

  // -------------------------------------------------------------- Sessions

  /// GET /api/photo-sessions — halaman sesi (paginate 20).
  Future<PhotoSessionPage> listSessions() async {
    final Map<String, dynamic> raw = await _client.getJson('photo-sessions');
    return PhotoSessionPage.fromLaravelPaginator(raw);
  }

  /// GET /api/photo-sessions/{id}.
  Future<PhotoSessionDto> getSession(int id) async {
    final Map<String, dynamic> raw =
        await _client.getJson('photo-sessions/$id');
    final Object? data = raw['data'];
    if (data is Map<String, dynamic>) {
      return PhotoSessionDto.fromJson(data);
    }
    return PhotoSessionDto.fromJson(raw);
  }

  /// POST /api/photo-sessions — buat sesi baru + upload semua foto.
  ///
  /// [photos] adalah pasangan (filename, bytes/filePath) yang mau dikirim
  /// sebagai multipart `photos[]`. [photoFrameId] wajib dan harus sama dengan
  /// jumlah slot foto pada frame terkait, sesuai validasi di
  /// [PhotoboothController::store].
  Future<PhotoSessionDto> createSession({
    required int boothId,
    required int photoFrameId,
    required List<PhotoUpload> photos,
    String? customerName,
    String? layout,
    String? filter,
    DateTime? takenAt,
  }) async {
    final Map<String, String> fields = <String, String>{
      'booth_id': boothId.toString(),
      'photo_frame_id': photoFrameId.toString(),
      if (customerName != null && customerName.isNotEmpty)
        'customer_name': customerName,
      if (layout != null && layout.isNotEmpty) 'layout': layout,
      if (filter != null && filter.isNotEmpty) 'filter': filter,
      if (takenAt != null) 'taken_at': takenAt.toIso8601String(),
    };

    final List<ApiFileUpload> files = photos
        .map(
          (PhotoUpload p) => ApiFileUpload(
            fieldName: 'photos[]',
            filename: p.filename,
            filePath: p.filePath,
            bytes: p.bytes,
          ),
        )
        .toList(growable: false);

    final Map<String, dynamic> raw = await _client.postMultipart(
      'photo-sessions',
      fields: fields,
      files: files,
    );
    return _extractSession(raw);
  }

  /// POST /api/photo-sessions/{id}/photos — tambah foto ke sesi existing.
  Future<PhotoSessionDto> addPhotos({
    required int sessionId,
    required List<PhotoUpload> photos,
  }) async {
    final List<ApiFileUpload> files = photos
        .map(
          (PhotoUpload p) => ApiFileUpload(
            fieldName: 'photos[]',
            filename: p.filename,
            filePath: p.filePath,
            bytes: p.bytes,
          ),
        )
        .toList(growable: false);

    final Map<String, dynamic> raw = await _client.postMultipart(
      'photo-sessions/$sessionId/photos',
      files: files,
    );
    return _extractSession(raw);
  }

  /// PUT /api/photo-sessions/{id} — update metadata sesi (frame/filter/dll).
  Future<PhotoSessionDto> updateSession({
    required int sessionId,
    int? photoFrameId,
    String? customerName,
    String? layout,
    String? filter,
    DateTime? takenAt,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      if (photoFrameId != null) 'photo_frame_id': photoFrameId,
      if (customerName != null) 'customer_name': customerName,
      if (layout != null) 'layout': layout,
      if (filter != null) 'filter': filter,
      if (takenAt != null) 'taken_at': takenAt.toIso8601String(),
    };
    final Map<String, dynamic> raw =
        await _client.putJson('photo-sessions/$sessionId', body: body);
    return _extractSession(raw);
  }

  /// DELETE /api/photo-sessions/{id}.
  Future<void> deleteSession(int sessionId) async {
    await _client.delete('photo-sessions/$sessionId');
  }

  /// DELETE /api/photo-sessions/{id}/photos/{media}.
  Future<void> deletePhoto({
    required int sessionId,
    required int mediaId,
  }) async {
    await _client.delete('photo-sessions/$sessionId/photos/$mediaId');
  }

  /// POST /api/photo-sessions/{id}/print — kirim email + trigger printer
  /// command (bila server dikonfigurasi PHOTOBOOTH_PRINTER_COMMAND).
  Future<PrintResult> printSession({
    required int sessionId,
    required String email,
  }) async {
    final Map<String, dynamic> raw = await _client.postJson(
      'photo-sessions/$sessionId/print',
      body: <String, dynamic>{'email': email},
    );
    return PrintResult(
      message: raw['message']?.toString() ?? 'Print job dikirim.',
      emailSent: raw['email_sent'] == true,
      printDispatched: raw['print_dispatched'] == true,
    );
  }

  // ------------------------------------------- helper: extract session json
  PhotoSessionDto _extractSession(Map<String, dynamic> raw) {
    final Object? data = raw['data'];
    if (data is Map<String, dynamic>) {
      return PhotoSessionDto.fromJson(data);
    }
    return PhotoSessionDto.fromJson(raw);
  }
}

/// Payload upload foto tunggal. Salah satu dari [filePath] / [bytes] harus
/// disediakan.
class PhotoUpload {
  PhotoUpload({
    required this.filename,
    this.filePath,
    this.bytes,
  }) : assert(filePath != null || bytes != null,
            'Butuh filePath atau bytes.');

  final String filename;
  final String? filePath;
  final Uint8List? bytes;
}

class PrintResult {
  const PrintResult({
    required this.message,
    required this.emailSent,
    required this.printDispatched,
  });

  final String message;
  final bool emailSent;
  final bool printDispatched;
}

/// Terjemahkan enum filter Flutter jadi string yang disimpan monolith.
String? filterToApiString(BoothFilter filter) {
  return switch (filter) {
    BoothFilter.none => null,
    BoothFilter.warm => 'warm',
    BoothFilter.cool => 'cool',
    BoothFilter.noir => 'noir',
    BoothFilter.vintage => 'vintage',
    BoothFilter.vivid => 'vivid',
  };
}
