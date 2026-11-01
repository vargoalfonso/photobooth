Letakkan isi folder "Dll" dari Canon EDSDK di sini:

  EDSDK.dll
  EdsImage.dll
  IconMan\   (folder)
  ... (file pendamping lain dari SDK)

Saat `flutter build windows`, isi folder ini otomatis disalin ke
<folder aplikasi>\EDSDK\ dan ditemukan aplikasi tanpa pengaturan tambahan.
Gunakan EDSDK 64-bit yang mendukung EOS R100.
File SDK jangan di-commit ke repo publik (lisensi Canon).
