import 'package:flutter/material.dart';

import '../models/booth_models.dart';
import '../state/photo_booth_config.dart';

class FramesPage extends StatefulWidget {
  const FramesPage({
    super.key,
    required this.config,
  });

  final PhotoBoothConfig config;

  @override
  State<FramesPage> createState() => _FramesPageState();
}

class _FramesPageState extends State<FramesPage> {
  late List<_FrameManagerItem> _localFrames;
  late List<_FrameManagerItem> _cloudFrames;

  @override
  void initState() {
    super.initState();
    _localFrames = <_FrameManagerItem>[
      _FrameManagerItem.fromOption(
        kFrameOptions[0],
        sizeMb: 0.22,
        modifiedAt: DateTime(2026, 4, 4, 8, 45),
        tags: const <String>['All', '2R', 'primary'],
        isActive: widget.config.frame.id == kFrameOptions[0].id,
      ),
      _FrameManagerItem.fromOption(
        kFrameOptions[1],
        sizeMb: 0.20,
        modifiedAt: DateTime(2026, 4, 4, 8, 45),
        tags: const <String>['All', 'Normal', 'primary'],
        isActive: widget.config.frame.id == kFrameOptions[1].id,
      ),
      _FrameManagerItem.fromOption(
        kFrameOptions[2],
        sizeMb: 0.20,
        modifiedAt: DateTime(2026, 4, 4, 8, 45),
        tags: const <String>['All', '2R', 'primary'],
        isActive: widget.config.frame.id == kFrameOptions[2].id,
      ),
    ];

    _cloudFrames = <_FrameManagerItem>[
      _FrameManagerItem.fromOption(
        kFrameOptions[3],
        sizeMb: 0.20,
        modifiedAt: DateTime(2026, 4, 4, 15, 43),
        tags: const <String>['All', 'Normal', 'primary'],
      ),
      _FrameManagerItem.fromOption(
        kFrameOptions[2],
        sizeMb: 0.20,
        modifiedAt: DateTime(2026, 3, 23, 0, 55),
        tags: const <String>['All', '2R', 'primary'],
      ),
      _FrameManagerItem.fromOption(
        kFrameOptions[0],
        sizeMb: 0.22,
        modifiedAt: DateTime(2026, 3, 23, 0, 30),
        tags: const <String>['All', '2R', 'primary'],
      ),
    ];
  }

  void _refreshLocalFrames() {
    setState(() {
      _localFrames = List<_FrameManagerItem>.from(_localFrames)
        ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    });
    _showMessage('Local frames refreshed.');
  }

  void _refreshCloudFrames() {
    setState(() {
      _cloudFrames = List<_FrameManagerItem>.from(_cloudFrames)
        ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    });
    _showMessage('Cloud frames refreshed.');
  }

  void _toggleSelected(String id, bool value) {
    setState(() {
      _localFrames = _localFrames
          .map((_FrameManagerItem item) =>
              item.id == id ? item.copyWith(isSelected: value) : item)
          .toList();
    });
  }

  void _setActive(String id, bool value) {
    final _FrameManagerItem? selectedItem =
        _localFrames.cast<_FrameManagerItem?>().firstWhere(
              (_FrameManagerItem? item) => item?.id == id,
              orElse: () => null,
            );
    if (selectedItem == null) {
      return;
    }

    if (value) {
      final BoothFrameOption frame = kFrameOptions.firstWhere(
        (BoothFrameOption option) => option.id == id,
        orElse: () => widget.config.frame,
      );
      widget.config.setFrame(frame);
    }

    setState(() {
      _localFrames = _localFrames
          .map((_FrameManagerItem item) => item.copyWith(
                isActive: value ? item.id == id : false,
              ))
          .toList();
    });

    _showMessage(value
        ? '${selectedItem.name} marked as active frame.'
        : '${selectedItem.name} is no longer active.');
  }

  void _syncFrame(String id) {
    final _FrameManagerItem? cloudItem =
        _cloudFrames.cast<_FrameManagerItem?>().firstWhere(
              (_FrameManagerItem? item) => item?.id == id,
              orElse: () => null,
            );
    if (cloudItem == null) {
      return;
    }

    final bool exists =
        _localFrames.any((_FrameManagerItem item) => item.id == id);
    if (!exists) {
      setState(() {
        _localFrames = <_FrameManagerItem>[
          cloudItem.copyWith(isSelected: false),
          ..._localFrames
        ];
      });
    }

    _showMessage('${cloudItem.name} synced to local frames.');
  }

  void _syncAllFrames() {
    setState(() {
      final Set<String> localIds =
          _localFrames.map((_FrameManagerItem item) => item.id).toSet();
      final List<_FrameManagerItem> missing = _cloudFrames
          .where((_FrameManagerItem item) => !localIds.contains(item.id))
          .map((_FrameManagerItem item) => item.copyWith(isSelected: false))
          .toList();
      _localFrames = <_FrameManagerItem>[..._localFrames, ...missing];
    });
    _showMessage('All cloud frames synced.');
  }

  void _deleteSelectedLocalFrames() {
    final int selectedCount =
        _localFrames.where((_FrameManagerItem item) => item.isSelected).length;
    if (selectedCount == 0) {
      _showMessage('Select at least one local frame to delete.');
      return;
    }

    setState(() {
      _localFrames = _localFrames
          .where((_FrameManagerItem item) => !item.isSelected)
          .toList();
    });
    _showMessage('$selectedCount local frame(s) deleted.');
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
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Column(
                    children: <Widget>[
                      Text(
                        'Frames Manager',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: const Color(0xFF324E71),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (BuildContext context,
                              BoxConstraints constraints) {
                            final bool stacked = constraints.maxWidth < 940;
                            final List<Widget> panels = <Widget>[
                              Expanded(
                                child: _FramePanel(
                                  title: 'Local Frames',
                                  subtitle:
                                      'Found ${_localFrames.length} local frames',
                                  subtitleColor: const Color(0xFF5DBF74),
                                  actionLabel: 'Refresh',
                                  onActionPressed: _refreshLocalFrames,
                                  footer: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFE64E4E),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: _deleteSelectedLocalFrames,
                                    child: const Text('Delete All Local Files'),
                                  ),
                                  children: _localFrames
                                      .map(
                                        (_FrameManagerItem item) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: _LocalFrameCard(
                                            item: item,
                                            onSelected: (bool value) =>
                                                _toggleSelected(item.id, value),
                                            onActiveChanged: (bool value) =>
                                                _setActive(item.id, value),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                              SizedBox(
                                  width: stacked ? 0 : 18,
                                  height: stacked ? 18 : 0),
                              Expanded(
                                child: _FramePanel(
                                  title: 'Cloud Frames',
                                  subtitle:
                                      'Found ${_cloudFrames.length} frames available for sync',
                                  subtitleColor: const Color(0xFF5DBF74),
                                  actionLabel: 'Refresh',
                                  onActionPressed: _refreshCloudFrames,
                                  footer: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF24456E),
                                      foregroundColor: const Color(0xFFF1D065),
                                    ),
                                    onPressed: _syncAllFrames,
                                    child: const Text('Sync All'),
                                  ),
                                  children: _cloudFrames
                                      .map(
                                        (_FrameManagerItem item) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: _CloudFrameCard(
                                            item: item,
                                            onSync: () => _syncFrame(item.id),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ];

                            return stacked
                                ? Column(children: panels)
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: panels);
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
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

class _FrameManagerItem {
  const _FrameManagerItem({
    required this.id,
    required this.name,
    required this.description,
    required this.gradient,
    required this.borderColor,
    required this.sizeMb,
    required this.modifiedAt,
    required this.tags,
    this.isSelected = false,
    this.isActive = false,
  });

  factory _FrameManagerItem.fromOption(
    BoothFrameOption option, {
    required double sizeMb,
    required DateTime modifiedAt,
    required List<String> tags,
    bool isSelected = false,
    bool isActive = false,
  }) {
    return _FrameManagerItem(
      id: option.id,
      name: option.name,
      description: option.description,
      gradient: option.gradient,
      borderColor: option.borderColor,
      sizeMb: sizeMb,
      modifiedAt: modifiedAt,
      tags: tags,
      isSelected: isSelected,
      isActive: isActive,
    );
  }

  final String id;
  final String name;
  final String description;
  final List<Color> gradient;
  final Color borderColor;
  final double sizeMb;
  final DateTime modifiedAt;
  final List<String> tags;
  final bool isSelected;
  final bool isActive;

  _FrameManagerItem copyWith({
    bool? isSelected,
    bool? isActive,
  }) {
    return _FrameManagerItem(
      id: id,
      name: name,
      description: description,
      gradient: gradient,
      borderColor: borderColor,
      sizeMb: sizeMb,
      modifiedAt: modifiedAt,
      tags: tags,
      isSelected: isSelected ?? this.isSelected,
      isActive: isActive ?? this.isActive,
    );
  }
}

class _FramePanel extends StatelessWidget {
  const _FramePanel({
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    required this.actionLabel,
    required this.onActionPressed,
    required this.children,
    required this.footer,
  });

  final String title;
  final String subtitle;
  final Color subtitleColor;
  final String actionLabel;
  final VoidCallback onActionPressed;
  final List<Widget> children;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFF324E71),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: onActionPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFA61A),
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: subtitleColor,
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                child: Column(children: children),
              ),
            ),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: footer),
          ],
        ),
      ),
    );
  }
}

class _LocalFrameCard extends StatelessWidget {
  const _LocalFrameCard({
    required this.item,
    required this.onSelected,
    required this.onActiveChanged,
  });

  final _FrameManagerItem item;
  final ValueChanged<bool> onSelected;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EBF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Checkbox(
              value: item.isSelected,
              onChanged: (bool? value) => onSelected(value ?? false),
            ),
            _FrameThumbnail(item: item),
            const SizedBox(width: 12),
            Expanded(child: _FrameMeta(item: item)),
            Column(
              children: <Widget>[
                Switch(
                  value: item.isActive,
                  onChanged: onActiveChanged,
                  activeColor: const Color(0xFF56C271),
                ),
                Text(
                  item.isActive ? 'Active' : 'Inactive',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: item.isActive
                            ? const Color(0xFF56C271)
                            : const Color(0xFF98A1AE),
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudFrameCard extends StatelessWidget {
  const _CloudFrameCard({
    required this.item,
    required this.onSync,
  });

  final _FrameManagerItem item;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EBF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            _FrameThumbnail(item: item),
            const SizedBox(width: 12),
            Expanded(child: _FrameMeta(item: item, showDescription: false)),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF24456E),
                foregroundColor: const Color(0xFFF1D065),
              ),
              onPressed: onSync,
              child: const Text('Sync'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameThumbnail extends StatelessWidget {
  const _FrameThumbnail({required this.item});

  final _FrameManagerItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE7EBF0)),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: item.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: item.borderColor, width: 3),
        ),
        child: Center(
          child: Icon(
            Icons.crop_portrait,
            color: item.borderColor.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

class _FrameMeta extends StatelessWidget {
  const _FrameMeta({
    required this.item,
    this.showDescription = true,
  });

  final _FrameManagerItem item;
  final bool showDescription;

  String _formatDate(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          item.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF324E71),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Size: ${item.sizeMb.toStringAsFixed(2)} MB',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8A8F99),
              ),
        ),
        Text(
          'Modified: ${_formatDate(item.modifiedAt)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8A8F99),
              ),
        ),
        if (showDescription) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            item.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF7B8491),
                ),
          ),
        ],
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children:
              item.tags.map((String tag) => _TagChip(label: tag)).toList(),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor;
    switch (label.toLowerCase()) {
      case '2r':
        backgroundColor = const Color(0xFF7B7BFF);
        break;
      case 'normal':
        backgroundColor = const Color(0xFFB28DFF);
        break;
      case 'primary':
        backgroundColor = const Color(0xFF31C48D);
        break;
      default:
        backgroundColor = const Color(0xFF9CA3FF);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
