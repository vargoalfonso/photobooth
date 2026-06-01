import 'package:flutter/material.dart';

import '../state/photo_booth_config.dart';

class UploadsPage extends StatefulWidget {
  const UploadsPage({
    super.key,
    required this.config,
  });

  final PhotoBoothConfig config;

  @override
  State<UploadsPage> createState() => _UploadsPageState();
}

class _UploadsPageState extends State<UploadsPage> {
  late List<_UploadSessionGroup> _groups;

  @override
  void initState() {
    super.initState();
    _groups = <_UploadSessionGroup>[
      _UploadSessionGroup(
        title: '2026-04-04',
        sessions: <_UploadSessionItem>[
          _UploadSessionItem(
            id: '20260404082651',
            time: '08:26:51',
            fileSummary:
                'Files: 9 (Photos, Photostrip, Animation, Moving Strip)',
            status: _UploadStatus.uploaded,
            previewColor: const Color(0xFFD9DDE3),
            lengthLabel: '00:13',
          ),
          _UploadSessionItem(
            id: '20260404081912',
            time: '08:19:12',
            fileSummary: 'Files: 8 (Photos, Photostrip, Animation)',
            status: _UploadStatus.failed,
            previewColor: const Color(0xFFCFC4B2),
            lengthLabel: '00:10',
          ),
          _UploadSessionItem(
            id: '20260404080205',
            time: '08:02:05',
            fileSummary:
                'Files: 9 (Photos, Photostrip, Animation, Moving Strip)',
            status: _UploadStatus.pending,
            previewColor: const Color(0xFFBFD3E6),
            lengthLabel: '00:14',
          ),
        ],
      ),
      _UploadSessionGroup(
        title: '2026-03-22',
        sessions: <_UploadSessionItem>[
          _UploadSessionItem(
            id: '20260322175619',
            time: '17:56:19',
            fileSummary:
                'Files: 9 (Photos, Photostrip, Animation, Moving Strip)',
            status: _UploadStatus.uploaded,
            previewColor: const Color(0xFFE0D4C0),
            lengthLabel: '00:18',
          ),
          _UploadSessionItem(
            id: '20260322173045',
            time: '17:30:45',
            fileSummary:
                'Files: 9 (Photos, Photostrip, Animation, Moving Strip)',
            status: _UploadStatus.uploaded,
            previewColor: const Color(0xFFDECBC1),
            lengthLabel: '00:14',
          ),
          _UploadSessionItem(
            id: '20260322170944',
            time: '17:09:44',
            fileSummary: 'Files: 7 (Photos, Photostrip)',
            status: _UploadStatus.failed,
            previewColor: const Color(0xFFD2D2D2),
            lengthLabel: '00:11',
          ),
          _UploadSessionItem(
            id: '20260322165510',
            time: '16:55:10',
            fileSummary: 'Files: 6 (Photos, Photostrip)',
            status: _UploadStatus.pending,
            previewColor: const Color(0xFFCED8E8),
            lengthLabel: '00:09',
          ),
        ],
      ),
      _UploadSessionGroup(
        title: '2026-03-19',
        sessions: <_UploadSessionItem>[
          _UploadSessionItem(
            id: '20260319162201',
            time: '16:22:01',
            fileSummary:
                'Files: 9 (Photos, Photostrip, Animation, Moving Strip)',
            status: _UploadStatus.uploaded,
            previewColor: const Color(0xFFCACACA),
            lengthLabel: '00:15',
          ),
          _UploadSessionItem(
            id: '20260319160240',
            time: '16:02:40',
            fileSummary:
                'Files: 9 (Photos, Photostrip, Animation, Moving Strip)',
            status: _UploadStatus.failed,
            previewColor: const Color(0xFFDDD5C5),
            lengthLabel: '00:17',
          ),
          _UploadSessionItem(
            id: '20260319154112',
            time: '15:41:12',
            fileSummary: 'Files: 5 (Photos, Photostrip)',
            status: _UploadStatus.pending,
            previewColor: const Color(0xFFD6E1E3),
            lengthLabel: '00:08',
          ),
          _UploadSessionItem(
            id: '20260319151233',
            time: '15:12:33',
            fileSummary: 'Files: 8 (Photos, Photostrip, Animation)',
            status: _UploadStatus.failed,
            previewColor: const Color(0xFFE1D2D2),
            lengthLabel: '00:10',
          ),
        ],
      ),
    ];
  }

  int get _totalSessions => _groups.fold<int>(
      0, (int sum, _UploadSessionGroup group) => sum + group.sessions.length);

  int get _failedCount => _groups
      .expand((_UploadSessionGroup group) => group.sessions)
      .where((_UploadSessionItem item) => item.status == _UploadStatus.failed)
      .length;

  int get _selectedCount => _groups
      .expand((_UploadSessionGroup group) => group.sessions)
      .where((_UploadSessionItem item) => item.isSelected)
      .length;

  void _refreshSessions() {
    setState(() {
      _groups = List<_UploadSessionGroup>.from(_groups);
    });
    _showMessage('Upload sessions refreshed.');
  }

  void _openLocalFiles() {
    _showMessage('Local files browser can be connected next.');
  }

  void _retryFailedSessions() {
    final int failed = _failedCount;
    if (failed == 0) {
      _showMessage('No failed sessions to retry.');
      return;
    }

    setState(() {
      _groups = _groups
          .map(
            (_UploadSessionGroup group) => group.copyWith(
              sessions: group.sessions
                  .map(
                    (_UploadSessionItem item) =>
                        item.status == _UploadStatus.failed
                            ? item.copyWith(status: _UploadStatus.uploaded)
                            : item,
                  )
                  .toList(),
            ),
          )
          .toList();
    });
    _showMessage('$failed failed session(s) retried successfully.');
  }

  void _uploadSelected() {
    if (_selectedCount == 0) {
      _showMessage('Select at least one session to upload.');
      return;
    }

    setState(() {
      _groups = _groups
          .map(
            (_UploadSessionGroup group) => group.copyWith(
              sessions: group.sessions
                  .map(
                    (_UploadSessionItem item) => item.isSelected
                        ? item.copyWith(
                            status: _UploadStatus.uploaded,
                            isSelected: false,
                          )
                        : item,
                  )
                  .toList(),
            ),
          )
          .toList();
    });
    _showMessage('Selected sessions uploaded.');
  }

  void _toggleSelected(String id, bool value) {
    setState(() {
      _groups = _groups
          .map(
            (_UploadSessionGroup group) => group.copyWith(
              sessions: group.sessions
                  .map(
                    (_UploadSessionItem item) =>
                        item.id == id ? item.copyWith(isSelected: value) : item,
                  )
                  .toList(),
            ),
          )
          .toList();
    });
  }

  void _sendToEmail(_UploadSessionItem item) {
    _showMessage('Session ${item.id} queued for email delivery.');
  }

  void _previewSession(_UploadSessionItem item) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Session ${item.id}'),
          content: Text(
              'Preview for session at ${item.time} with status ${item.status.label}.'),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
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
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                  child: Column(
                    children: <Widget>[
                      Text(
                        'Uploads Management',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: const Color(0xFF324E71),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'List all sessions with their upload status. Select sessions and upload them again when needed.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF8A8F99),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          FilledButton.tonalIcon(
                            onPressed: _openLocalFiles,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFA61A),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Local Files'),
                          ),
                          FilledButton.tonal(
                            onPressed: _retryFailedSessions,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFA61A),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(
                                'Retry Uploads for All Failed Session ($_failedCount)'),
                          ),
                          FilledButton.tonal(
                            onPressed: _refreshSessions,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFA61A),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Refresh'),
                          ),
                          FilledButton(
                            onPressed: _uploadSelected,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF24456E),
                              foregroundColor: const Color(0xFFF1D065),
                            ),
                            child: Text(
                                'Upload Selected${_selectedCount > 0 ? ' ($_selectedCount)' : ''}'),
                          ),
                        ],
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
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: <Widget>[
                                Text(
                                  'Total: $_totalSessions sessions found',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFF63B86A),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: _groups
                                          .map(
                                            (_UploadSessionGroup group) =>
                                                Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 18),
                                              child: _UploadGroupSection(
                                                group: group,
                                                onToggleSelected:
                                                    _toggleSelected,
                                                onSendToEmail: _sendToEmail,
                                                onPreview: _previewSession,
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

class _UploadGroupSection extends StatelessWidget {
  const _UploadGroupSection({
    required this.group,
    required this.onToggleSelected,
    required this.onSendToEmail,
    required this.onPreview,
  });

  final _UploadSessionGroup group;
  final void Function(String id, bool value) onToggleSelected;
  final void Function(_UploadSessionItem item) onSendToEmail;
  final void Function(_UploadSessionItem item) onPreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${group.title} (${group.sessions.length} sessions)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF324E71),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: group.sessions
              .map(
                (_UploadSessionItem item) => SizedBox(
                  width: 272,
                  child: _UploadSessionCard(
                    item: item,
                    onToggleSelected: (bool value) =>
                        onToggleSelected(item.id, value),
                    onSendToEmail: () => onSendToEmail(item),
                    onPreview: () => onPreview(item),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _UploadSessionCard extends StatelessWidget {
  const _UploadSessionCard({
    required this.item,
    required this.onToggleSelected,
    required this.onSendToEmail,
    required this.onPreview,
  });

  final _UploadSessionItem item;
  final ValueChanged<bool> onToggleSelected;
  final VoidCallback onSendToEmail;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPreview,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE7EBF0)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Checkbox(
                  value: item.isSelected,
                  onChanged: (bool? value) => onToggleSelected(value ?? false),
                ),
                const Spacer(),
              ],
            ),
            Container(
              height: 156,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                children: <Widget>[
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _MiniStrip(color: item.previewColor),
                        const SizedBox(width: 10),
                        _MiniStrip(
                          color: item.previewColor.withValues(alpha: 0.82),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xAAFFFFFF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.lengthLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF6A7380),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.id,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF324E71),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                _StatusChip(status: item.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Time: ${item.time}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6A7380),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              item.fileSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A8F99),
                  ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: onSendToEmail,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF88C0E6),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.email_outlined, size: 16),
                label: const Text('Send to Email'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Click to view photostrip',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFA0A8B2),
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStrip extends StatelessWidget {
  const _MiniStrip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 96,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Expanded(child: _MiniPhoto(color: color)),
          const SizedBox(height: 3),
          Expanded(child: _MiniPhoto(color: color.withValues(alpha: 0.88))),
          const SizedBox(height: 3),
          Expanded(child: _MiniPhoto(color: color.withValues(alpha: 0.76))),
        ],
      ),
    );
  }
}

class _MiniPhoto extends StatelessWidget {
  const _MiniPhoto({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
      child: const Center(
        child: Icon(
          Icons.person,
          size: 11,
          color: Colors.white70,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _UploadStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(status.icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

enum _UploadStatus {
  uploaded('Uploaded', Color(0xFF63C16E), Icons.check),
  failed('Failed', Color(0xFFE55A5A), Icons.error_outline),
  pending('Pending', Color(0xFFF0AD32), Icons.schedule);

  const _UploadStatus(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;
}

class _UploadSessionItem {
  const _UploadSessionItem({
    required this.id,
    required this.time,
    required this.fileSummary,
    required this.status,
    required this.previewColor,
    required this.lengthLabel,
    this.isSelected = false,
  });

  final String id;
  final String time;
  final String fileSummary;
  final _UploadStatus status;
  final Color previewColor;
  final String lengthLabel;
  final bool isSelected;

  _UploadSessionItem copyWith({
    _UploadStatus? status,
    bool? isSelected,
  }) {
    return _UploadSessionItem(
      id: id,
      time: time,
      fileSummary: fileSummary,
      status: status ?? this.status,
      previewColor: previewColor,
      lengthLabel: lengthLabel,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class _UploadSessionGroup {
  const _UploadSessionGroup({
    required this.title,
    required this.sessions,
  });

  final String title;
  final List<_UploadSessionItem> sessions;

  _UploadSessionGroup copyWith({
    List<_UploadSessionItem>? sessions,
  }) {
    return _UploadSessionGroup(
      title: title,
      sessions: sessions ?? this.sessions,
    );
  }
}
