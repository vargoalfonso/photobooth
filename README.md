# Luminash Booth

Prototype aplikasi Flutter untuk photo booth Android/APK dengan launcher seperti benchmark Luminash.

## Fitur awal

- Launcher page dengan tombol menu vertikal
- Halaman `Enter Booth` dengan preview kamera
- Halaman `Settings`, `Crop`, `Frames`, dan `Filters`
- Pemilihan kamera dari daftar device yang tersedia
- State pengaturan bersama untuk preview booth

## Kondisi saat ini

Project ini disiapkan manual karena Flutter SDK belum terpasang di mesin target saat file dibuat. Source Flutter utamanya sudah siap, tetapi file platform seperti `android/`, `ios/`, `linux/`, `macos/`, `web/`, dan `windows/` perlu digenerate sekali dengan Flutter CLI.

## Langkah menjalankan

1. Install Flutter SDK
2. Dari folder project, jalankan:

```bash
flutter create .
flutter pub get
flutter run
```

## Build APK

```bash
flutter build apk
```

## Catatan integrasi kamera

Package yang digunakan adalah `camera`, sehingga untuk Android nantinya izin kamera akan otomatis ditambahkan/ditinjau di project platform hasil `flutter create .`. Jika ingin integrasi printer, DSLR, atau multi-camera USB yang lebih kompleks, biasanya perlu plugin native Android tambahan.

## Kamera Canon lewat USB (EDSDK langsung)

Mode **USB Langsung (Canon EDSDK)** memuat `EDSDK.dll` di dalam aplikasi lewat
`dart:ffi`: tanpa Python, tanpa bridge. Hanya Windows.

1. Unduh Canon EDSDK (64-bit, mendukung EOS R100) dari Canon Developer Community.
2. Salin isi folder `Dll` ke `windows/edsdk/` (lihat `windows/edsdk/README.txt`),
   atau pilih `EDSDK.dll` langsung dari menu Canon Setup di aplikasi.
3. `flutter pub get` lalu `flutter build windows` (atau `flutter run -d windows`).
4. Kamera: nyalakan, mode **M**, kualitas **JPEG**, Auto Power Off mati.
5. **Tutup EOS Webcam Utility / EOS Utility** (kamera hanya bisa dipakai satu aplikasi).
6. Canon Setup -> mode USB Langsung -> Test Connection.

## Setup otomatis (tanpa klik)

Begitu aplikasi dibuka, tanpa menekan apa pun:

- **Kamera:** aplikasi memantau USB tiap 3 detik. Canon yang dicolok/dinyalakan
  otomatis terhubung (tanpa host/port); bila dicabut lalu dicolok lagi, koneksi
  dan live view pulih sendiri. Bila tidak ada Canon, webcam dipakai otomatis.
  Halaman booth menunggu deteksi awal selesai sebelum memilih kamera.
- **API:** sinkron ke server (pengaturan, template, background frame) saat start,
  mengulang bertahap (5-60 detik) bila server belum terjangkau, lalu menyegarkan
  tiap 5 menit (ditunda saat sesi pelanggan berlangsung). Mengganti URL/token di
  halaman API memicu sinkron ulang. Status "Server online/offline" dan kamera
  tampil live di launcher (arahkan kursor ke badge untuk detail/peringatan server).

Nilai bawaan API bisa diatur per build tanpa edit kode:

    flutter run -d windows ^
      --dart-define=API_BASE_URL=https://booth.contoh.com/api ^
      --dart-define=API_TOKEN=xxxx --dart-define=BOOTH_ID=2

Catatan: Booth ID tidak bisa dideteksi otomatis (kontrak API klien tidak punya
endpoint pendaftaran booth), jadi diatur lewat `BOOTH_ID` atau halaman API.

Pengaturan (mode, lokasi DLL, folder foto, deteksi otomatis, API, kamera pilihan)
tersimpan dan dipulihkan saat aplikasi dibuka.

Mode lama tetap ada sebagai cadangan: USB Tether Bridge (`tools/canon_bridge`)
dan Wi-Fi CCAPI. Binding diuji tanpa kamera memakai EDSDK palsu
(`tools/edsdk_mock`).
