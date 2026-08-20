// High-level service yang membungkus MonolithApiClient sesuai kontrak
// endpoint monolith Laravel (routes/api.php + Api/PhotoboothController.php).
//
// Semua fungsi menerjemahkan JSON menjadi DTO Dart yang bersih supaya UI
// Flutter tidak perlu tahu bentuk paginator/response Laravel.

import 'dart:typed_data';

import '../models/api_models.dart';
import '../models/booth_models.dart';
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
