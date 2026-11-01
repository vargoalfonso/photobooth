@echo off
REM Jalankan bridge Canon. Ubah path DLL sesuai lokasi EDSDK Anda.
REM Folder tempat EDSDK.dll harus juga berisi EdsImage.dll dan folder IconMan.
set EDSDK_DLL=%~dp0EDSDK\EDSDK.dll
python "%~dp0canon_bridge.py" --host 127.0.0.1 --port 5513
pause
