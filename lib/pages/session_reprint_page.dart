import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../state/photo_booth_config.dart';
import '../utils/file_picker_helper.dart';

class SessionReprintPage extends StatefulWidget {
  const SessionReprintPage({
    super.key,
    required this.config,
  });

  final PhotoBoothConfig config;

  @override
  State<SessionReprintPage> createState() => _SessionReprintPageState();
}

class _SessionReprintPageState extends State<SessionReprintPage> {
  List<PlatformFile> _files = const <PlatformFile>[];
  bool _isPicking = false;

  Future<void> _pickFiles() async {
    setState(() {
      _isPicking = true;
    });

    try {
      final List<PlatformFile> files = await FilePickerHelper.pickMediaFiles(
        dialogTitle: 'Choose session prints',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _files = files;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _openPreview(PlatformFile file) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          file.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F5F8),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: _PreviewImage(file: file),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _printFile(PlatformFile file) {
    if (widget.config.disableAllPrinting || !widget.config.enablePrintButton) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Printing sedang nonaktif di pengaturan booth.'),
        ),
      );
      return;
    }

    final String message = widget.config.enableReprintLogging
        ? 'Reprint ${file.name} dikirim ke ${widget.config.primaryPrinter} dan dicatat.'
        : 'Reprint ${file.name} dikirim ke ${widget.config.primaryPrinter}.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E4A73),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F0D8),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 28,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              children: <Widget>[
                                Text(
                                  'Session Re-Print',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: const Color(0xFF324E71),
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Pilih hasil sesi sebelumnya lalu cetak ulang dari daftar ini.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: const Color(0xFF8A8F99)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close),
                            color: const Color(0xFF324E71),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: _isPicking ? null : _pickFiles,
                            icon: const Icon(Icons.folder_open),
                            label: Text(_files.isEmpty ? 'Choose Files' : 'Replace Files'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.tonalIcon(
                            onPressed: _isPicking ? null : _pickFiles,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: _files.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        const Icon(
                                          Icons.print_outlined,
                                          size: 54,
                                          color: Color(0xFF9BA3AE),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Belum ada file sesi yang dipilih',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: const Color(0xFF324E71),
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Gunakan Choose Files untuk mengambil JPG, PNG, atau WEBP hasil cetak sebelumnya.',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: const Color(0xFF8A8F99),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : GridView.builder(
                                  padding: const EdgeInsets.all(18),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    childAspectRatio: 0.82,
                                  ),
                                  itemCount: _files.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final PlatformFile file = _files[index];
                                    return _ReprintCard(
                                      file: file,
                                      fileSizeLabel: _formatFileSize(file.size),
                                      onPreview: () => _openPreview(file),
                                      onPrint: () => _printFile(file),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReprintCard extends StatelessWidget {
  const _ReprintCard({
    required this.file,
    required this.fileSizeLabel,
    required this.onPreview,
    required this.onPrint,
  });

  final PlatformFile file;
  final String fileSizeLabel;
  final VoidCallback onPreview;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9EDF2)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF4F6F8),
                        ),
                        child: _PreviewImage(file: file),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: InkWell(
                      onTap: onPreview,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xAA000000),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Click to preview',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF324E71),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ukuran: $fileSizeLabel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A8F99),
                  ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF24456E),
                  foregroundColor: const Color(0xFFF1D065),
                ),
                onPressed: onPrint,
                child: const Text('Print'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.file});

  final PlatformFile file;

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      return const Icon(
        Icons.image_not_supported_outlined,
        size: 48,
        color: Color(0xFF98A1AE),
      );
    }

    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        return const Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: Color(0xFF98A1AE),
        );
      },
    );
  }
}
