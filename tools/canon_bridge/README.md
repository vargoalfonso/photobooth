# Canon USB Bridge (EDSDK)

Server HTTP lokal yang menghubungkan Luminash Booth ke kamera Canon (EOS R100)
lewat kabel USB. Aplikasi Flutter memanggilnya dengan mode **USB Tether Bridge**
(port 5513).

## Persiapan (sekali saja)

1. Daftar & unduh **Canon EDSDK** dari Canon Developer Community (gratis, perlu
   persetujuan Canon). Pastikan versi SDK-nya mendukung **EOS R100**
   (cek daftar kamera di dokumentasi SDK).
2. Pasang **Python 3.8+ 64-bit** untuk Windows (bit harus sama dengan DLL EDSDK).
3. Salin isi folder `EDSDK\Dll` (berisi `EDSDK.dll`, `EdsImage.dll`, `IconMan`)
   ke `tools\canon_bridge\EDSDK\`.
4. Di kamera: nyalakan, set **mode M** (agar ISO/Av/Tv bisa diubah dari PC),
   kualitas gambar **JPEG** (bukan RAW), matikan Auto Power Off.
5. **Tutup EOS Webcam Utility, EOS Utility, dan aplikasi Canon lain.**
   Kamera hanya bisa dipakai satu aplikasi pada satu waktu (error 0xC0).

## Menjalankan

    start_bridge.bat
    # atau
    python canon_bridge.py --sdk-dll "C:\path\EDSDK.dll" --port 5513

Tes tanpa kamera: `python canon_bridge.py --mock`

Cek: buka http://127.0.0.1:5513/api/camera/info - harus muncul nama kamera.

## Di aplikasi

Canon Setup -> mode **USB Tether Bridge**, host `127.0.0.1`, port `5513`,
aktifkan Canon, lalu Connect. (Bridge dan aplikasi harus di PC yang sama;
aplikasi Android tidak bisa memakai 127.0.0.1 milik PC.)

## Endpoint

| Method | Path | Keterangan |
|---|---|---|
| GET | /api/camera/info, battery, storage, lens | info kamera |
| POST | /api/liveview/start, stop | live view |
| GET | /api/liveview/frame | JPEG (204 bila belum siap) |
| POST | /api/autofocus | AF live view |
| POST | /api/capture | body `{keepOnCard, download, targetDirectory}` |
| GET | /api/capture/last | JPEG foto terakhir |
| POST | /api/settings/iso, aperture, shutter, wb | body `{"value": "..."}` |

## Catatan penting

- Kode ini **belum diuji dengan kamera asli** (hanya mode mock). Konstanta dan
  struct EDSDK ditulis dari `EDSDKTypes.h`; cocokkan dengan versi SDK Anda,
  terutama `EdsDirectoryItemInfo` (SDK lama memakai `size` 32-bit).
- Tabel kode ISO/Av/Tv/WB di `canon_bridge.py` perlu diverifikasi ke
  `EDSDKTypes.h`. Nilai di luar tabel ditolak dengan error 400.
- Semua panggilan EDSDK dijalankan di satu thread (syarat SDK).
