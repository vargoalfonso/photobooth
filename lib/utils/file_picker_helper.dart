import 'package:file_picker/file_picker.dart';

class FilePickerHelper {
  const FilePickerHelper._();

  static Future<String?> pickCustomPath({
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) async {
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      lockParentWindow: true,
    );

    return file?.path;
  }

  static Future<List<PlatformFile>> pickMediaFiles({
    String? dialogTitle,
  }) async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
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
      lockParentWindow: true,
    );

    return files;
  }

  static Future<List<PlatformFile>> pickCustomFiles({
    required List<String> allowedExtensions,
    String? dialogTitle,
    bool allowMultiple = true,
  }) async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
      lockParentWindow: true,
    );

    return files;
  }
}
