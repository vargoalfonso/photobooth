#!/usr/bin/env python3
"""
Canon USB bridge untuk Luminash Booth.

Server HTTP lokal yang berbicara ke kamera Canon (mis. EOS R100) lewat USB
memakai Canon EDSDK, dan menyediakan endpoint yang dipanggil oleh
CanonCameraService (mode "USB Tether Bridge") di aplikasi Flutter:

    GET  /api/camera/info        GET  /api/camera/battery
    GET  /api/camera/storage     GET  /api/camera/lens
    POST /api/liveview/start     GET  /api/liveview/frame   (image/jpeg)
    POST /api/liveview/stop      POST /api/autofocus
    POST /api/capture            GET  /api/capture/last     (image/jpeg)
    POST /api/settings/{iso|aperture|shutter|wb}   body: {"value": "..."}
    GET  /api/health

Hanya butuh Python 3.8+ (64-bit, Windows) tanpa package tambahan.
Semua panggilan EDSDK dijalankan di SATU thread khusus (syarat EDSDK).

Pakai:
    python canon_bridge.py --sdk-dll "C:\\EDSDK\\Dll\\EDSDK.dll"
    python canon_bridge.py --mock        # tes tanpa kamera / tanpa SDK
"""

from __future__ import annotations

import argparse
import base64
import ctypes
import io
import json
import os
import queue
import re
import sys
import threading
import time
from concurrent.futures import Future
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable, Dict, Optional, Tuple

# ---------------------------------------------------------------------------
# Konstanta EDSDK (dari EDSDKTypes.h). Verifikasi dengan versi SDK Anda.
# ---------------------------------------------------------------------------
kEdsPropID_ProductName = 0x00000002
kEdsPropID_FirmwareVersion = 0x00000007
kEdsPropID_BatteryLevel = 0x00000008
kEdsPropID_SaveTo = 0x0000000B
kEdsPropID_BodyIDEx = 0x00000015
kEdsPropID_WhiteBalance = 0x00000106
kEdsPropID_Av = 0x00000402
kEdsPropID_Tv = 0x00000403
kEdsPropID_ISOSpeed = 0x00000404
kEdsPropID_LensName = 0x00000409
kEdsPropID_Evf_OutputDevice = 0x00000500
kEdsPropID_Evf_Mode = 0x00000501

kEdsCameraCommand_TakePicture = 0x00000000
kEdsCameraCommand_PressShutterButton = 0x00000004
kEdsCameraCommand_DoEvfAf = 0x00000102

kEdsCameraCommand_ShutterButton_OFF = 0x00000000
kEdsCameraCommand_ShutterButton_Completely_NonAF = 0x00010003

kEdsObjectEvent_All = 0x00000200
kEdsObjectEvent_DirItemRequestTransfer = 0x00000208

kEdsSaveTo_Camera = 1
kEdsSaveTo_Host = 2
kEdsSaveTo_Both = 3

kEdsEvfOutputDevice_PC = 2

EDS_ERR_OK = 0
EDS_ERR_DEVICE_NOT_FOUND = 0x80
EDS_ERR_DEVICE_BUSY = 0x81
EDS_ERR_SESSION_NOT_OPEN = 0x2003
EDS_ERR_OBJECT_NOTREADY = 0xA102
EDS_ERR_TAKE_PICTURE_AF_NG = 0x8D01
EDS_ERR_COMM_PORT_IS_IN_USE = 0xC0

ERROR_HINTS = {
    EDS_ERR_DEVICE_NOT_FOUND: "kamera tidak ditemukan (cek kabel USB / nyalakan kamera)",
    EDS_ERR_DEVICE_BUSY: "kamera sibuk",
    EDS_ERR_SESSION_NOT_OPEN: "sesi kamera belum terbuka",
    EDS_ERR_OBJECT_NOTREADY: "objek belum siap",
    EDS_ERR_TAKE_PICTURE_AF_NG: "autofocus gagal saat jepret",
    EDS_ERR_COMM_PORT_IS_IN_USE: (
        "kamera sedang dipakai aplikasi lain - tutup EOS Webcam Utility, "
        "EOS Utility, atau aplikasi Canon lain"
    ),
}


class BridgeError(Exception):
    def __init__(self, message: str, status: int = 500):
        super().__init__(message)
        self.status = status


class EdsError(BridgeError):
    def __init__(self, code: int, where: str):
        hint = ERROR_HINTS.get(code, "")
        msg = f"EDSDK {where} gagal: 0x{code:X}" + (f" ({hint})" if hint else "")
        super().__init__(msg, 503)
        self.code = code


# ---------------------------------------------------------------------------
# Tabel nilai eksposur (label dari aplikasi -> kode EDSDK).
# Kamera hanya menerima nilai yang valid untuk mode/lensa saat ini; kamera
# harus di mode M (manual) agar Av/Tv bisa diubah dari komputer.
# ---------------------------------------------------------------------------
ISO_CODES = {
    "auto": 0x00, "100": 0x48, "200": 0x50, "400": 0x58, "800": 0x60,
    "1600": 0x68, "3200": 0x70, "6400": 0x78, "12800": 0x80, "25600": 0x88,
}

AV_TABLE = {  # f-number -> kode
    1.0: 0x08, 1.1: 0x0B, 1.2: 0x0C, 1.4: 0x10, 1.6: 0x13, 1.8: 0x14,
    2.0: 0x18, 2.2: 0x1B, 2.5: 0x1C, 2.8: 0x20, 3.2: 0x23, 3.5: 0x24,
    4.0: 0x28, 4.5: 0x2B, 5.0: 0x2C, 5.6: 0x30, 6.3: 0x33, 7.1: 0x34,
    8.0: 0x38, 9.0: 0x3B, 10.0: 0x3C, 11.0: 0x40, 13.0: 0x43, 14.0: 0x44,
    16.0: 0x48, 18.0: 0x4B, 20.0: 0x4C, 22.0: 0x50,
}

TV_TABLE = {  # detik -> kode
    30.0: 0x10, 25.0: 0x13, 20.0: 0x14, 15.0: 0x18, 13.0: 0x1B, 10.0: 0x1C,
    8.0: 0x20, 6.0: 0x23, 5.0: 0x24, 4.0: 0x28, 3.2: 0x2B, 2.5: 0x2C,
    2.0: 0x30, 1.6: 0x33, 1.3: 0x34, 1.0: 0x38, 0.8: 0x3B, 0.6: 0x3C,
    0.5: 0x40, 0.4: 0x43, 0.3: 0x44,
    1 / 4: 0x48, 1 / 5: 0x4B, 1 / 6: 0x4C, 1 / 8: 0x50, 1 / 10: 0x53,
    1 / 13: 0x54, 1 / 15: 0x58, 1 / 20: 0x5B, 1 / 25: 0x5C, 1 / 30: 0x60,
    1 / 40: 0x63, 1 / 50: 0x64, 1 / 60: 0x68, 1 / 80: 0x6B, 1 / 100: 0x6C,
    1 / 125: 0x70, 1 / 160: 0x73, 1 / 200: 0x74, 1 / 250: 0x78,
    1 / 320: 0x7B, 1 / 400: 0x7C, 1 / 500: 0x80, 1 / 640: 0x83,
    1 / 800: 0x84, 1 / 1000: 0x88,
}

WB_CODES = {
    "auto": 0, "daylight": 1, "cloudy": 2, "tungsten": 3,
    "fluorescent": 4, "flash": 5, "shade": 8,
}


def _nearest(table: Dict[float, int], value: float, tol: float = 0.03) -> int:
    best = min(table, key=lambda k: abs(k - value) / max(k, 1e-9))
    if abs(best - value) / max(best, 1e-9) > tol:
        raise BridgeError(f"nilai {value} tidak ada di tabel kamera", 400)
    return table[best]


def parse_setting(kind: str, raw: str) -> int:
    s = (raw or "").strip().lower()
    if s.startswith("0x"):  # kode mentah, mis. "0x70"
        return int(s, 16)
    if kind == "iso":
        if s in ISO_CODES:
            return ISO_CODES[s]
        raise BridgeError(f"ISO '{raw}' tidak dikenal", 400)
    if kind == "wb":
        if s in WB_CODES:
            return WB_CODES[s]
        raise BridgeError(f"White balance '{raw}' tidak didukung", 400)
    if kind == "aperture":
        m = re.search(r"(\d+(?:\.\d+)?)", s)
        if not m:
            raise BridgeError(f"Aperture '{raw}' tidak valid", 400)
        return _nearest(AV_TABLE, float(m.group(1)))
    if kind == "shutter":
        if s == "bulb":
            return 0x0C
        m = re.fullmatch(r"1/(\d+(?:\.\d+)?)", s)
        if m:
            return _nearest(TV_TABLE, 1.0 / float(m.group(1)))
        m = re.fullmatch(r'(\d+(?:\.\d+)?)"?', s)
        if m:
            return _nearest(TV_TABLE, float(m.group(1)))
        raise BridgeError(f"Shutter '{raw}' tidak valid", 400)
    raise BridgeError(f"setting '{kind}' tidak dikenal", 404)


# ---------------------------------------------------------------------------
# Backend kamera
# ---------------------------------------------------------------------------
class Backend:
    """Antarmuka backend. Semua method dipanggil dari thread worker."""

    def setup(self) -> None: ...
    def shutdown(self) -> None: ...
    def pump(self) -> None: ...
    def info(self) -> Dict[str, Any]: ...
    def battery(self) -> Dict[str, Any]: ...
    def storage(self) -> Dict[str, Any]: ...
    def lens(self) -> Dict[str, Any]: ...
    def liveview_start(self) -> None: ...
    def liveview_stop(self) -> None: ...
    def liveview_frame(self) -> bytes: ...
    def autofocus(self) -> None: ...
    def capture(self, keep: bool, download: bool, target_dir: str) -> Dict[str, Any]: ...
    def set_setting(self, kind: str, value: str) -> None: ...
    last_photo: Optional[bytes] = None


class MockBackend(Backend):
    """Kamera palsu untuk menguji bridge + aplikasi tanpa hardware."""

    _TINY_JPEG = base64.b64decode(
        "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////"
        "////////////////////////////////////////////////////////////wgALCAAB"
        "AAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA="
    )

    def __init__(self) -> None:
        self._live = False
        self.settings: Dict[str, str] = {}
        self.last_photo = None

    def _jpeg(self, label: str) -> bytes:
        try:
            from PIL import Image, ImageDraw  # type: ignore

            img = Image.new("RGB", (960, 640), (40, 60, 90))
            d = ImageDraw.Draw(img)
            d.text((20, 20), f"MOCK CANON  {label}  {time.strftime('%H:%M:%S')}",
                   fill=(255, 255, 255))
            buf = io.BytesIO()
            img.save(buf, "JPEG", quality=70)
            return buf.getvalue()
        except Exception:
            return self._TINY_JPEG

    def info(self):
        return {"productname": "Canon EOS R100 (MOCK)", "serialnumber": "MOCK0001",
                "firmwareversion": "1.0.0", "model": "Canon EOS R100 (MOCK)"}

    def battery(self):
        return {"level": 87}

    def storage(self):
        return {"free": "12000 MB"}

    def lens(self):
        return {"name": "RF-S18-45mm F4.5-6.3 IS STM (MOCK)"}

    def liveview_start(self):
        self._live = True

    def liveview_stop(self):
        self._live = False

    def liveview_frame(self):
        if not self._live:
            raise BridgeError("live view belum dimulai", 409)
        return self._jpeg("LIVE")

    def autofocus(self):
        time.sleep(0.2)

    def capture(self, keep, download, target_dir):
        time.sleep(0.4)
        data = self._jpeg("PHOTO")
        self.last_photo = data
        return _finish_capture(data, target_dir)

    def set_setting(self, kind, value):
        parse_setting(kind, value)  # validasi saja
        self.settings[kind] = value


class EdsdkBackend(Backend):
    """Backend nyata memakai Canon EDSDK lewat ctypes (Windows)."""

    class _DeviceInfo(ctypes.Structure):
        _fields_ = [
            ("szPortName", ctypes.c_char * 256),
            ("szDeviceDescription", ctypes.c_char * 256),
            ("deviceSubType", ctypes.c_uint32),
            ("reserved", ctypes.c_uint32),
        ]

    class _DirItemInfo(ctypes.Structure):  # EDSDK >= 13 (size 64-bit)
        _fields_ = [
            ("size", ctypes.c_uint64),
            ("isFolder", ctypes.c_int32),
            ("groupID", ctypes.c_uint32),
            ("option", ctypes.c_uint32),
            ("szFileName", ctypes.c_char * 256),
            ("format", ctypes.c_uint32),
            ("dateTime", ctypes.c_uint32),
        ]

    class _Capacity(ctypes.Structure):
        _fields_ = [
            ("numberOfFreeClusters", ctypes.c_int32),
            ("bytesPerSector", ctypes.c_int32),
            ("reset", ctypes.c_int32),
        ]

    class _VolumeInfo(ctypes.Structure):
        _fields_ = [
            ("storageType", ctypes.c_uint32),
            ("access", ctypes.c_uint32),
            ("maxCapacity", ctypes.c_uint64),
            ("freeSpaceInBytes", ctypes.c_uint64),
            ("szVolumeLabel", ctypes.c_char * 256),
        ]

    def __init__(self, dll_path: str) -> None:
        self.dll_path = dll_path
        self.eds: Any = None
        self.cam = ctypes.c_void_p()
        self.connected = False
        self.live = False
        self.last_photo = None
        self._photo: Optional[bytes] = None
        self._photo_name = ""
        self._photo_err: Optional[int] = None
        self._cb = None  # simpan referensi callback agar tidak di-GC
        self._sdk_ready = False

    # ------------------------------------------------------------ low level
    def _load(self) -> None:
        if not hasattr(ctypes, "WinDLL"):
            raise BridgeError("EDSDK hanya tersedia di Windows (gunakan --mock untuk tes).")
        if not os.path.isfile(self.dll_path):
            raise BridgeError(f"EDSDK.dll tidak ditemukan: {self.dll_path}")
        if hasattr(os, "add_dll_directory"):
            os.add_dll_directory(os.path.dirname(os.path.abspath(self.dll_path)))
        self.eds = ctypes.WinDLL(self.dll_path)
        v, u32, i32, u64 = ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int32, ctypes.c_uint64
        pv = ctypes.POINTER

        def sig(name: str, args: list) -> None:
            f = getattr(self.eds, name)
            f.argtypes = args
            f.restype = u32

        sig("EdsInitializeSDK", [])
        sig("EdsTerminateSDK", [])
        sig("EdsGetEvent", [])
        sig("EdsRelease", [v])
        sig("EdsGetCameraList", [pv(v)])
        sig("EdsGetChildCount", [v, pv(u32)])
        sig("EdsGetChildAtIndex", [v, i32, pv(v)])
        sig("EdsGetDeviceInfo", [v, pv(self._DeviceInfo)])
        sig("EdsOpenSession", [v])
        sig("EdsCloseSession", [v])
        sig("EdsSendCommand", [v, u32, i32])
        sig("EdsGetPropertyData", [v, u32, i32, u32, v])
        sig("EdsSetPropertyData", [v, u32, i32, u32, v])
        sig("EdsSetCapacity", [v, self._Capacity])
        sig("EdsCreateMemoryStream", [u64, pv(v)])
        sig("EdsGetPointer", [v, pv(v)])
        sig("EdsGetLength", [v, pv(u64)])
        sig("EdsCreateEvfImageRef", [v, pv(v)])
        sig("EdsDownloadEvfImage", [v, v])
        sig("EdsGetDirectoryItemInfo", [v, pv(self._DirItemInfo)])
        sig("EdsDownload", [v, u64, v])
        sig("EdsDownloadComplete", [v])
        sig("EdsGetVolumeInfo", [v, pv(self._VolumeInfo)])

        cb_type = getattr(ctypes, "WINFUNCTYPE", ctypes.CFUNCTYPE)(
            u32, u32, v, v)
        self.eds.EdsSetObjectEventHandler.argtypes = [v, u32, cb_type, v]
        self.eds.EdsSetObjectEventHandler.restype = u32
        self._cb_type = cb_type

    def _chk(self, code: int, where: str) -> None:
        if code != EDS_ERR_OK:
            if code in (EDS_ERR_DEVICE_NOT_FOUND, EDS_ERR_SESSION_NOT_OPEN):
                self.connected = False
                self.live = False
            raise EdsError(code, where)

    def _get_u32(self, prop: int) -> int:
        val = ctypes.c_uint32()
        self._chk(self.eds.EdsGetPropertyData(
            self.cam, prop, 0, 4, ctypes.byref(val)), f"get 0x{prop:X}")
        return val.value

    def _set_u32(self, prop: int, value: int) -> None:
        val = ctypes.c_uint32(value)
        self._chk(self.eds.EdsSetPropertyData(
            self.cam, prop, 0, 4, ctypes.byref(val)), f"set 0x{prop:X}")

    def _get_str(self, prop: int) -> str:
        buf = ctypes.create_string_buffer(256)
        self._chk(self.eds.EdsGetPropertyData(
            self.cam, prop, 0, 256, buf), f"get 0x{prop:X}")
        return buf.value.decode("utf-8", "replace")

    def _stream_bytes(self, stream: ctypes.c_void_p) -> bytes:
        ptr = ctypes.c_void_p()
        length = ctypes.c_uint64()
        self._chk(self.eds.EdsGetPointer(stream, ctypes.byref(ptr)), "GetPointer")
        self._chk(self.eds.EdsGetLength(stream, ctypes.byref(length)), "GetLength")
        if not ptr.value or length.value == 0:
            return b""
        return ctypes.string_at(ptr.value, length.value)

    # ------------------------------------------------------------ lifecycle
    def setup(self) -> None:
        self._load()
        self._chk(self.eds.EdsInitializeSDK(), "InitializeSDK")
        self._sdk_ready = True

    def shutdown(self) -> None:
        try:
            self._disconnect()
        finally:
            if self._sdk_ready:
                self.eds.EdsTerminateSDK()
                self._sdk_ready = False

    def pump(self) -> None:
        if self._sdk_ready:
            self.eds.EdsGetEvent()

    def _on_object_event(self, event: int, obj: Any, _ctx: Any) -> int:
        try:
            if event == kEdsObjectEvent_DirItemRequestTransfer and obj:
                self._download_item(ctypes.c_void_p(obj))
            elif obj:
                self.eds.EdsRelease(ctypes.c_void_p(obj))
        except Exception as exc:  # jangan biarkan exception lolos ke SDK
            self._photo_err = -1
            print(f"[bridge] error di event handler: {exc}", file=sys.stderr)
        return EDS_ERR_OK

    def _download_item(self, item: ctypes.c_void_p) -> None:
        info = self._DirItemInfo()
        self._chk(self.eds.EdsGetDirectoryItemInfo(item, ctypes.byref(info)), "DirItemInfo")
        stream = ctypes.c_void_p()
        self._chk(self.eds.EdsCreateMemoryStream(0, ctypes.byref(stream)), "CreateMemoryStream")
        try:
            self._chk(self.eds.EdsDownload(item, info.size, stream), "Download")
            self._chk(self.eds.EdsDownloadComplete(item), "DownloadComplete")
            self._photo = self._stream_bytes(stream)
            self._photo_name = info.szFileName.decode("utf-8", "replace")
        finally:
            self.eds.EdsRelease(stream)
            self.eds.EdsRelease(item)

    def _ensure_connected(self) -> None:
        if self.connected:
            return
        cam_list = ctypes.c_void_p()
        self._chk(self.eds.EdsGetCameraList(ctypes.byref(cam_list)), "GetCameraList")
        try:
            count = ctypes.c_uint32()
            self._chk(self.eds.EdsGetChildCount(cam_list, ctypes.byref(count)), "GetChildCount")
            if count.value == 0:
                raise BridgeError(
                    "Tidak ada kamera Canon terdeteksi lewat USB. Cek kabel, nyalakan "
                    "kamera, dan tutup EOS Webcam Utility / EOS Utility.", 503)
            self._chk(self.eds.EdsGetChildAtIndex(
                cam_list, 0, ctypes.byref(self.cam)), "GetChildAtIndex")
        finally:
            self.eds.EdsRelease(cam_list)
        self._chk(self.eds.EdsOpenSession(self.cam), "OpenSession")
        self._cb = self._cb_type(self._on_object_event)
        self._chk(self.eds.EdsSetObjectEventHandler(
            self.cam, kEdsObjectEvent_All, self._cb, None), "SetObjectEventHandler")
        self.connected = True
        print("[bridge] kamera terhubung:", self._get_str(kEdsPropID_ProductName))

    def _disconnect(self) -> None:
        if self.connected:
            try:
                if self.live:
                    self.liveview_stop()
                self.eds.EdsCloseSession(self.cam)
            except Exception:
                pass
            self.eds.EdsRelease(self.cam)
        self.connected = False
        self.live = False

    # ------------------------------------------------------------- queries
    def info(self):
        self._ensure_connected()
        name = self._get_str(kEdsPropID_ProductName)
        try:
            serial = self._get_str(kEdsPropID_BodyIDEx)
        except BridgeError:
            serial = "-"
        try:
            fw = self._get_str(kEdsPropID_FirmwareVersion)
        except BridgeError:
            fw = "-"
        return {"productname": name, "model": name,
                "serialnumber": serial, "firmwareversion": fw}

    def battery(self):
        self._ensure_connected()
        try:
            level = self._get_u32(kEdsPropID_BatteryLevel)
        except BridgeError:
            return {"level": "-"}
        return {"level": "AC" if level == 0xFFFFFFFF else level}

    def storage(self):
        self._ensure_connected()
        try:
            vol = ctypes.c_void_p()
            self._chk(self.eds.EdsGetChildAtIndex(self.cam, 0, ctypes.byref(vol)), "Volume")
            vi = self._VolumeInfo()
            self._chk(self.eds.EdsGetVolumeInfo(vol, ctypes.byref(vi)), "VolumeInfo")
            self.eds.EdsRelease(vol)
            return {"free": f"{vi.freeSpaceInBytes // (1024 * 1024)} MB"}
        except BridgeError:
            return {"free": "-"}

    def lens(self):
        self._ensure_connected()
        try:
            return {"name": self._get_str(kEdsPropID_LensName)}
        except BridgeError:
            return {"name": "-"}

    # ----------------------------------------------------------- live view
    def liveview_start(self):
        self._ensure_connected()
        try:
            self._set_u32(kEdsPropID_Evf_Mode, 1)
        except BridgeError:
            pass  # sebagian body tidak butuh / tidak mengizinkan
        dev = self._get_u32(kEdsPropID_Evf_OutputDevice)
        self._set_u32(kEdsPropID_Evf_OutputDevice, dev | kEdsEvfOutputDevice_PC)
        self.live = True

    def liveview_stop(self):
        if not self.connected:
            return
        try:
            dev = self._get_u32(kEdsPropID_Evf_OutputDevice)
            self._set_u32(kEdsPropID_Evf_OutputDevice, dev & ~kEdsEvfOutputDevice_PC)
        finally:
            self.live = False

    def liveview_frame(self):
        self._ensure_connected()
        if not self.live:
            raise BridgeError("live view belum dimulai", 409)
        stream = ctypes.c_void_p()
        evf = ctypes.c_void_p()
        self._chk(self.eds.EdsCreateMemoryStream(0, ctypes.byref(stream)), "CreateMemoryStream")
        try:
            self._chk(self.eds.EdsCreateEvfImageRef(stream, ctypes.byref(evf)), "CreateEvfImageRef")
            code = self.eds.EdsDownloadEvfImage(self.cam, evf)
            if code == EDS_ERR_OBJECT_NOTREADY:
                return b""  # frame belum siap -> aplikasi akan abaikan
            self._chk(code, "DownloadEvfImage")
            return self._stream_bytes(stream)
        finally:
            if evf.value:
                self.eds.EdsRelease(evf)
            self.eds.EdsRelease(stream)

    def autofocus(self):
        self._ensure_connected()
        if not self.live:
            return
        try:
            self._chk(self.eds.EdsSendCommand(self.cam, kEdsCameraCommand_DoEvfAf, 1), "DoEvfAf")
            self._sleep_pump(0.4)
        finally:
            self.eds.EdsSendCommand(self.cam, kEdsCameraCommand_DoEvfAf, 0)

    # -------------------------------------------------------------- capture
    def _sleep_pump(self, seconds: float) -> None:
        end = time.time() + seconds
        while time.time() < end:
            self.pump()
            time.sleep(0.02)

    def _set_save_to(self, keep: bool, download: bool) -> None:
        if download and keep:
            target = kEdsSaveTo_Both
        elif keep:
            target = kEdsSaveTo_Camera
        else:
            target = kEdsSaveTo_Host
        self._set_u32(kEdsPropID_SaveTo, target)
        if target != kEdsSaveTo_Camera:
            cap = self._Capacity(0x7FFFFFFF, 0x1000, 1)
            self.eds.EdsSetCapacity(self.cam, cap)  # beri tahu kamera: host siap

    def _trigger(self) -> None:
        for _ in range(6):
            code = self.eds.EdsSendCommand(self.cam, kEdsCameraCommand_TakePicture, 0)
            if code == EDS_ERR_OK:
                return
            if code == EDS_ERR_DEVICE_BUSY:
                self._sleep_pump(0.25)
                continue
            if code == EDS_ERR_TAKE_PICTURE_AF_NG:
                # jepret tanpa menunggu AF
                self._chk(self.eds.EdsSendCommand(
                    self.cam, kEdsCameraCommand_PressShutterButton,
                    kEdsCameraCommand_ShutterButton_Completely_NonAF), "ShutterNonAF")
                self.eds.EdsSendCommand(
                    self.cam, kEdsCameraCommand_PressShutterButton,
                    kEdsCameraCommand_ShutterButton_OFF)
                return
            self._chk(code, "TakePicture")
        raise BridgeError("kamera tetap sibuk, gagal menjepret", 503)

    def capture(self, keep, download, target_dir):
        self._ensure_connected()
        self._set_save_to(keep, download)
        self._photo, self._photo_name, self._photo_err = None, "", None
        self._trigger()

        wants_file = download or not keep
        deadline = time.time() + 25
        while wants_file and self._photo is None and time.time() < deadline:
            if self._photo_err is not None:
                raise BridgeError("gagal mengunduh foto dari kamera", 500)
            self.pump()
            time.sleep(0.02)
        if not wants_file:
            self._sleep_pump(0.6)
            return {"path": None, "size": 0}
        if self._photo is None:
            raise BridgeError("timeout menunggu foto dari kamera", 504)

        ext = os.path.splitext(self._photo_name)[1].lower()
        if ext not in (".jpg", ".jpeg"):
            print(f"[bridge] PERINGATAN: file {self._photo_name} bukan JPEG. "
                  "Set kualitas gambar kamera ke JPEG (bukan RAW).", file=sys.stderr)
        self.last_photo = self._photo
        return _finish_capture(self._photo, target_dir)

    # ------------------------------------------------------------- settings
    def set_setting(self, kind, value):
        self._ensure_connected()
        code = parse_setting(kind, value)
        prop = {"iso": kEdsPropID_ISOSpeed, "aperture": kEdsPropID_Av,
                "shutter": kEdsPropID_Tv, "wb": kEdsPropID_WhiteBalance}[kind]
        self._set_u32(prop, code)


def _finish_capture(data: bytes, target_dir: str) -> Dict[str, Any]:
    path = None
    if target_dir:
        os.makedirs(target_dir, exist_ok=True)
        path = os.path.abspath(os.path.join(
            target_dir, f"booth_{int(time.time() * 1000)}.jpg"))
        with open(path, "wb") as f:
            f.write(data)
    return {"path": path, "size": len(data)}


# ---------------------------------------------------------------------------
# Worker: semua panggilan backend berjalan di satu thread
# ---------------------------------------------------------------------------
class Worker(threading.Thread):
    def __init__(self, backend: Backend) -> None:
        super().__init__(name="camera-worker", daemon=True)
        self.backend = backend
        self.jobs: "queue.Queue[Optional[Tuple[Callable, tuple, Future]]]" = queue.Queue()
        self.ready = threading.Event()
        self.init_error: Optional[BaseException] = None

    def run(self) -> None:
        try:
            self.backend.setup()
        except BaseException as exc:  # noqa: BLE001
            self.init_error = exc
            self.ready.set()
            return
        self.ready.set()
        while True:
            try:
                job = self.jobs.get(timeout=0.02)
            except queue.Empty:
                try:
                    self.backend.pump()
                except Exception:
                    pass
                continue
            if job is None:
                break
            fn, args, fut = job
            if fut.set_running_or_notify_cancel():
                try:
                    fut.set_result(fn(*args))
                except BaseException as exc:  # noqa: BLE001
                    fut.set_exception(exc)
        self.backend.shutdown()

    def call(self, fn: Callable, *args: Any, timeout: float = 40.0) -> Any:
        if self.init_error:
            raise BridgeError(f"inisialisasi gagal: {self.init_error}", 500)
        fut: Future = Future()
        self.jobs.put((fn, args, fut))
        try:
            return fut.result(timeout=timeout)
        except TimeoutError:
            raise BridgeError("kamera tidak merespons (timeout)", 504)

    def stop(self) -> None:
        self.jobs.put(None)


# ---------------------------------------------------------------------------
# HTTP server
# ---------------------------------------------------------------------------
def make_handler(worker: Worker, quiet: bool):
    be = worker.backend

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        server_version = "CanonBridge/1.0"

        def log_message(self, fmt, *args):  # noqa: A003
            if not quiet:
                sys.stderr.write("[http] " + fmt % args + "\n")

        # ------------------------------------------------------ helpers
        def _send(self, status: int, body: bytes, ctype: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            if body:
                self.wfile.write(body)

        def _json(self, obj: Any, status: int = 200) -> None:
            self._send(status, json.dumps(obj).encode(), "application/json")

        def _body(self) -> Dict[str, Any]:
            n = int(self.headers.get("Content-Length") or 0)
            if n <= 0:
                return {}
            try:
                data = json.loads(self.rfile.read(n) or b"{}")
                return data if isinstance(data, dict) else {}
            except json.JSONDecodeError:
                raise BridgeError("body bukan JSON valid", 400)

        def _route(self, method: str) -> None:
            path = self.path.split("?", 1)[0].rstrip("/")
            if path.startswith("/api"):
                path = path[4:]
            try:
                self._dispatch(method, path)
            except BridgeError as exc:
                self._json({"error": str(exc)}, exc.status)
            except Exception as exc:  # noqa: BLE001
                self._json({"error": f"internal error: {exc}"}, 500)

        def _dispatch(self, method: str, path: str) -> None:
            if method == "GET":
                if path == "/health":
                    return self._json({"ok": True, "mock": isinstance(be, MockBackend)})
                if path == "/camera/info":
                    return self._json(worker.call(be.info))
                if path == "/camera/battery":
                    return self._json(worker.call(be.battery))
                if path == "/camera/storage":
                    return self._json(worker.call(be.storage))
                if path == "/camera/lens":
                    return self._json(worker.call(be.lens))
                if path == "/liveview/frame":
                    frame = worker.call(be.liveview_frame, timeout=8)
                    if not frame:
                        return self._send(204, b"", "image/jpeg")
                    return self._send(200, frame, "image/jpeg")
                if path == "/capture/last":
                    if not be.last_photo:
                        raise BridgeError("belum ada foto", 404)
                    return self._send(200, be.last_photo, "image/jpeg")
            elif method == "POST":
                if path == "/liveview/start":
                    worker.call(be.liveview_start)
                    return self._json({"ok": True})
                if path == "/liveview/stop":
                    worker.call(be.liveview_stop)
                    return self._json({"ok": True})
                if path == "/autofocus":
                    worker.call(be.autofocus)
                    return self._json({"ok": True})
                if path == "/capture":
                    body = self._body()
                    res = worker.call(
                        be.capture,
                        bool(body.get("keepOnCard", True)),
                        bool(body.get("download", True)),
                        str(body.get("targetDirectory") or ""),
                        timeout=45)
                    return self._json({"ok": True, **res})
                m = re.fullmatch(r"/settings/(iso|aperture|shutter|wb)", path)
                if m:
                    value = str(self._body().get("value", ""))
                    worker.call(be.set_setting, m.group(1), value)
                    return self._json({"ok": True, "value": value})
            raise BridgeError(f"endpoint tidak ada: {method} {path}", 404)

        def do_GET(self):  # noqa: N802
            self._route("GET")

        def do_POST(self):  # noqa: N802
            self._route("POST")

        def do_PUT(self):  # noqa: N802
            self._route("POST")

        def do_OPTIONS(self):  # noqa: N802
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.send_header("Content-Length", "0")
            self.end_headers()

    return Handler


def main() -> int:
    ap = argparse.ArgumentParser(description="Canon USB bridge (EDSDK) untuk Luminash Booth")
    ap.add_argument("--host", default="127.0.0.1",
                    help="alamat listen (default 127.0.0.1; pakai 0.0.0.0 bila app di perangkat lain)")
    ap.add_argument("--port", type=int, default=5513)
    ap.add_argument("--sdk-dll", default=os.environ.get("EDSDK_DLL", "EDSDK.dll"),
                    help="path ke EDSDK.dll (atau env EDSDK_DLL)")
    ap.add_argument("--mock", action="store_true", help="kamera palsu untuk tes")
    ap.add_argument("--quiet", action="store_true", help="matikan log request")
    args = ap.parse_args()

    backend: Backend = MockBackend() if args.mock else EdsdkBackend(args.sdk_dll)
    worker = Worker(backend)
    worker.start()
    worker.ready.wait(10)
    if worker.init_error:
        print(f"[bridge] GAGAL init: {worker.init_error}", file=sys.stderr)
        return 1

    server = ThreadingHTTPServer((args.host, args.port), make_handler(worker, args.quiet))
    server.daemon_threads = True
    mode = "MOCK" if args.mock else "EDSDK"
    print(f"[bridge] {mode} siap di http://{args.host}:{args.port}/api  (Ctrl+C untuk berhenti)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        worker.stop()
        worker.join(5)
    return 0


if __name__ == "__main__":
    sys.exit(main())
