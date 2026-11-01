# EDSDK palsu untuk uji binding

`mock_edsdk.c` meniru *bentuk* API EDSDK (bukan perilaku kamera asli) agar
`lib/services/edsdk_native.dart` dan `CanonCameraService` bisa diuji di Linux/CI
tanpa kamera atau SDK Canon.

    gcc -shared -fPIC -o /tmp/libmock_edsdk.so mock_edsdk.c

Skrip di `tests/` dijalankan dengan paket Dart kecil yang meng-import file
`lib/services/*` (butuh stub `flutter`/`shared_preferences` bila dijalankan di
luar proyek Flutter). Env: `MOCK_NO_CAMERA=1`, `MOCK_BUSY=n`.

Uji ini membuktikan mekanisme FFI (callback, struct by value, stream memori,
alur capture) benar, bukan bahwa konstanta/struct cocok dengan EDSDK Canon asli.

Skrip uji Dart (`ffi_wrapper_test`, `service_test`, `auto_setup_test`) sengaja
TIDAK ada di proyek ini karena mereka meng-import paket uji terpisah dan akan
menimbulkan error di analyzer Flutter. Lihat `edsdk-tests.zip` yang diberikan
terpisah. Hook `mock_set_present(0/1)` di `mock_edsdk.c` meniru kabel
dicabut/dicolok.
