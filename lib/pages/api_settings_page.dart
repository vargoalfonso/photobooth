import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/monolith_api_client.dart';
import '../services/photobooth_api_service.dart';
import '../state/photo_booth_config.dart';

/// Halaman untuk mengatur koneksi ke API monolith (Laravel) dan menguji
/// apakah endpoint sudah reachable.
class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key, required this.config});

  final PhotoBoothConfig config;

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _boothIdCtrl;

  bool _testing = false;
  bool _loadingTemplates = false;
  String? _testResult;
  bool _testOk = false;
  List<PhotoFrameDto> _templates = const <PhotoFrameDto>[];
  String? _templatesError;

  @override
  void initState() {
    super.initState();
    _baseUrlCtrl = TextEditingController(text: widget.config.apiBaseUrl);
    _tokenCtrl = TextEditingController(text: widget.config.apiAuthToken);
    _boothIdCtrl =
        TextEditingController(text: widget.config.apiBoothId.toString());
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _tokenCtrl.dispose();
    _boothIdCtrl.dispose();
    super.dispose();
  }

  void _saveToConfig() {
    widget.config.setApiBaseUrl(_baseUrlCtrl.text);
    widget.config.setApiAuthToken(_tokenCtrl.text);
    final int? id = int.tryParse(_boothIdCtrl.text.trim());
    if (id != null) {
      widget.config.setApiBoothId(id);
    }
  }

  Future<void> _testConnection() async {
    _saveToConfig();
    setState(() {
      _testing = true;
      _testResult = null;
      _testOk = false;
    });

    final MonolithApiClient client = MonolithApiClient(
      baseUrl: _baseUrlCtrl.text,
      token: _tokenCtrl.text.trim().isEmpty ? null : _tokenCtrl.text.trim(),
    );
    final PhotoboothApiService service = PhotoboothApiService(client);
    try {
      final List<PhotoFrameDto> frames = await service.listTemplates();
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult =
            'Terhubung. ${frames.length} template ditemukan di server.';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = 'Gagal: ${e.message} (HTTP ${e.statusCode ?? '-'})';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = 'Gagal: $e';
      });
    } finally {
      client.close();
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _loadTemplates() async {
    _saveToConfig();
    final PhotoboothApiService? service =
        PhotoboothApiService.fromConfig(widget.config);
    if (service == null) {
      setState(() {
        _templatesError =
            'Isi Base URL terlebih dahulu, lalu simpan.';
      });
      return;
    }
    setState(() {
      _loadingTemplates = true;
      _templatesError = null;
    });
    try {
      final List<PhotoFrameDto> data = await service.listTemplates();
      if (!mounted) return;
      setState(() => _templates = data);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _templatesError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _templatesError = e.toString());
    } finally {
      service.close();
      if (mounted) {
        setState(() => _loadingTemplates = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Monolith'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Koneksi',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      'Konfigurasi endpoint Laravel (routes/api.php).',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Wajib bayar sebelum mulai'),
                      subtitle: const Text(
                          'Pelanggan scan QR dari dashboard; booth baru jalan setelah status paid.'),
                      value: widget.config.requirePayment,
                      onChanged: (bool value) {
                        widget.config.setRequirePayment(value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _baseUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: 'http://127.0.0.1:8000/api',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tokenCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Bearer Token (opsional)',
                        hintText: 'Kosongkan bila endpoint tidak butuh auth.',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _boothIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Booth ID (integer)',
                        hintText: 'Sesuai dengan tabel `booths` di monolith.',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _testing ? null : _testConnection,
                            icon: _testing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.wifi_tethering),
                            label: Text(
                                _testing ? 'Menguji...' : 'Test Connection'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _saveToConfig();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Konfigurasi API disimpan.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Simpan'),
                          ),
                        ),
                      ],
                    ),
                    if (_testResult != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _testOk
                              ? Colors.green.withOpacity(0.12)
                              : Colors.red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _testOk
                                ? Colors.green.shade400
                                : Colors.red.shade300,
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              _testOk ? Icons.check_circle : Icons.error,
                              color: _testOk
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_testResult!)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Templates dari server',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed:
                              _loadingTemplates ? null : _loadTemplates,
                          icon: _loadingTemplates
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('Muat'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Endpoint: GET /api/templates',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_templatesError != null)
                      Text(
                        _templatesError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      )
                    else if (_templates.isEmpty)
                      Text(
                        'Belum ada data. Tekan Muat untuk menarik template dari server.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Column(
                        children: _templates
                            .map(
                              (PhotoFrameDto f) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  child: Text(f.id.toString()),
                                ),
                                title: Text(f.name),
                                subtitle: Text(
                                    '${f.category} • ${f.slotCount} slot • ${f.printSize}'),
                                trailing: Text(f.status),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Daftar endpoint yang tersedia',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const _EndpointRow(
                        method: 'GET', path: '/templates?category=...'),
                    const _EndpointRow(method: 'GET', path: '/photo-sessions'),
                    const _EndpointRow(
                        method: 'GET', path: '/photo-sessions/{id}'),
                    const _EndpointRow(
                        method: 'POST', path: '/photo-sessions'),
                    const _EndpointRow(
                        method: 'PUT', path: '/photo-sessions/{id}'),
                    const _EndpointRow(
                        method: 'DELETE', path: '/photo-sessions/{id}'),
                    const _EndpointRow(
                        method: 'POST',
                        path: '/photo-sessions/{id}/photos'),
                    const _EndpointRow(
                        method: 'DELETE',
                        path: '/photo-sessions/{id}/photos/{media}'),
                    const _EndpointRow(
                        method: 'POST',
                        path: '/photo-sessions/{id}/print'),
                    const _EndpointRow(method: 'POST', path: '/sessions'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.method, required this.path});

  final String method;
  final String path;

  Color _color(BuildContext context) {
    switch (method) {
      case 'GET':
        return Colors.blue.shade600;
      case 'POST':
        return Colors.green.shade700;
      case 'PUT':
        return Colors.orange.shade700;
      case 'DELETE':
        return Colors.red.shade600;
    }
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _color(context),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              method,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              path,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
