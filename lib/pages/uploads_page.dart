import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/monolith_api_client.dart';
import '../services/photobooth_api_service.dart';
import '../state/photo_booth_config.dart';

/// Halaman "Uploads" — sekarang tersambung langsung ke API monolith.
/// Menampilkan daftar photo sessions yang sudah tersimpan di server dan
/// menyediakan aksi refresh, print+email, dan delete.
class UploadsPage extends StatefulWidget {
  const UploadsPage({super.key, required this.config});

  final PhotoBoothConfig config;

  @override
  State<UploadsPage> createState() => _UploadsPageState();
}

class _UploadsPageState extends State<UploadsPage> {
  bool _loading = false;
  String? _error;
  PhotoSessionPage? _page;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _reload(showLoader: true));
  }

  PhotoboothApiService? _service() =>
      PhotoboothApiService.fromConfig(widget.config);

  Future<void> _reload({bool showLoader = false}) async {
    final PhotoboothApiService? svc = _service();
    if (svc == null) {
      setState(() {
        _error = 'API belum aktif. Buka "API Monolith" untuk mengatur base URL.';
        _page = null;
      });
      return;
    }
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final PhotoSessionPage data = await svc.listSessions();
      if (!mounted) return;
      setState(() {
        _page = data;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      svc.close();
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _delete(PhotoSessionDto s) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Hapus sesi?'),
        content: Text(
            'Sesi ${s.sessionCode} dan seluruh medianya akan dihapus dari server.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;

    final PhotoboothApiService? svc = _service();
    if (svc == null) return;
    try {
      await svc.deleteSession(s.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sesi ${s.sessionCode} dihapus.')),
      );
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal hapus: ${e.message}')));
    } finally {
      svc.close();
    }
  }

  Future<void> _printAndEmail(PhotoSessionDto s) async {
    final TextEditingController ctrl =
        TextEditingController(text: s.email ?? '');
    final String? email = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Kirim ke email'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Alamat email',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Kirim')),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;

    final PhotoboothApiService? svc = _service();
    if (svc == null) return;
    try {
      final PrintResult r =
          await svc.printSession(sessionId: s.id, email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.message)));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal print: ${e.message}')));
    } finally {
      svc.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uploads (Monolith)'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Konfigurasi API',
            onPressed: () =>
                Navigator.of(context).pushNamed('/api-settings'),
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _reload(showLoader: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/api-settings'),
              icon: const Icon(Icons.tune),
              label: const Text('Buka API Settings'),
            ),
          ],
        ),
      );
    }

    final PhotoSessionPage? p = _page;
    if (p == null || p.data.isEmpty) {
      return const Center(
        child: Text('Belum ada sesi tersimpan di server.'),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: p.data.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Text(
              'Total ${p.total} sesi • halaman ${p.currentPage}/${p.lastPage}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            );
          }
          final PhotoSessionDto s = p.data[index - 1];
          return _SessionCard(
            session: s,
            onDelete: () => _delete(s),
            onPrint: () => _printAndEmail(s),
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onDelete,
    required this.onPrint,
  });

  final PhotoSessionDto session;
  final VoidCallback onDelete;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String subtitle = <String>[
      if (session.booth != null) 'Booth ${session.booth!.name}',
      if (session.photoFrame != null) 'Frame ${session.photoFrame!.name}',
      if (session.filter != null && session.filter!.isNotEmpty)
        'Filter ${session.filter}',
      '${session.media.length} media',
    ].join(' • ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        session.sessionCode,
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(label: Text('#${session.id}')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Hapus'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: onPrint,
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Print + Email'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
