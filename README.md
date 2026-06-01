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
