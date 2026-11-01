// Stub untuk platform tanpa dart:ffi (Flutter Web).
import 'dart:typed_data';

import 'edsdk_types.dart';

class EdsdkNative {
  static String? locateDll(String configured) => null;

  bool get isLoaded => false;
  bool get isOpen => false;
  bool get isLiveView => false;

  static Never _unsupported() => throw EdsdkException(
    'EDSDK tidak tersedia di platform ini (hanya Windows).',
  );

  void load(String dllPath) => _unsupported();
  int cameraCount() => 0;
  void openCamera() => _unsupported();
  EdsdkInfo readInfo() => _unsupported();
  void startLiveView() => _unsupported();
  void stopLiveView() {}
  Uint8List? liveViewFrame() => _unsupported();
  Future<void> autoFocus() async {}
  Future<EdsdkShot> capture({bool keepOnCard = true, bool download = true}) =>
      _unsupported();
  void setExposure(String kind, String value) => _unsupported();
  void pump() {}
  void closeCamera() {}
  void dispose() {}
}
