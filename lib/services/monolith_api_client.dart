// Low-level HTTP client untuk API monolith Laravel (monolith-picture).
//
// Berbasis package:http. Menyediakan helper:
//   - GET / POST / PUT / DELETE JSON
//   - POST multipart untuk upload file (photos[])
//
// Tidak boleh berisi state UI dan tidak boleh referensi Flutter widgets.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

/// Exception yang dilempar oleh [MonolithApiClient]. Membawa status code dan
/// pesan yang paling mudah dibaca (dari body Laravel bila ada).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() {
    if (statusCode != null) {
      return 'ApiException($statusCode): $message';
    }
    return 'ApiException: $message';
  }
}

/// Pasangan file yang mau di-upload sebagai multipart `photos[]`.
class ApiFileUpload {
  ApiFileUpload({
    required this.fieldName,
    required this.filename,
    this.filePath,
    this.bytes,
    this.contentType,
  }) : assert(filePath != null || bytes != null,
            'Butuh filePath atau bytes.');

  final String fieldName; // umumnya 'photos[]'
  final String filename;
  final String? filePath;
  final Uint8List? bytes;
  final MediaType? contentType;

  Future<http.MultipartFile> toMultipart() async {
    final MediaType type = contentType ?? _guessMediaType(filename);
    if (bytes != null) {
      return http.MultipartFile.fromBytes(
        fieldName,
        bytes!,
        filename: filename,
        contentType: type,
      );
    }
    if (!kIsWeb && filePath != null) {
      final File file = File(filePath!);
      final Uint8List data = await file.readAsBytes();
      return http.MultipartFile.fromBytes(
        fieldName,
        data,
        filename: filename,
        contentType: type,
      );
    }
    throw ApiException('File $filename tidak bisa dibaca.');
  }
}

MediaType _guessMediaType(String name) {
  final String lower = name.toLowerCase();
  if (lower.endsWith('.png')) return MediaType('image', 'png');
  if (lower.endsWith('.webp')) return MediaType('image', 'webp');
  if (lower.endsWith('.gif')) return MediaType('image', 'gif');
  if (lower.endsWith('.heic')) return MediaType('image', 'heic');
  if (lower.endsWith('.mp4')) return MediaType('video', 'mp4');
  return MediaType('image', 'jpeg');
}

/// HTTP client tipis untuk memanggil monolith Laravel.
class MonolithApiClient {
  MonolithApiClient({
    required String baseUrl,
    String? token,
    Duration timeout = const Duration(seconds: 30),
    http.Client? httpClient,
  })  : _base = _normalizeBase(baseUrl),
        _token = token,
        _timeout = timeout,
        _http = httpClient ?? http.Client();

  final String _base; // ex: http://127.0.0.1:8000/api
  final String? _token;
  final Duration _timeout;
  final http.Client _http;

  /// Base URL yang sudah dinormalisasi (tanpa trailing slash).
  String get baseUrl => _base;

  /// Host bagian dari [baseUrl] (tanpa `/api`). Berguna untuk membangun URL
  /// gambar dari path `storage/...` yang dikembalikan monolith.
  String get hostBaseUrl {
    final Uri uri = Uri.parse(_base);
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }

  static String _normalizeBase(String value) {
    String trimmed = value.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.isEmpty) {
      return 'http://127.0.0.1:8000/api';
    }
    // Kalau user cuma masukkan `http://host` tanpa `/api`, tambahkan.
    if (!trimmed.endsWith('/api')) {
      final Uri parsed = Uri.tryParse(trimmed) ?? Uri();
      if (parsed.pathSegments.isEmpty ||
          !parsed.pathSegments.contains('api')) {
        trimmed = '$trimmed/api';
      }
    }
    return trimmed;
  }

  Map<String, String> _headers({bool jsonBody = false}) {
    return <String, String>{
      'Accept': 'application/json',
      if (jsonBody) 'Content-Type': 'application/json',
      if (_token != null && _token!.isNotEmpty)
        'Authorization': 'Bearer $_token',
    };
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final String cleanedPath =
        path.startsWith('/') ? path.substring(1) : path;
    final Uri base = Uri.parse('$_base/$cleanedPath');
    if (query == null || query.isEmpty) {
      return base;
    }
    final Map<String, String> stringified = <String, String>{};
    query.forEach((String k, Object? v) {
      if (v != null) {
        stringified[k] = v.toString();
      }
    });
    return base.replace(queryParameters: <String, String>{
      ...base.queryParameters,
      ...stringified,
    });
  }

  /// GET JSON.
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final http.Response res = await _http
        .get(_uri(path, query), headers: _headers())
        .timeout(_timeout);
    return _decode(res);
  }

  /// POST JSON body.
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final http.Response res = await _http
        .post(
          _uri(path),
          headers: _headers(jsonBody: true),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout);
    return _decode(res);
  }

  /// PUT JSON body.
  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final http.Response res = await _http
        .put(
          _uri(path),
          headers: _headers(jsonBody: true),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout);
    return _decode(res);
  }

  /// DELETE JSON.
  Future<Map<String, dynamic>> delete(String path) async {
    final http.Response res = await _http
        .delete(_uri(path), headers: _headers())
        .timeout(_timeout);
    return _decode(res);
  }

  /// POST multipart untuk upload file. [fields] jadi body form-data biasa,
  /// [files] di-attach sebagai file entries.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    Map<String, String> fields = const <String, String>{},
    List<ApiFileUpload> files = const <ApiFileUpload>[],
  }) async {
    final http.MultipartRequest request =
        http.MultipartRequest('POST', _uri(path));
    request.headers.addAll(_headers());
    request.fields.addAll(fields);
    for (final ApiFileUpload f in files) {
      request.files.add(await f.toMultipart());
    }

    final http.StreamedResponse streamed =
        await request.send().timeout(_timeout);
    final http.Response res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final int status = res.statusCode;
    final String body = res.body;

    // 204 no content -> return kosong.
    if (status == 204 || body.isEmpty) {
      if (status >= 200 && status < 300) {
        return const <String, dynamic>{};
      }
      throw ApiException(
        'HTTP $status tanpa body.',
        statusCode: status,
        body: '',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      if (status >= 200 && status < 300) {
        return <String, dynamic>{'raw': body};
      }
      throw ApiException(
        'Response bukan JSON valid.',
        statusCode: status,
        body: body,
      );
    }

    if (status >= 200 && status < 300) {
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{'data': decoded};
    }

    String message = 'HTTP $status';
    if (decoded is Map && decoded['message'] is String) {
      message = decoded['message'] as String;
    } else if (decoded is Map && decoded['error'] is String) {
      message = decoded['error'] as String;
    }
    throw ApiException(message, statusCode: status, body: body);
  }

  void close() => _http.close();
}
