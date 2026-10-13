// Data Transfer Objects untuk API monolith Laravel (monolith-picture).
//
// Semua model bersifat immutable dan hanya berisi field-field yang benar-benar
// dikembalikan / diminta oleh endpoint monolith. Kolom yang belum dipakai
// Flutter sengaja tidak dibungkus lagi supaya tetap ringan.

import 'dart:convert';

/// Satu DESAIN background frame bawaan dari dashboard
/// (`GET /api/frame-backgrounds`; satu frame bisa punya banyak desain).
/// [aspect] = lebar / tinggi gambar; area* = kotak tempat foto ditempatkan
/// (persen dari lembar).
class FrameBackgroundInfo {
  const FrameBackgroundInfo({
    this.id,
    this.name = '',
    required this.url,
    this.aspect,
    this.areaX = 4,
    this.areaY = 3,
    this.areaW = 92,
    this.areaH = 94,
  });

  /// ID desain di server (null untuk server lama yang belum mengirimnya).
  final int? id;

  /// Nama desain, mis. "Pantai".
  final String name;
  final String url;
  final double? aspect;
  final double areaX;
  final double areaY;
  final double areaW;
  final double areaH;
}

/// Pengaturan server (`GET /api/config`).
class ServerConfigDto {
  const ServerConfigDto({
    required this.requirePayment,
    this.shotsPerSession,
    this.warnings = const <String>[],
  });

  final bool requirePayment;
  final int? shotsPerSession;

  /// Masalah setup server (storage link, migrasi, mail, printer).
  final List<String> warnings;

  factory ServerConfigDto.fromJson(Map<String, dynamic> json) {
    final Object? rawWarnings = json['warnings'];
    return ServerConfigDto(
      requirePayment: _asBool(json['require_payment'], defaultValue: true),
      shotsPerSession: _asIntOrNull(json['shots_per_session']),
      warnings: rawWarnings is List
          ? rawWarnings.map((Object? w) => w.toString()).toList(growable: false)
          : const <String>[],
    );
  }
}

/// Booth = tempat fisik / device yang memiliki sesi foto.
class BoothDto {
  const BoothDto({
    required this.id,
    required this.name,
    this.slug,
    this.location,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String? slug;
  final String? location;
  final bool isActive;

  factory BoothDto.fromJson(Map<String, dynamic> json) {
    return BoothDto(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? 'Booth',
      slug: json['slug']?.toString(),
      location: json['location']?.toString(),
      isActive: _asBool(json['is_active'], defaultValue: true),
    );
  }
}

/// Template / photo frame yang tersedia di backend.
class PhotoFrameDto {
  const PhotoFrameDto({
    required this.id,
    required this.name,
    this.category = 'All',
    this.scope = 'Generic',
    this.status = 'active',
    this.printSize = 'Normal',
    this.printerSetting = 'Primary Printer',
    this.filePath,
    this.thumbnailPath,
    this.imageUrl,
    this.isActive = true,
    this.layoutJson,
    this.notes,
  });

  final int id;
  final String name;
  final String category;
  final String scope;
  final String status;
  final String printSize;
  final String printerSetting;
  final String? filePath;
  final String? thumbnailPath;

  /// URL absolut PNG frame (accessor `image_url` di monolith), bila ada.
  final String? imageUrl;
  final bool isActive;
  final Map<String, dynamic>? layoutJson;
  final String? notes;

  /// Jumlah slot foto pada template ini (dari layout_json.slots[]).
  int get slotCount {
    final Object? slots = layoutJson?['slots'];
    if (slots is List) {
      return slots.length;
    }
    return 0;
  }

  factory PhotoFrameDto.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? layout;
    final Object? raw = json['layout_json'];
    if (raw is Map<String, dynamic>) {
      layout = raw;
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final Object decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          layout = decoded;
        }
      } catch (_) {
        layout = null;
      }
    }

    return PhotoFrameDto(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? 'Template',
      category: json['category']?.toString() ?? 'All',
      scope: json['scope']?.toString() ?? 'Generic',
      status: json['status']?.toString() ?? 'active',
      printSize: json['print_size']?.toString() ?? 'Normal',
      printerSetting: json['printer_setting']?.toString() ?? 'Primary Printer',
      filePath: json['file_path']?.toString(),
      thumbnailPath: json['thumbnail_path']?.toString(),
      imageUrl: json['image_url']?.toString(),
      isActive: _asBool(json['is_active'], defaultValue: true),
      layoutJson: layout,
      notes: json['notes']?.toString(),
    );
  }
}

/// Media (foto/strip/video) yang ter-attach ke sebuah sesi.
class MediaDto {
  const MediaDto({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.fileName,
    required this.path,
    required this.size,
  });

  final int id;
  final int sessionId;
  final String type; // photo | strip | gif | boomerang | video
  final String fileName;
  final String path; // relatif storage/... di monolith
  final int size;

  factory MediaDto.fromJson(Map<String, dynamic> json) {
    return MediaDto(
      id: _asInt(json['id']),
      sessionId: _asIntOrNull(json['session_id']) ?? 0,
      type: json['type']?.toString() ?? 'photo',
      fileName: json['file_name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      size: _asIntOrNull(json['size']) ?? 0,
    );
  }

  /// Absolute URL untuk media, mengambil host [baseHost] (http://host:port).
  String absoluteUrl(String baseHost) {
    final String host = baseHost.replaceAll(RegExp(r'/+$'), '');
    final String cleaned = path.replaceAll(RegExp(r'^/+'), '');
    return '$host/$cleaned';
  }
}

/// Sesi foto lengkap: booth + frame + media.
class PhotoSessionDto {
  const PhotoSessionDto({
    required this.id,
    required this.boothId,
    required this.sessionCode,
    this.photoFrameId,
    this.customerName,
    this.layout,
    this.grid,
    this.filter,
    this.email,
    this.totalFiles = 0,
    this.totalSize = 0,
    this.takenAt,
    this.booth,
    this.photoFrame,
    this.media = const <MediaDto>[],
  });

  final int id;
  final int boothId;
  final int? photoFrameId;
  final String sessionCode;
  final String? customerName;
  final String? layout;
  final String? grid;
  final String? filter;
  final String? email;
  final int totalFiles;
  final int totalSize;
  final DateTime? takenAt;
  final BoothDto? booth;
  final PhotoFrameDto? photoFrame;
  final List<MediaDto> media;

  factory PhotoSessionDto.fromJson(Map<String, dynamic> json) {
    final Object? mediaRaw = json['media'];
    final List<MediaDto> media = mediaRaw is List
        ? mediaRaw
            .whereType<Map<String, dynamic>>()
            .map(MediaDto.fromJson)
            .toList(growable: false)
        : const <MediaDto>[];

    BoothDto? booth;
    final Object? boothRaw = json['booth'];
    if (boothRaw is Map<String, dynamic>) {
      booth = BoothDto.fromJson(boothRaw);
    }

    PhotoFrameDto? frame;
    final Object? frameRaw = json['photo_frame'];
    if (frameRaw is Map<String, dynamic>) {
      frame = PhotoFrameDto.fromJson(frameRaw);
    }

    DateTime? takenAt;
    final Object? rawTaken = json['taken_at'];
    if (rawTaken is String && rawTaken.isNotEmpty) {
      takenAt = DateTime.tryParse(rawTaken);
    }

    return PhotoSessionDto(
      id: _asInt(json['id']),
      boothId: _asIntOrNull(json['booth_id']) ?? 0,
      photoFrameId: _asIntOrNull(json['photo_frame_id']),
      sessionCode: json['session_code']?.toString() ?? '',
      customerName: json['customer_name']?.toString(),
      layout: json['layout']?.toString(),
      grid: json['grid']?.toString(),
      filter: json['filter']?.toString(),
      email: json['email']?.toString(),
      totalFiles: _asIntOrNull(json['total_files']) ?? 0,
      totalSize: _asIntOrNull(json['total_size']) ?? 0,
      takenAt: takenAt,
      booth: booth,
      photoFrame: frame,
      media: media,
    );
  }
}

/// Halaman hasil dari endpoint `GET /photo-sessions` (Laravel paginate 20).
class PhotoSessionPage {
  const PhotoSessionPage({
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<PhotoSessionDto> data;
  final int currentPage;
  final int lastPage;
  final int total;

  factory PhotoSessionPage.fromLaravelPaginator(Map<String, dynamic> raw) {
    // Laravel paginator format: { data: [], current_page, last_page, total, ... }
    // Endpoint monolith bungkus paginator dalam key `data`. Handle keduanya.
    final Map<String, dynamic> pager;
    final Object? outer = raw['data'];
    if (outer is Map<String, dynamic> && outer.containsKey('data')) {
      pager = outer;
    } else {
      pager = raw;
    }

    final Object? items = pager['data'];
    final List<PhotoSessionDto> data = items is List
        ? items
            .whereType<Map<String, dynamic>>()
            .map(PhotoSessionDto.fromJson)
            .toList(growable: false)
        : const <PhotoSessionDto>[];

    return PhotoSessionPage(
      data: data,
      currentPage: _asInt(pager['current_page'], 1),
      lastPage: _asInt(pager['last_page'], 1),
      total: _asInt(pager['total'], data.length),
    );
  }
}

/// Laravel mengirim kolom DECIMAL (mis. `size`, `total_size`) sebagai String
/// seperti "0.00", jadi cast langsung `as num` akan melempar TypeError.
int? _asIntOrNull(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return num.tryParse(value.trim())?.toInt();
  return null;
}

int _asInt(Object? value, [int fallback = 0]) =>
    _asIntOrNull(value) ?? fallback;

bool _asBool(Object? value, {bool defaultValue = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String v = value.toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
  }
  return defaultValue;
}
