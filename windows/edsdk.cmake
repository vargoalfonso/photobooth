# Menyalin Canon EDSDK (64-bit) ke folder EDSDK di samping .exe saat build/install.
# Dicari oleh lib/services/edsdk_native.dart di: <folder exe>/EDSDK/EDSDK.dll
#
# Pasang dengan menambahkan baris ini di windows/CMakeLists.txt (setelah blok install lain):
#   include(edsdk.cmake)
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/EDSDK/"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/EDSDK"
  COMPONENT Runtime
  PATTERN "include" EXCLUDE)
