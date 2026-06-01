import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../state/photo_booth_config.dart';
import '../utils/file_picker_helper.dart';

class FiltersPage extends StatefulWidget {
  const FiltersPage({
    super.key,
    required this.config,
  });

  final PhotoBoothConfig config;

  @override
  State<FiltersPage> createState() => _FiltersPageState();
}

class _FiltersPageState extends State<FiltersPage> {
  List<PlatformFile> _selectedFiles = const <PlatformFile>[];
  late List<_InstalledFilterItem> _installedFilters;

  @override
  void initState() {
    super.initState();
    _installedFilters = <_InstalledFilterItem>[
      const _InstalledFilterItem(
        id: 'green-dust',
        name: 'Green Dust.cube',
        sizeKb: 899.4,
        accentColor: Color(0xFF7CCB9A),
      ),
      const _InstalledFilterItem(
        id: 'renata',
        name: 'Renata.cube',
        sizeKb: 947.7,
        accentColor: Color(0xFF9FC4E4),
      ),
      const _InstalledFilterItem(
        id: 'sedona',
        name: 'Sedona.cube',
        sizeKb: 864.2,
        accentColor: Color(0xFFE6D18A),
      ),
    ];
  }

  Future<void> _chooseFiles() async {
    final List<PlatformFile> files = await FilePickerHelper.pickCustomFiles(
      allowedExtensions: const <String>['cube'],
      dialogTitle: 'Choose .cube filter files',
    );
    if (!mounted || files.isEmpty) {
      return;
    }

    setState(() {
      _selectedFiles = files;
    });
  }

  void _uploadFiles() {
    if (_selectedFiles.isEmpty) {
      _showMessage('Choose at least one .cube file first.');
      return;
    }

    final List<_InstalledFilterItem> newItems = _selectedFiles
        .map(
          (PlatformFile file) => _InstalledFilterItem(
            id: file.name.toLowerCase().replaceAll(' ', '-'),
            name: file.name,
            sizeKb: file.size / 1024,
            accentColor: _accentFromName(file.name),
          ),
        )
        .toList();

    setState(() {
      final Set<String> existingIds =
          _installedFilters.map((_InstalledFilterItem item) => item.id).toSet();
      _installedFilters = <_InstalledFilterItem>[
        ..._installedFilters,
        ...newItems.where(
          (_InstalledFilterItem item) => !existingIds.contains(item.id),
        ),
      ];
      _selectedFiles = const <PlatformFile>[];
    });

    _showMessage('${newItems.length} filter file(s) uploaded.');
  }

  void _refreshInstalledFilters() {
    setState(() {
      _installedFilters = List<_InstalledFilterItem>.from(_installedFilters)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });
    _showMessage('Installed filters refreshed.');
  }

  Future<void> _renameFilter(_InstalledFilterItem item) async {
    final TextEditingController controller =
        TextEditingController(text: item.name.replaceAll('.cube', ''));
    final String? newName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Rename Filter'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Filter name',
              hintText: 'Enter new name',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (!mounted || newName == null || newName.isEmpty) {
      return;
    }

    final String normalizedName =
        newName.endsWith('.cube') ? newName : '$newName.cube';
    setState(() {
      _installedFilters = _installedFilters
          .map(
            (_InstalledFilterItem current) => current.id == item.id
                ? current.copyWith(name: normalizedName)
                : current,
          )
          .toList();
    });
    _showMessage('Filter renamed to $normalizedName.');
  }

  void _deleteFilter(_InstalledFilterItem item) {
    setState(() {
      _installedFilters = _installedFilters
          .where((_InstalledFilterItem current) => current.id != item.id)
          .toList();
    });
    _showMessage('${item.name} deleted.');
  }

  Color _accentFromName(String name) {
    final int hash =
        name.codeUnits.fold<int>(0, (int sum, int code) => sum + code);
    final List<Color> palette = <Color>[
      const Color(0xFF7CCB9A),
      const Color(0xFF9FC4E4),
      const Color(0xFFE6D18A),
      const Color(0xFFD0A1E6),
      const Color(0xFF86D6D1),
    ];
    return palette[hash % palette.length];
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF1E4A73),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
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
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                  child: Column(
                    children: <Widget>[
                      Text(
                        'Photo Filters Manager',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: const Color(0xFF324E71),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _UploadPanel(
                        selectedFiles: _selectedFiles,
                        onChooseFiles: _chooseFiles,
                        onUpload: _uploadFiles,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE6EAF0)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        'Installed Filters',
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                          color: const Color(0xFF324E71),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: _refreshInstalledFilters,
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFFFFA61A),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Refresh'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: _installedFilters
                                          .map(
                                            (_InstalledFilterItem item) =>
                                                Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12),
                                              child: _InstalledFilterCard(
                                                item: item,
                                                onRename: () =>
                                                    _renameFilter(item),
                                                onDelete: () =>
                                                    _deleteFilter(item),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
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

class _UploadPanel extends StatelessWidget {
  const _UploadPanel({
    required this.selectedFiles,
    required this.onChooseFiles,
    required this.onUpload,
  });

  final List<PlatformFile> selectedFiles;
  final Future<void> Function() onChooseFiles;
  final VoidCallback onUpload;

  String get _selectionLabel {
    if (selectedFiles.isEmpty) {
      return 'No file chosen';
    }
    if (selectedFiles.length == 1) {
      return selectedFiles.first.name;
    }
    return '${selectedFiles.length} files selected';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFCF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF8DA2E2),
          width: 1.5,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFD9E0EA)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: OutlinedButton(
                          onPressed: onChooseFiles,
                          child: const Text('Choose Files'),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _selectionLabel,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFF7B8491),
                                  ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF24456E),
                  foregroundColor: const Color(0xFFF1D065),
                  minimumSize: const Size(96, 42),
                ),
                onPressed: onUpload,
                child: const Text('Upload'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Select one or more .cube files to upload. They will be saved to /static/filters/.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8A8F99),
                ),
          ),
        ],
      ),
    );
  }
}

class _InstalledFilterItem {
  const _InstalledFilterItem({
    required this.id,
    required this.name,
    required this.sizeKb,
    required this.accentColor,
  });

  final String id;
  final String name;
  final double sizeKb;
  final Color accentColor;

  _InstalledFilterItem copyWith({
    String? name,
  }) {
    return _InstalledFilterItem(
      id: id,
      name: name ?? this.name,
      sizeKb: sizeKb,
      accentColor: accentColor,
    );
  }
}

class _InstalledFilterCard extends StatelessWidget {
  const _InstalledFilterCard({
    required this.item,
    required this.onRename,
    required this.onDelete,
  });

  final _InstalledFilterItem item;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EBF0)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: <Color>[
                  item.accentColor.withValues(alpha: 0.92),
                  item.accentColor.withValues(alpha: 0.45),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.face_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF324E71),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.sizeKb.toStringAsFixed(1)} KB',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF8A8F99),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFA61A),
              foregroundColor: Colors.white,
            ),
            onPressed: onRename,
            child: const Text('Rename'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE64E4E),
              foregroundColor: Colors.white,
            ),
            onPressed: onDelete,
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
