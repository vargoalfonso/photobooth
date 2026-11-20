import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Cetak langsung ke printer Windows (mis. DNP DS-RX1HS) tanpa dialog.
///
/// Alur: PNG strip hasil [RenderRepaintBoundary.toImage] -> dibungkus jadi
/// PDF 4x6 inci -> `Printing.directPrintPdf` ke antrean printer.
///
/// Ukuran kertas yang dipakai printer ditentukan oleh *Printing Preferences*
/// driver DNP (mis. "4x6" atau "4x6 (2inch cut)"). Atur sekali di Windows:
/// Settings > Printers > DS-RX1HS > Printing preferences.
class LocalPrinterService {
  const LocalPrinterService._();

  static bool get supported => !kIsWeb && Platform.isWindows;

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Nama semua printer yang terpasang di Windows.
  static Future<List<String>> listPrinterNames() async {
    if (!supported) return <String>[];
    try {
      final List<Printer> printers = await Printing.listPrinters();
      return <String>[for (final Printer p in printers) p.name];
    } catch (e) {
      debugPrint('Gagal membaca daftar printer: $e');
      return <String>[];
    }
  }

  /// Cari printer: nama persis -> nama mirip -> printer apa pun "DS-RX1".
  static Future<Printer?> resolve(String wanted) async {
    final List<Printer> printers = await Printing.listPrinters();
    if (printers.isEmpty) return null;

    for (final Printer p in printers) {
      if (p.name == wanted) return p;
    }
    final String w = _norm(wanted);
    for (final Printer p in printers) {
      final String n = _norm(p.name);
      if (w.isNotEmpty && (n.contains(w) || w.contains(n))) return p;
    }
    for (final Printer p in printers) {
      if (_norm(p.name).contains('dsrx1')) return p;
    }
    return null;
  }

  /// Cetak [png] satu lembar penuh. [scalePercent] 100 = penuh satu kertas;
  /// lebih kecil = ada pinggiran putih. [offsetX]/[offsetY] dalam 0,1 mm.
  static Future<void> printPng({
    required Uint8List png,
    required String printerName,
    double scalePercent = 100,
    double offsetX = 0,
    double offsetY = 0,
    String jobName = 'Photobooth',
    bool usePrinterSettings = true,
  }) async {
    if (!supported) {
      throw UnsupportedError('Cetak langsung hanya tersedia di Windows.');
    }
    final Printer? printer = await resolve(printerName);
    if (printer == null) {
      throw StateError(
          'Printer "$printerName" tidak ditemukan. Pastikan driver DNP '
          'terpasang dan printer menyala.');
    }

    final ui.Codec codec = await ui.instantiateImageCodec(png);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final double imgW = frame.image.width.toDouble();
    final double imgH = frame.image.height.toDouble();
    frame.image.dispose();
    codec.dispose();

    // Kertas 4R (4x6 inci); orientasi mengikuti gambar.
    final bool landscape = imgW > imgH;
    final PdfPageFormat format = PdfPageFormat(
      (landscape ? 6 : 4) * PdfPageFormat.inch,
      (landscape ? 4 : 6) * PdfPageFormat.inch,
      marginAll: 0,
    );

    // "Contain" ke kertas lalu skala + geser.
    final double fit = (format.width / imgW) < (format.height / imgH)
        ? format.width / imgW
        : format.height / imgH;
    final double k = fit * (scalePercent.clamp(10, 100) / 100);
    final double w = imgW * k;
    final double h = imgH * k;
    const double mm = PdfPageFormat.mm;
    final double x = (format.width - w) / 2 + offsetX * 0.1 * mm;
    final double y = (format.height - h) / 2 + offsetY * 0.1 * mm;

    final pw.Document doc = pw.Document();
    final pw.MemoryImage image = pw.MemoryImage(png);
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context ctx) => pw.Stack(
          children: <pw.Widget>[
            pw.Positioned(
              left: x,
              top: y,
              child: pw.Image(image,
                  width: w, height: h, fit: pw.BoxFit.fill),
            ),
          ],
        ),
      ),
    );
    final Uint8List bytes = await doc.save();

    final bool ok = await Printing.directPrintPdf(
      printer: printer,
      onLayout: (PdfPageFormat _) async => bytes,
      name: jobName,
      format: format,
      usePrinterSettings: usePrinterSettings,
    );
    if (!ok) {
      throw StateError('Printer "${printer.name}" menolak pekerjaan cetak.');
    }
  }

  /// Halaman uji (bingkai + teks) untuk memeriksa posisi & koneksi printer.
  static Future<void> printTestPage(String printerName) async {
    if (!supported) {
      throw UnsupportedError('Cetak langsung hanya tersedia di Windows.');
    }
    final Printer? printer = await resolve(printerName);
    if (printer == null) {
      throw StateError('Printer "$printerName" tidak ditemukan.');
    }
    final PdfPageFormat format = PdfPageFormat(
      4 * PdfPageFormat.inch,
      6 * PdfPageFormat.inch,
      marginAll: 0,
    );
    final pw.Document doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context ctx) => pw.Container(
          margin: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 2),
          ),
          alignment: pw.Alignment.center,
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: <pw.Widget>[
              pw.Text('TEST PRINT',
                  style: pw.TextStyle(
                      fontSize: 28, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text(printer.name, style: const pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 4),
              pw.Text('4 x 6 inch', style: const pw.TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
    final Uint8List bytes = await doc.save();
    final bool ok = await Printing.directPrintPdf(
      printer: printer,
      onLayout: (PdfPageFormat _) async => bytes,
      name: 'Photobooth test',
      format: format,
      usePrinterSettings: true,
    );
    if (!ok) {
      throw StateError('Printer "${printer.name}" menolak pekerjaan cetak.');
    }
  }
}
