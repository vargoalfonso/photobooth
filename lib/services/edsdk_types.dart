import 'dart:typed_data';

/// Ringkasan kamera yang dibaca dari EDSDK.
class EdsdkInfo {
  const EdsdkInfo({
    required this.model,
    required this.serialNumber,
    required this.firmware,
    required this.lens,
    required this.battery,
    required this.storage,
  });

  final String model;
  final String serialNumber;
  final String firmware;
  final String lens;
  final String battery;
  final String storage;
}

/// Hasil satu kali jepret yang sudah diunduh dari kamera.
class EdsdkShot {
  const EdsdkShot({required this.bytes, required this.fileName});

  /// Null bila foto hanya disimpan di kartu kamera (tidak diunduh).
  final Uint8List? bytes;
  final String fileName;
}

/// Error dari EDSDK / pemuatan DLL, dengan pesan yang bisa langsung
/// ditampilkan ke operator booth.
class EdsdkException implements Exception {
  EdsdkException(this.message, {this.code});

  final String message;

  /// Kode EDSDK (EdsError) bila error berasal dari SDK.
  final int? code;

  @override
  String toString() => message;
}
