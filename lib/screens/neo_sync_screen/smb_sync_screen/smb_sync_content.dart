import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/services/smb/smb_client.dart';
import 'package:neostation/services/smb/smb_exceptions.dart';

/// Phase 1 Hello-World debug UI for SMB connection validation.
/// Phase 2 replaces this with the proper form + provider integration.
class SmbSyncContent extends StatefulWidget {
  final VoidCallback onBack;

  const SmbSyncContent({super.key, required this.onBack});

  @override
  State<SmbSyncContent> createState() => _SmbSyncContentState();
}

class _SmbSyncContentState extends State<SmbSyncContent> {
  final _hostCtrl = TextEditingController();
  final _shareCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _domainCtrl = TextEditingController(text: 'WORKGROUP');

  bool _busy = false;
  String _status = 'Idle';
  Color _statusColor = Colors.grey;
  List<SmbDirEntry> _entries = const [];

  @override
  void dispose() {
    _hostCtrl.dispose();
    _shareCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _domainCtrl.dispose();
    super.dispose();
  }

  Future<void> _onTest() async {
    setState(() {
      _busy = true;
      _status = 'Connecting...';
      _statusColor = Colors.orange;
      _entries = const [];
    });
    SmbConnection? conn;
    try {
      conn = await SmbClient.connect(
        host: _hostCtrl.text.trim(),
        share: _shareCtrl.text.trim(),
        user: _userCtrl.text.trim(),
        pass: _passCtrl.text,
        domain: _domainCtrl.text.trim(),
      );
      final entries = await conn.listDirectory('');
      if (!mounted) return;
      setState(() {
        _status = 'Connected — ${entries.length} entries at root';
        _statusColor = Colors.green;
        _entries = entries;
      });
    } on SmbException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '${e.runtimeType}: ${e.message}';
        _statusColor = Colors.red;
      });
    } finally {
      await conn?.disconnect();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 12.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
              SizedBox(width: 4.r),
              Text(
                'SMB Hello-World (debug)',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          SizedBox(height: 8.r),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field('Host / IP', _hostCtrl, hint: '192.168.0.10'),
                  _field('Share', _shareCtrl, hint: 'Backups'),
                  _field('Username', _userCtrl),
                  _field('Password', _passCtrl, obscure: true),
                  _field('Domain', _domainCtrl),
                  SizedBox(height: 8.r),
                  ElevatedButton(
                    onPressed: _busy ? null : _onTest,
                    child: Text(
                      _busy ? 'Testing...' : 'Test connection + list root',
                    ),
                  ),
                  SizedBox(height: 12.r),
                  Container(
                    padding: EdgeInsets.all(8.r),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(
                      _status,
                      style: TextStyle(color: _statusColor),
                    ),
                  ),
                  if (_entries.isNotEmpty) ...[
                    SizedBox(height: 12.r),
                    Text('Entries:', style: theme.textTheme.titleSmall),
                    for (final e in _entries.take(20))
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 1.r),
                        child: Text(
                          '${e.isDir ? "[DIR] " : "      "}${e.name}  (${e.size} B)',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (_entries.length > 20)
                      Text(
                        '... and ${_entries.length - 20} more',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                  ],
                  if (kDebugMode) ...[
                    SizedBox(height: 16.r),
                    Text(
                      'DEBUG MODE — this UI is replaced in Phase 2.',
                      style: TextStyle(fontSize: 10.r, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
    String? hint,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.r),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
