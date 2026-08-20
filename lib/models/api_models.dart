// Data Transfer Objects untuk API monolith Laravel (monolith-picture).
//
// Semua model bersifat immutable dan hanya berisi field-field yang benar-benar
// dikembalikan / diminta oleh endpoint monolith. Kolom yang belum dipakai
// Flutter sengaja tidak dibungkus lagi supaya tetap ringan.

import 'dart:convert';

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
      id: (json['id'] as num).toInt(),
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
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? 'Template',
      category: json['category']?.toString() ?? 'All',
      scope: json['scope']?.toString() ?? 'Generic',
      status: json['status']?.toString() ?? 'active',
      printSize: json['print_size']?.toString() ?? 'Normal',
      printerSetting: json['printer_setting']?.toString() ?? 'Primary Printer',
      filePath: json['file_path']?.toString(),
      thumbnailPath: json['thumbnail_path']?.toString(),
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
      id: (json['id'] as num).toInt(),
      sessionId: (json['session_id'] as num?)?.toInt() ?? 0,
      type: json['type']?.toString() ?? 'photo',
      fileName: json['file_name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
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
      id: (json['id'] as num).toInt(),
      boothId: (json['booth_id'] as num?)?.toInt() ?? 0,
      photoFrameId: (json['photo_frame_id'] as num?)?.toInt(),
      sessionCode: json['session_code']?.toString() ?? '',
      customerName: json['customer_name']?.toString(),
      layout: json['layout']?.toString(),
      grid: json['grid']?.toString(),
      filter: json['filter']?.toString(),
      email: json['email']?.toString(),
      totalFiles: (json['total_files'] as num?)?.toInt() ?? 0,
      totalSize: (json['total_size'] as num?)?.toInt() ?? 0,
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
      currentPage: (pager['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (pager['last_page'] as num?)?.toInt() ?? 1,
      total: (pager['total'] as num?)?.toInt() ?? data.length,
    );
  }
}

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
