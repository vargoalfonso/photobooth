// Binding Canon EDSDK langsung dari Dart lewat dart:ffi (tanpa Python/bridge).
//
// Catatan desain:
//  * Semua panggilan EDSDK dilakukan dari isolate utama (satu thread). EDSDK di
//    Windows mensyaratkan semua panggilan berasal dari thread yang sama dengan
//    saat EdsInitializeSDK.
//  * Event dari kamera (mis. "ada file baru, silakan unduh") dikirim lewat
//    callback yang dipicu oleh EdsGetEvent(); karena itu [pump] dipanggil
//    berkala saat menunggu hasil jepretan.
//  * Struct yang ukurannya bergantung versi SDK (EdsDirectoryItemInfo,
//    EdsVolumeInfo) dibaca lewat buffer + offset, bukan Struct Dart, supaya
//    tidak rusak pada SDK lama/baru.
//
// Konstanta ditulis dari EDSDKTypes.h; cocokkan dengan versi SDK Anda.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'edsdk_types.dart';

// ----------------------------------------------------------------- konstanta
const int _kPropProductName = 0x00000002;
const int _kPropFirmwareVersion = 0x00000007;
const int _kPropBatteryLevel = 0x00000008;
// Status verifikasi konstanta:
//  [OK]  dicocokkan dengan file contoh resmi Canon (EDSDKType.pas/EDSDKError.pas)
//  [HDR] berasal dari pengetahuan header EDSDKTypes.h, BELUM dicocokkan dengan
//        file header asli. Cocokkan begitu SDK Canon tersedia.
const int _kPropSaveTo = 0x0000000B; // [HDR]
const int _kPropBodyIDEx = 0x00000015;
const int _kPropWhiteBalance = 0x00000106;
const int _kPropIsoSpeed = 0x00000402; // [HDR] (urutan: ISO 402, Av 405, Tv 406)
const int _kPropAv = 0x00000405; // [HDR]
const int _kPropTv = 0x00000406; // [HDR]
const int _kPropLensName = 0x0000040D; // [OK] kEdsPropID_LensName
const int _kPropEvfOutputDevice = 0x00000500;
const int _kPropEvfMode = 0x00000501;

const int _kCmdTakePicture = 0x00000000;
const int _kCmdPressShutterButton = 0x00000004;
const int _kCmdDoEvfAf = 0x00000102;
const int _kShutterOff = 0x00000000;
const int _kShutterCompletelyNonAf = 0x00010003;

const int _kObjectEventAll = 0x00000200;
const int _kObjectEventDirItemRequestTransfer = 0x00000208;

const int _kSaveToCamera = 1;
const int _kSaveToHost = 2;
const int _kSaveToBoth = 3;
const int _kEvfOutputPc = 2;

const int _errOk = 0;
const int _errDeviceNotFound = 0x80;
const int _errDeviceBusy = 0x81;
const int _errSessionNotOpen = 0x2003;
const int _errObjectNotReady = 0xA102;
const int _errTakePictureAfNg = 0x8D01;
const int _errCommPortInUse = 0xC0;

String _hint(int code) {
  switch (code) {
    case _errDeviceNotFound:
      return 'kamera tidak ditemukan (cek kabel USB dan nyalakan kamera)';
    case _errDeviceBusy:
      return 'kamera sibuk';
    case _errSessionNotOpen:
      return 'sesi kamera belum terbuka';
    case _errObjectNotReady:
      return 'objek belum siap';
    case _errTakePictureAfNg:
      return 'autofocus gagal saat jepret';
    case _errCommPortInUse:
      return 'kamera sedang dipakai aplikasi lain - tutup EOS Webcam Utility, '
          'EOS Utility, atau aplikasi Canon lain';
  }
  return '';
}

// ------------------------------------------------------- tabel nilai eksposur
const Map<String, int> _isoCodes = <String, int>{
  'auto': 0x00,
  '100': 0x48,
  '200': 0x50,
  '400': 0x58,
  '800': 0x60,
  '1600': 0x68,
  '3200': 0x70,
  '6400': 0x78,
  '12800': 0x80,
  '25600': 0x88,
};

final Map<double, int> _avTable = <double, int>{
  1.0: 0x08,
  1.1: 0x0B,
  1.2: 0x0C,
  1.4: 0x10,
  1.6: 0x13,
  1.8: 0x14,
  2.0: 0x18,
  2.2: 0x1B,
  2.5: 0x1C,
  2.8: 0x20,
  3.2: 0x23,
  3.5: 0x24,
  4.0: 0x28,
  4.5: 0x2B,
  5.0: 0x2C,
  5.6: 0x30,
  6.3: 0x33,
  7.1: 0x34,
  8.0: 0x38,
  9.0: 0x3B,
  10.0: 0x3C,
  11.0: 0x40,
  13.0: 0x43,
  14.0: 0x44,
  16.0: 0x48,
  18.0: 0x4B,
  20.0: 0x4C,
  22.0: 0x50,
};

// detik -> kode. Pecahan ditulis sebagai 1/x.
final Map<double, int> _tvTable = <double, int>{
  30.0: 0x10,
  25.0: 0x13,
  20.0: 0x14,
  15.0: 0x18,
  13.0: 0x1B,
  10.0: 0x1C,
  8.0: 0x20,
  6.0: 0x23,
  5.0: 0x24,
  4.0: 0x28,
  3.2: 0x2B,
  2.5: 0x2C,
  2.0: 0x30,
  1.6: 0x33,
  1.3: 0x34,
  1.0: 0x38,
  0.8: 0x3B,
  0.6: 0x3C,
  0.5: 0x40,
  0.4: 0x43,
  0.3: 0x44,
  1 / 4: 0x48,
  1 / 5: 0x4B,
  1 / 6: 0x4C,
  1 / 8: 0x50,
  1 / 10: 0x53,
  1 / 13: 0x54,
  1 / 15: 0x58,
  1 / 20: 0x5B,
  1 / 25: 0x5C,
  1 / 30: 0x60,
  1 / 40: 0x63,
  1 / 50: 0x64,
  1 / 60: 0x68,
  1 / 80: 0x6B,
  1 / 100: 0x6C,
  1 / 125: 0x70,
  1 / 160: 0x73,
  1 / 200: 0x74,
  1 / 250: 0x78,
  1 / 320: 0x7B,
  1 / 400: 0x7C,
  1 / 500: 0x80,
  1 / 640: 0x83,
  1 / 800: 0x84,
  1 / 1000: 0x88,
};

const Map<String, int> _wbCodes = <String, int>{
  'auto': 0,
  'daylight': 1,
  'cloudy': 2,
  'tungsten': 3,
  'fluorescent': 4,
  'flash': 5,
  'shade': 8,
};

int _nearest(Map<double, int> table, double value, {double tol = 0.03}) {
  double best = table.keys.first;
  for (final double k in table.keys) {
    if ((k - value).abs() / k < (best - value).abs() / best) {
      best = k;
    }
  }
  if ((best - value).abs() / best > tol) {
    throw EdsdkException('Nilai $value tidak ada di tabel kamera.');
  }
  return table[best]!;
}

// -------------------------------------------------------------- tipe native
typedef _ObjEventNative = Uint32 Function(Uint32, Pointer<Void>, Pointer<Void>);

typedef _N0 = Uint32 Function();
typedef _D0 = int Function();
typedef _N1 = Uint32 Function(Pointer<Void>);
typedef _D1 = int Function(Pointer<Void>);
typedef _NOut = Uint32 Function(Pointer<Pointer<Void>>);
typedef _DOut = int Function(Pointer<Pointer<Void>>);
typedef _NRefU32Out = Uint32 Function(Pointer<Void>, Pointer<Uint32>);
typedef _DRefU32Out = int Function(Pointer<Void>, Pointer<Uint32>);
typedef _NChildAt = Uint32 Function(
  Pointer<Void>,
  Int32,
  Pointer<Pointer<Void>>,
);
typedef _DChildAt = int Function(Pointer<Void>, int, Pointer<Pointer<Void>>);
typedef _NCmd = Uint32 Function(Pointer<Void>, Uint32, Int32);
typedef _DCmd = int Function(Pointer<Void>, int, int);
typedef _NProp = Uint32 Function(
  Pointer<Void>,
  Uint32,
  Int32,
  Uint32,
  Pointer<Void>,
);
typedef _DProp = int Function(Pointer<Void>, int, int, int, Pointer<Void>);
typedef _NRefRef = Uint32 Function(Pointer<Void>, Pointer<Void>);
typedef _NRefOut = Uint32 Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _DRefOut = int Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _DRefRef = int Function(Pointer<Void>, Pointer<Void>);
typedef _NStreamNew = Uint32 Function(Uint64, Pointer<Pointer<Void>>);
typedef _DStreamNew = int Function(int, Pointer<Pointer<Void>>);
typedef _NRefU64Out = Uint32 Function(Pointer<Void>, Pointer<Uint64>);
typedef _DRefU64Out = int Function(Pointer<Void>, Pointer<Uint64>);
typedef _NDownload = Uint32 Function(Pointer<Void>, Uint64, Pointer<Void>);
typedef _DDownload = int Function(Pointer<Void>, int, Pointer<Void>);
typedef _NSetHandler = Uint32 Function(
  Pointer<Void>,
  Uint32,
  Pointer<NativeFunction<_ObjEventNative>>,
  Pointer<Void>,
);
typedef _DSetHandler = int Function(
  Pointer<Void>,
  int,
  Pointer<NativeFunction<_ObjEventNative>>,
  Pointer<Void>,
);

/// struct EdsCapacity { int numberOfFreeClusters; int bytesPerSector; EdsBool reset; }
final class _EdsCapacity extends Struct {
  @Int32()
  external int numberOfFreeClusters;
  @Int32()
  external int bytesPerSector;
  @Int32()
  external int reset;
}

typedef _NSetCapacity = Uint32 Function(Pointer<Void>, _EdsCapacity);
typedef _DSetCapacity = int Function(Pointer<Void>, _EdsCapacity);

typedef _NSetDllDir = Int32 Function(Pointer<Uint16>);
typedef _DSetDllDir = int Function(Pointer<Uint16>);

/// Wrapper tipis di atas EDSDK.dll.
class EdsdkNative {
  EdsdkNative();

  bool _sdkReady = false;
  Pointer<Void> _cam = nullptr;
  bool _sessionOpen = false;
  bool _liveView = false;
  NativeCallable<_ObjEventNative>? _callable;

  // hasil unduhan dari callback
  Uint8List? _photo;
  String _photoName = '';
  bool _photoFailed = false;

  // fungsi native (diisi oleh load)
  late _D0 _initializeSdk;
  late _D0 _terminateSdk;
  late _D0 _getEvent;
  late _D1 _release;
  late _DOut _getCameraList;
  late _DRefU32Out _getChildCount;
  late _DChildAt _getChildAtIndex;
  late _D1 _openSession;
  late _D1 _closeSession;
  late _DCmd _sendCommand;
  late _DProp _getPropertyData;
  late _DProp _setPropertyData;
  late _DSetCapacity _setCapacity;
  late _DStreamNew _createMemoryStream;
  late _DRefOut _getPointer;
  late _DRefU64Out _getLength;
  late _DRefOut _createEvfImageRef;
  late _DRefRef _downloadEvfImage;
  late _DRefRef _getDirectoryItemInfo;
  late _DDownload _download;
  late _D1 _downloadComplete;
  late _DRefRef _getVolumeInfo;
  late _DSetHandler _setObjectEventHandler;

  bool get isLoaded => _sdkReady;
  bool get isOpen => _sessionOpen;
  bool get isLiveView => _liveView;

  // ------------------------------------------------------------- lokasi DLL
  /// Mencari EDSDK.dll. [configured] boleh berupa path file atau folder.
  /// Urutan: pilihan operator, lalu folder aplikasi (EDSDK.dll,
  /// EDSDK/EDSDK.dll), lalu folder kerja.
  static String? locateDll(String configured) {
    final List<String> candidates = <String>[];
    final String c = configured.trim();
    if (c.isNotEmpty) {
      candidates.add(c);
      candidates.add('$c${Platform.pathSeparator}EDSDK.dll');
    }
    try {
      final String exeDir = File(Platform.resolvedExecutable).parent.path;
      final String s = Platform.pathSeparator;
      candidates.addAll(<String>[
        '$exeDir${s}EDSDK.dll',
        '$exeDir${s}EDSDK${s}EDSDK.dll',
        '$exeDir${s}edsdk${s}EDSDK.dll',
      ]);
    } catch (_) {}
    candidates.add(
      '${Directory.current.path}${Platform.pathSeparator}EDSDK.dll',
    );

    for (final String path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  /// Tambahkan folder DLL ke jalur pencarian dependensi (EdsImage.dll dll.).
  /// DynamicLibrary.open tidak mencari dependensi di folder DLL itu sendiri.
  void _setDllDirectory(String dir) {
    if (!Platform.isWindows) {
      return;
    }
    final _DSetDllDir fn = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<_NSetDllDir, _DSetDllDir>('SetDllDirectoryW');
    final List<int> units = dir.codeUnits;
    final Pointer<Uint16> buf = calloc<Uint16>(units.length + 1);
    try {
      for (int i = 0; i < units.length; i++) {
        buf[i] = units[i];
      }
      fn(buf);
    } finally {
      calloc.free(buf);
    }
  }

  // ------------------------------------------------------------------ load
  void load(String dllPath) {
    if (_sdkReady) {
      return;
    }
    final File file = File(dllPath);
    if (!file.existsSync()) {
      throw EdsdkException('EDSDK.dll tidak ditemukan: $dllPath');
    }
    try {
      _setDllDirectory(file.parent.path);
      final DynamicLibrary lib = DynamicLibrary.open(dllPath);
      _initializeSdk = lib.lookupFunction<_N0, _D0>('EdsInitializeSDK');
      _terminateSdk = lib.lookupFunction<_N0, _D0>('EdsTerminateSDK');
      _getEvent = lib.lookupFunction<_N0, _D0>('EdsGetEvent');
      _release = lib.lookupFunction<_N1, _D1>('EdsRelease');
      _getCameraList = lib.lookupFunction<_NOut, _DOut>('EdsGetCameraList');
      _getChildCount = lib.lookupFunction<_NRefU32Out, _DRefU32Out>(
        'EdsGetChildCount',
      );
      _getChildAtIndex = lib.lookupFunction<_NChildAt, _DChildAt>(
        'EdsGetChildAtIndex',
      );
      _openSession = lib.lookupFunction<_N1, _D1>('EdsOpenSession');
      _closeSession = lib.lookupFunction<_N1, _D1>('EdsCloseSession');
      _sendCommand = lib.lookupFunction<_NCmd, _DCmd>('EdsSendCommand');
      _getPropertyData = lib.lookupFunction<_NProp, _DProp>(
        'EdsGetPropertyData',
      );
      _setPropertyData = lib.lookupFunction<_NProp, _DProp>(
        'EdsSetPropertyData',
      );
      _setCapacity = lib.lookupFunction<_NSetCapacity, _DSetCapacity>(
        'EdsSetCapacity',
      );
      _createMemoryStream = lib.lookupFunction<_NStreamNew, _DStreamNew>(
        'EdsCreateMemoryStream',
      );
      _getPointer = lib.lookupFunction<_NRefOut, _DRefOut>('EdsGetPointer');
      _getLength = lib.lookupFunction<_NRefU64Out, _DRefU64Out>('EdsGetLength');
      _createEvfImageRef = lib.lookupFunction<_NRefOut, _DRefOut>(
        'EdsCreateEvfImageRef',
      );
      _downloadEvfImage = lib.lookupFunction<_NRefRef, _DRefRef>(
        'EdsDownloadEvfImage',
      );
      _getDirectoryItemInfo = lib.lookupFunction<_NRefRef, _DRefRef>(
        'EdsGetDirectoryItemInfo',
      );
      _download = lib.lookupFunction<_NDownload, _DDownload>('EdsDownload');
      _downloadComplete = lib.lookupFunction<_N1, _D1>('EdsDownloadComplete');
      _getVolumeInfo = lib.lookupFunction<_NRefRef, _DRefRef>(
        'EdsGetVolumeInfo',
      );
      _setObjectEventHandler = lib.lookupFunction<_NSetHandler, _DSetHandler>(
        'EdsSetObjectEventHandler',
      );
    } on ArgumentError catch (e) {
      throw EdsdkException(
        'EDSDK.dll tidak cocok / fungsi tidak ditemukan: ${e.message}',
      );
    } catch (e) {
      throw EdsdkException(
        'Gagal memuat EDSDK.dll ($dllPath): $e. Pastikan DLL 64-bit dan '
        'file pendampingnya (EdsImage.dll, folder IconMan) ada di folder yang sama.',
      );
    }
    _chk(_initializeSdk(), 'EdsInitializeSDK');
    _sdkReady = true;
  }

  // ---------------------------------------------------------------- utilitas
  void _chk(int code, String where) {
    if (code == _errOk) {
      return;
    }
    if (code == _errDeviceNotFound || code == _errSessionNotOpen) {
      _sessionOpen = false;
      _liveView = false;
    }
    final String hint = _hint(code);
    throw EdsdkException(
      'EDSDK $where gagal: 0x${code.toRadixString(16).toUpperCase()}'
      '${hint.isEmpty ? '' : ' ($hint)'}',
      code: code,
    );
  }

  void _requireSession() {
    if (!_sdkReady || !_sessionOpen) {
      throw EdsdkException('Kamera belum terhubung.');
    }
  }

  int _getU32(int prop) {
    final Pointer<Uint32> p = calloc<Uint32>();
    try {
      _chk(
        _getPropertyData(_cam, prop, 0, 4, p.cast<Void>()),
        'get 0x${prop.toRadixString(16)}',
      );
      return p.value;
    } finally {
      calloc.free(p);
    }
  }

  void _setU32(int prop, int value) {
    final Pointer<Uint32> p = calloc<Uint32>();
    try {
      p.value = value;
      _chk(
        _setPropertyData(_cam, prop, 0, 4, p.cast<Void>()),
        'set 0x${prop.toRadixString(16)}',
      );
    } finally {
      calloc.free(p);
    }
  }

  String _getString(int prop) {
    final Pointer<Uint8> p = calloc<Uint8>(256);
    try {
      _chk(
        _getPropertyData(_cam, prop, 0, 256, p.cast<Void>()),
        'get 0x${prop.toRadixString(16)}',
      );
      return _cString(p.asTypedList(256), 0);
    } finally {
      calloc.free(p);
    }
  }

  static String _cString(Uint8List bytes, int offset) {
    int end = offset;
    while (end < bytes.length && bytes[end] != 0) {
      end++;
    }
    return utf8.decode(bytes.sublist(offset, end), allowMalformed: true);
  }

  Uint8List _streamBytes(Pointer<Void> stream) {
    final Pointer<Pointer<Void>> ptr = calloc<Pointer<Void>>();
    final Pointer<Uint64> len = calloc<Uint64>();
    try {
      _chk(_getPointer(stream, ptr), 'EdsGetPointer');
      _chk(_getLength(stream, len), 'EdsGetLength');
      final int n = len.value;
      if (ptr.value == nullptr || n == 0) {
        return Uint8List(0);
      }
      // Salin: memori stream dilepas setelah EdsRelease.
      return Uint8List.fromList(ptr.value.cast<Uint8>().asTypedList(n));
    } finally {
      calloc.free(ptr);
      calloc.free(len);
    }
  }

  /// Jalankan antrean event EDSDK (memicu callback unduhan foto).
  void pump() {
    if (_sdkReady) {
      _getEvent();
    }
  }

  Future<void> _pumpFor(Duration d) async {
    final DateTime end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  // -------------------------------------------------------------- kamera
  /// Jumlah kamera Canon yang terlihat di USB saat ini (0 = tidak ada /
  /// dimatikan / kabel dicabut). Murah dipanggil berkala untuk deteksi
  /// colok-cabut; tidak membuka sesi.
  int cameraCount() {
    if (!_sdkReady) {
      throw EdsdkException('EDSDK belum dimuat.');
    }
    final Pointer<Pointer<Void>> list = calloc<Pointer<Void>>();
    final Pointer<Uint32> count = calloc<Uint32>();
    try {
      _chk(_getCameraList(list), 'EdsGetCameraList');
      try {
        _chk(_getChildCount(list.value, count), 'EdsGetChildCount');
        return count.value;
      } finally {
        _release(list.value);
      }
    } finally {
      calloc.free(list);
      calloc.free(count);
    }
  }

  void openCamera() {
    if (!_sdkReady) {
      throw EdsdkException('EDSDK belum dimuat.');
    }
    if (_sessionOpen) {
      return;
    }
    final Pointer<Pointer<Void>> list = calloc<Pointer<Void>>();
    final Pointer<Uint32> count = calloc<Uint32>();
    final Pointer<Pointer<Void>> cam = calloc<Pointer<Void>>();
    try {
      _chk(_getCameraList(list), 'EdsGetCameraList');
      try {
        _chk(_getChildCount(list.value, count), 'EdsGetChildCount');
        if (count.value == 0) {
          throw EdsdkException(
            'Tidak ada kamera Canon terdeteksi lewat USB. Cek kabel, '
            'nyalakan kamera, dan tutup EOS Webcam Utility / EOS Utility.',
          );
        }
        _chk(_getChildAtIndex(list.value, 0, cam), 'EdsGetChildAtIndex');
      } finally {
        _release(list.value);
      }
      _cam = cam.value;
    } finally {
      calloc.free(list);
      calloc.free(count);
      calloc.free(cam);
    }

    _chk(_openSession(_cam), 'EdsOpenSession');
    _sessionOpen = true;

    _callable?.close();
    _callable = NativeCallable<_ObjEventNative>.isolateLocal(
      _onObjectEvent,
      exceptionalReturn: 0,
    );
    _chk(
      _setObjectEventHandler(
        _cam,
        _kObjectEventAll,
        _callable!.nativeFunction,
        nullptr,
      ),
      'EdsSetObjectEventHandler',
    );
  }

  EdsdkInfo readInfo() {
    _requireSession();
    String tryStr(int prop) {
      try {
        return _getString(prop);
      } on EdsdkException {
        return '-';
      }
    }

    String battery = '-';
    try {
      final int level = _getU32(_kPropBatteryLevel);
      battery = level == 0xFFFFFFFF ? 'AC' : '$level%';
    } on EdsdkException {
      // opsional
    }

    return EdsdkInfo(
      model: tryStr(_kPropProductName),
      serialNumber: tryStr(_kPropBodyIDEx),
      firmware: tryStr(_kPropFirmwareVersion),
      lens: tryStr(_kPropLensName),
      battery: battery,
      storage: _readStorage(),
    );
  }

  String _readStorage() {
    final Pointer<Pointer<Void>> vol = calloc<Pointer<Void>>();
    final Pointer<Uint8> buf = calloc<Uint8>(512);
    try {
      if (_getChildAtIndex(_cam, 0, vol) != _errOk) {
        return '-';
      }
      try {
        if (_getVolumeInfo(vol.value, buf.cast<Void>()) != _errOk) {
          return '-';
        }
        // EdsVolumeInfo: u32 storageType, u32 access, u64 maxCapacity,
        // u64 freeSpaceInBytes (offset 16).
        final int free = ByteData.sublistView(buf.asTypedList(512))
            .getUint64(16, Endian.little);
        return '${free ~/ (1024 * 1024)} MB';
      } finally {
        _release(vol.value);
      }
    } finally {
      calloc.free(vol);
      calloc.free(buf);
    }
  }

  // ------------------------------------------------------------- live view
  void startLiveView() {
    _requireSession();
    try {
      _setU32(_kPropEvfMode, 1);
    } on EdsdkException {
      // sebagian body tidak butuh / tidak mengizinkan
    }
    final int dev = _getU32(_kPropEvfOutputDevice);
    _setU32(_kPropEvfOutputDevice, dev | _kEvfOutputPc);
    _liveView = true;
  }

  void stopLiveView() {
    if (!_sessionOpen || !_liveView) {
      return;
    }
    try {
      final int dev = _getU32(_kPropEvfOutputDevice);
      _setU32(_kPropEvfOutputDevice, dev & ~_kEvfOutputPc);
    } on EdsdkException {
      // abaikan; sesi mungkin sudah putus
    } finally {
      _liveView = false;
    }
  }

  /// Satu frame JPEG live view, atau null bila frame belum siap.
  Uint8List? liveViewFrame() {
    _requireSession();
    if (!_liveView) {
      return null;
    }
    final Pointer<Pointer<Void>> stream = calloc<Pointer<Void>>();
    final Pointer<Pointer<Void>> evf = calloc<Pointer<Void>>();
    Pointer<Void> streamRef = nullptr;
    Pointer<Void> evfRef = nullptr;
    try {
      _chk(_createMemoryStream(0, stream), 'EdsCreateMemoryStream');
      streamRef = stream.value;
      _chk(_createEvfImageRef(streamRef, evf), 'EdsCreateEvfImageRef');
      evfRef = evf.value;
      final int code = _downloadEvfImage(_cam, evfRef);
      if (code == _errObjectNotReady) {
        return null;
      }
      _chk(code, 'EdsDownloadEvfImage');
      final Uint8List bytes = _streamBytes(streamRef);
      return bytes.isEmpty ? null : bytes;
    } finally {
      if (evfRef != nullptr) {
        _release(evfRef);
      }
      if (streamRef != nullptr) {
        _release(streamRef);
      }
      calloc.free(stream);
      calloc.free(evf);
    }
  }

  Future<void> autoFocus() async {
    if (!_sessionOpen || !_liveView) {
      return;
    }
    try {
      _chk(_sendCommand(_cam, _kCmdDoEvfAf, 1), 'DoEvfAf');
      await _pumpFor(const Duration(milliseconds: 400));
    } finally {
      _sendCommand(_cam, _kCmdDoEvfAf, 0);
    }
  }

  // --------------------------------------------------------------- capture
  int _onObjectEvent(int event, Pointer<Void> obj, Pointer<Void> context) {
    try {
      if (event == _kObjectEventDirItemRequestTransfer && obj != nullptr) {
        _downloadItem(obj);
      } else if (obj != nullptr) {
        _release(obj);
      }
    } catch (_) {
      _photoFailed = true; // jangan biarkan exception lolos ke SDK
    }
    return _errOk;
  }

  void _downloadItem(Pointer<Void> item) {
    final Pointer<Uint8> info = calloc<Uint8>(512);
    final Pointer<Pointer<Void>> stream = calloc<Pointer<Void>>();
    Pointer<Void> streamRef = nullptr;
    try {
      _chk(
        _getDirectoryItemInfo(item, info.cast<Void>()),
        'EdsGetDirectoryItemInfo',
      );
      final Uint8List raw = info.asTypedList(512);
      final ByteData view = ByteData.sublistView(raw);
      // size selalu di offset 0. SDK baru: UInt64; SDK lama: UInt32 diikuti
      // isFolder (=0 untuk file), sehingga membaca UInt64 tetap benar.
      final int size = view.getUint64(0, Endian.little);
      // Nama file: offset 20 (SDK baru) atau 16 (SDK lama).
      String name = _cString(raw, 20);
      if (!name.contains('.')) {
        name = _cString(raw, 16);
      }
      _chk(_createMemoryStream(0, stream), 'EdsCreateMemoryStream');
      streamRef = stream.value;
      _chk(_download(item, size, streamRef), 'EdsDownload');
      _chk(_downloadComplete(item), 'EdsDownloadComplete');
      _photo = _streamBytes(streamRef);
      _photoName = name;
    } finally {
      if (streamRef != nullptr) {
        _release(streamRef);
      }
      _release(item);
      calloc.free(info);
      calloc.free(stream);
    }
  }

  void _setSaveTo(bool keepOnCard, bool download) {
    final int target = download && keepOnCard
        ? _kSaveToBoth
        : keepOnCard
        ? _kSaveToCamera
        : _kSaveToHost;
    _setU32(_kPropSaveTo, target);
    if (target != _kSaveToCamera) {
      // Beri tahu kamera bahwa host punya ruang untuk menerima file.
      final Pointer<_EdsCapacity> cap = calloc<_EdsCapacity>();
      try {
        cap.ref
          ..numberOfFreeClusters = 0x7FFFFFFF
          ..bytesPerSector = 0x1000
          ..reset = 1;
        _setCapacity(_cam, cap.ref);
      } finally {
        calloc.free(cap);
      }
    }
  }

  Future<void> _trigger() async {
    for (int attempt = 0; attempt < 6; attempt++) {
      final int code = _sendCommand(_cam, _kCmdTakePicture, 0);
      if (code == _errOk) {
        return;
      }
      if (code == _errDeviceBusy) {
        await _pumpFor(const Duration(milliseconds: 250));
        continue;
      }
      if (code == _errTakePictureAfNg) {
        // jepret tanpa menunggu AF
        _chk(
          _sendCommand(_cam, _kCmdPressShutterButton, _kShutterCompletelyNonAf),
          'ShutterNonAF',
        );
        _sendCommand(_cam, _kCmdPressShutterButton, _kShutterOff);
        return;
      }
      _chk(code, 'TakePicture');
    }
    throw EdsdkException('Kamera tetap sibuk, gagal menjepret.');
  }

  Future<EdsdkShot> capture({
    bool keepOnCard = true,
    bool download = true,
  }) async {
    _requireSession();
    _setSaveTo(keepOnCard, download);
    _photo = null;
    _photoName = '';
    _photoFailed = false;
    await _trigger();

    final bool wantsFile = download || !keepOnCard;
    if (!wantsFile) {
      await _pumpFor(const Duration(milliseconds: 600));
      return const EdsdkShot(bytes: null, fileName: '');
    }

    final DateTime deadline = DateTime.now().add(const Duration(seconds: 25));
    while (_photo == null &&
        !_photoFailed &&
        DateTime.now().isBefore(deadline)) {
      pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_photoFailed) {
      throw EdsdkException('Gagal mengunduh foto dari kamera.');
    }
    final Uint8List? data = _photo;
    if (data == null) {
      throw EdsdkException('Timeout menunggu foto dari kamera.');
    }
    return EdsdkShot(bytes: data, fileName: _photoName);
  }

  // -------------------------------------------------------------- setting
  /// [kind]: iso | aperture | shutter | wb. [value]: label dari aplikasi
  /// ("800", "f/2.8", "1/125", "Daylight") atau kode mentah "0x70".
  void setExposure(String kind, String value) {
    _requireSession();
    final int code = parseSetting(kind, value);
    final int prop = switch (kind) {
      'iso' => _kPropIsoSpeed,
      'aperture' => _kPropAv,
      'shutter' => _kPropTv,
      'wb' => _kPropWhiteBalance,
      _ => throw EdsdkException("Setting '$kind' tidak dikenal."),
    };
    _setU32(prop, code);
  }

  static int parseSetting(String kind, String raw) {
    final String s = raw.trim().toLowerCase();
    if (s.startsWith('0x')) {
      final int? v = int.tryParse(s.substring(2), radix: 16);
      if (v != null) {
        return v;
      }
    }
    switch (kind) {
      case 'iso':
        final int? v = _isoCodes[s];
        if (v == null) {
          throw EdsdkException("ISO '$raw' tidak dikenal.");
        }
        return v;
      case 'wb':
        final int? v = _wbCodes[s];
        if (v == null) {
          throw EdsdkException("White balance '$raw' tidak didukung.");
        }
        return v;
      case 'aperture':
        final RegExpMatch? m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(s);
        if (m == null) {
          throw EdsdkException("Aperture '$raw' tidak valid.");
        }
        return _nearest(_avTable, double.parse(m.group(1)!));
      case 'shutter':
        if (s == 'bulb') {
          return 0x0C;
        }
        final RegExpMatch? frac = RegExp(r'^1/(\d+(?:\.\d+)?)$').firstMatch(s);
        if (frac != null) {
          return _nearest(_tvTable, 1.0 / double.parse(frac.group(1)!));
        }
        final RegExpMatch? secs = RegExp(r'^(\d+(?:\.\d+)?)"?$').firstMatch(s);
        if (secs != null) {
          return _nearest(_tvTable, double.parse(secs.group(1)!));
        }
        throw EdsdkException("Shutter '$raw' tidak valid.");
    }
    throw EdsdkException("Setting '$kind' tidak dikenal.");
  }

  // -------------------------------------------------------------- lifecycle
  void closeCamera() {
    if (_cam != nullptr) {
      try {
        if (_sessionOpen) {
          if (_liveView) {
            stopLiveView();
          }
          _closeSession(_cam);
        }
      } catch (_) {}
      // Lepas referensi walau sesi sudah putus (kabel dicabut) agar tidak bocor.
      _release(_cam);
    }
    _sessionOpen = false;
    _liveView = false;
    _cam = nullptr;
    _callable?.close();
    _callable = null;
  }

  void dispose() {
    closeCamera();
    if (_sdkReady) {
      _terminateSdk();
      _sdkReady = false;
    }
  }
}
