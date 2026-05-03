import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/smb_credentials_model.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/sync/providers/smb_sync_provider.dart';
import 'package:neostation/models/sync_models.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:provider/provider.dart';

/// Final SMB content screen (Phase 2): credential form, status pill, and
/// 4 action buttons (Test connection, Save & activate, Upload test file in
/// debug mode, List saves).
class SmbSyncContent extends StatefulWidget {
  final VoidCallback onBack;

  const SmbSyncContent({super.key, required this.onBack});

  @override
  State<SmbSyncContent> createState() => _SmbSyncContentState();
}

class _SmbSyncContentState extends State<SmbSyncContent> {
  static const _layerKey = 'smb_sync_content';

  final _hostCtrl = TextEditingController();
  final _shareCtrl = TextEditingController();
  final _subdirCtrl = TextEditingController(text: 'idastation_saves');
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _domainCtrl = TextEditingController(text: 'WORKGROUP');

  bool _busy = false;
  String? _resultMessage;
  Color? _resultColor;

  late GamepadNavigation _nav;
  bool _layerPushed = false;

  SmbSyncProvider? get _provider =>
      SyncManager.instance[SmbSyncProvider.kProviderId] as SmbSyncProvider?;

  @override
  void initState() {
    super.initState();
    _provider?.addListener(_onProviderChanged);
    _populateFromProvider();
    // Minimal gamepad layer: B = back. Other inputs (D-pad, A) fall
    // through; the form is text-heavy and best driven by touch/keyboard.
    _nav = GamepadNavigation(onBack: widget.onBack);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pushLayer();
      _nav.initialize();
    });
  }

  @override
  void dispose() {
    _popLayer();
    _nav.dispose();
    _provider?.removeListener(_onProviderChanged);
    _hostCtrl.dispose();
    _shareCtrl.dispose();
    _subdirCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _domainCtrl.dispose();
    super.dispose();
  }

  void _pushLayer() {
    if (_layerPushed) return;
    _layerPushed = true;
    GamepadNavigationManager.pushLayer(
      _layerKey,
      onActivate: () => _nav.activate(),
      onDeactivate: () => _nav.deactivate(),
    );
  }

  void _popLayer() {
    if (!_layerPushed) return;
    _layerPushed = false;
    GamepadNavigationManager.popLayer(_layerKey);
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  /// On first show, pre-fill the form fields from the saved config so the
  /// user sees their previous values. Password is NOT pre-filled (security).
  void _populateFromProvider() {
    final cfg = _provider?.config;
    if (cfg == null) return;
    _hostCtrl.text = cfg.host;
    _shareCtrl.text = cfg.share;
    _subdirCtrl.text = cfg.subdirectory;
    _userCtrl.text = cfg.username;
    _domainCtrl.text = cfg.domain;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _onTest() async {
    final p = _provider;
    if (p == null) return;
    setState(() {
      _busy = true;
      _resultMessage = null;
    });
    try {
      // Build a transient model from form, but don't persist — we just want
      // to validate the connection.
      final cfg = SmbCredentialsModel(
        host: _hostCtrl.text.trim(),
        share: _shareCtrl.text.trim(),
        subdirectory: _subdirCtrl.text.trim().isEmpty
            ? 'idastation_saves'
            : _subdirCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        domain: _domainCtrl.text.trim().isEmpty
            ? 'WORKGROUP'
            : _domainCtrl.text.trim(),
      );
      // Reuse updateCredentials path so the test connection mirrors the
      // production "Save & activate" flow.
      final r = await p.updateCredentials(
        config: cfg,
        password: _passCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _resultMessage = r.success
            ? AppLocale.smbSyncStatusConnected.getString(context)
            : (r.message ?? AppLocale.smbSyncErrUnknown.getString(context));
        _resultColor = r.success ? Colors.green : Colors.red;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onSaveAndActivate() async {
    final p = _provider;
    if (p == null) return;
    setState(() {
      _busy = true;
      _resultMessage = null;
    });
    try {
      final cfg = SmbCredentialsModel(
        host: _hostCtrl.text.trim(),
        share: _shareCtrl.text.trim(),
        subdirectory: _subdirCtrl.text.trim().isEmpty
            ? 'idastation_saves'
            : _subdirCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        domain: _domainCtrl.text.trim().isEmpty
            ? 'WORKGROUP'
            : _domainCtrl.text.trim(),
      );
      final r = await p.updateCredentials(
        config: cfg,
        password: _passCtrl.text,
      );
      if (!mounted) return;
      if (r.success) {
        // ignore: use_build_context_synchronously — guarded above by mounted check
        final cfgProvider =
            Provider.of<SqliteConfigProvider>(context, listen: false);
        await SyncManager.instance.setActive(
          SmbSyncProvider.kProviderId,
          persist: cfgProvider.updateActiveSyncProvider,
        );
        if (!mounted) return;
        setState(() {
          _resultMessage =
              '${AppLocale.smbSyncStatusConnected.getString(context)} — saved & activated';
          _resultColor = Colors.green;
        });
      } else {
        setState(() {
          _resultMessage =
              r.message ?? AppLocale.smbSyncErrUnknown.getString(context);
          _resultColor = Colors.red;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onUploadTestFile() async {
    final p = _provider;
    if (p == null || !p.isAuthenticated) {
      setState(() {
        _resultMessage = 'Not connected — Test or Save first';
        _resultColor = Colors.red;
      });
      return;
    }
    setState(() {
      _busy = true;
      _resultMessage = null;
    });
    try {
      // Synthesize a small test file in temp.
      final tempDir = Directory.systemTemp.createTempSync('smb_test_');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final testFile = File('${tempDir.path}/test_$ts.txt');
      await testFile.writeAsBytes(Uint8List.fromList(
        'Idastation SMB upload test — $ts\n'.codeUnits,
      ));
      final r = await p.uploadSave('_idastation_test', testFile);
      // Cleanup local temp.
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _resultMessage = r.success
            ? 'Uploaded: ${r.message}'
            : 'Upload failed: ${r.message}';
        _resultColor = r.success ? Colors.green : Colors.red;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onListSaves() async {
    final p = _provider;
    if (p == null || !p.isAuthenticated) {
      setState(() {
        _resultMessage = 'Not connected — Test or Save first';
        _resultColor = Colors.red;
      });
      return;
    }
    setState(() {
      _busy = true;
      _resultMessage = null;
    });
    try {
      final saves = await p.listSaves();
      if (!mounted) return;
      setState(() {
        _resultMessage = '${saves.length} save(s) at root';
        _resultColor = Colors.green;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  String _statusLabel() {
    final p = _provider;
    if (p == null) return 'No provider';
    final lastError = p.lastError;
    switch (p.status) {
      case SyncProviderStatus.connected:
        return AppLocale.smbSyncStatusConnected.getString(context);
      case SyncProviderStatus.connecting:
      case SyncProviderStatus.syncing:
        return 'Connecting…';
      case SyncProviderStatus.error:
        return AppLocale.smbSyncStatusError
            .getString(context)
            .replaceAll('{error}', lastError ?? 'unknown');
      case SyncProviderStatus.disconnected:
        return AppLocale.smbSyncStatusDisconnected.getString(context);
      case SyncProviderStatus.paused:
        return 'Paused';
    }
  }

  Color _statusColor() {
    final p = _provider;
    if (p == null) return Colors.grey;
    switch (p.status) {
      case SyncProviderStatus.connected:
        return Colors.green;
      case SyncProviderStatus.connecting:
      case SyncProviderStatus.syncing:
        return Colors.orange;
      case SyncProviderStatus.error:
        return Colors.red;
      case SyncProviderStatus.disconnected:
        return Colors.grey;
      case SyncProviderStatus.paused:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        // Extra top padding to clear the LB/RB tab navbar that overlays the
        // top of the page in this app's tab layout.
        padding: EdgeInsets.fromLTRB(16.r, 56.r, 16.r, 12.r),
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
                Icon(Icons.lan_rounded,
                    size: 22.r, color: theme.colorScheme.secondary),
                SizedBox(width: 8.r),
                Text(
                  AppLocale.smbSyncProviderName.getString(context),
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
                  _field(AppLocale.smbSyncFormHost, _hostCtrl,
                      hint: '192.168.0.10'),
                  _field(AppLocale.smbSyncFormShare, _shareCtrl,
                      hint: 'Aeris'),
                  _field(AppLocale.smbSyncFormSubdir, _subdirCtrl,
                      hint: 'idastation_saves'),
                  _field(AppLocale.smbSyncFormUser, _userCtrl),
                  _field(
                    AppLocale.smbSyncFormPassword,
                    _passCtrl,
                    obscure: true,
                    hint: _provider?.hasStoredPassword == true
                        ? '••••••• (laisser vide pour conserver)'
                        : null,
                  ),
                  _field(AppLocale.smbSyncFormDomain, _domainCtrl),
                  SizedBox(height: 8.r),
                  Wrap(
                    spacing: 8.r,
                    runSpacing: 8.r,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _busy ? null : _onTest,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                            AppLocale.smbSyncBtnTest.getString(context)),
                      ),
                      ElevatedButton.icon(
                        onPressed: _busy ? null : _onSaveAndActivate,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(
                            AppLocale.smbSyncBtnSave.getString(context)),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _onListSaves,
                        icon: const Icon(Icons.list_rounded),
                        label: Text(
                            AppLocale.smbSyncBtnList.getString(context)),
                      ),
                      if (kDebugMode)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _onUploadTestFile,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('Upload test file (debug)'),
                        ),
                    ],
                  ),
                  // Unified status line: shows the latest action result
                  // when one exists, otherwise the live provider state.
                  SizedBox(height: 12.r),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(8.r),
                    decoration: BoxDecoration(
                      color: (_resultMessage != null
                              ? (_resultColor ?? Colors.grey)
                              : _statusColor())
                          .withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(
                      _resultMessage ?? _statusLabel(),
                      style: TextStyle(
                        color: _resultMessage != null
                            ? _resultColor
                            : _statusColor(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _field(
    String labelKey,
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
          labelText: labelKey.getString(context),
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
