import 'package:file_picker/file_picker.dart';

class FilePickerHelper {
  const FilePickerHelper._();

  static Future<String?> pickCustomPath({
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
      allowMultiple: false,
      lockParentWindow: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    return result.files.single.path;
  }

  static Future<List<PlatformFile>> pickMediaFiles({
    String? dialogTitle,
  }) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>[
        'jpg',
        'jpeg',
        'png',
        'gif',
        'bmp',
        'webp',
      ],
      allowMultiple: true,
      withData: true,
      dialogTitle: dialogTitle,
      lockParentWindow: true,
    );

    return result?.files ?? const <PlatformFile>[];
  }

  static Future<List<PlatformFile>> pickCustomFiles({
    required List<String> allowedExtensions,
    String? dialogTitle,
    bool allowMultiple = true,
  }) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
      dialogTitle: dialogTitle,
      lockParentWindow: true,
    );

    return result?.files ?? const <PlatformFile>[];
  }
}
