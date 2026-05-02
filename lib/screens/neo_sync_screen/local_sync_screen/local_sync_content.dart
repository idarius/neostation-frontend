import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/sync/i_sync_provider.dart';
import 'package:neostation/sync/providers/local_storage_provider.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:provider/provider.dart';

/// Content screen for the Local / NAS sync provider.
///
/// Displays the current target path, the provider's connection status, and
/// 3 actions: pick a folder, test access, list saves. Path changes require
/// an app restart (the provider's targetPath is final).
class LocalSyncContent extends StatefulWidget {
  final VoidCallback onBack;

  const LocalSyncContent({super.key, required this.onBack});

  @override
  State<LocalSyncContent> createState() => _LocalSyncContentState();
}

class _LocalSyncContentState extends State<LocalSyncContent> {
  static const _layerKey = 'local_sync_content';
  static const _btnCount = 3;

  late GamepadNavigation _nav;
  bool _layerPushed = false;
  int _focusIndex = 0;
  String? _statusOverride;
  String? _listingResult;

  LocalStorageProvider? get _provider =>
      SyncManager.instance[LocalStorageProvider.kProviderId]
          as LocalStorageProvider?;

  @override
  void initState() {
    super.initState();
    _nav = GamepadNavigation(
      onNavigateUp: _moveUp,
      onNavigateDown: _moveDown,
      onSelectItem: _activateFocused,
      onBack: widget.onBack,
    );
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

  void _moveUp() => setState(
    () => _focusIndex = (_focusIndex - 1 + _btnCount) % _btnCount,
  );

  void _moveDown() => setState(
    () => _focusIndex = (_focusIndex + 1) % _btnCount,
  );

  void _activateFocused() {
    switch (_focusIndex) {
      case 0:
        _onPickFolder();
        break;
      case 1:
        _onTestAccess();
        break;
      case 2:
        _onListSaves();
        break;
    }
  }

  Future<void> _onPickFolder() async {
    final dialogTitle = AppLocale.localSyncBtnPickFolder.getString(context);
    final restartHint = AppLocale.localSyncRestartHint.getString(context);
    final configProvider = context.read<SqliteConfigProvider>();
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
    );
    if (picked == null) return;

    if (picked.startsWith('content://')) {
      if (!mounted) return;
      final msg =
          AppLocale.localSyncContentUriUnsupported.getString(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    }

    await configProvider.updateLocalSyncPath(picked);
    if (!mounted) return;
    setState(() {
      _statusOverride = null;
      _listingResult = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(restartHint),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _onTestAccess() async {
    final p = _provider;
    if (p == null) return;
    final r = await p.login();
    if (!mounted) return;
    setState(() {
      _statusOverride = r.success
          ? AppLocale.localSyncStatusConnected.getString(context)
          : (r.message ?? 'Error');
    });
  }

  Future<void> _onListSaves() async {
    final p = _provider;
    if (p == null) return;
    final saves = await p.listSaves();
    if (!mounted) return;
    setState(() {
      _listingResult = saves.length.toString();
    });
  }

  String _statusLabel(BuildContext context) {
    if (_statusOverride != null) return _statusOverride!;
    final p = _provider;
    if (p == null) {
      return AppLocale.localSyncStatusUnconfigured.getString(context);
    }
    if (p.status == SyncProviderStatus.connected) {
      return AppLocale.localSyncStatusConnected.getString(context);
    }
    if (p.status == SyncProviderStatus.error) {
      final err = p.lastError ?? 'unknown';
      return AppLocale.localSyncStatusError
          .getString(context)
          .replaceAll('{error}', err);
    }
    return AppLocale.localSyncStatusUnconfigured.getString(context);
  }

  Color _statusColor() {
    final p = _provider;
    if (p == null) return Colors.orange;
    return switch (p.status) {
      SyncProviderStatus.connected => Colors.green,
      SyncProviderStatus.error => Colors.red,
      _ => Colors.orange,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configProvider = context.watch<SqliteConfigProvider>();
    final path = configProvider.config.localSyncPath;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.r, vertical: 24.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.folder_shared_rounded,
                size: 28.r,
                color: theme.colorScheme.secondary,
              ),
              SizedBox(width: 12.r),
              Text(
                AppLocale.localSyncProviderName.getString(context),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 20.r,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 16.r),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 10.r,
                  vertical: 4.r,
                ),
                decoration: BoxDecoration(
                  color: _statusColor().withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  _statusLabel(context),
                  style: TextStyle(
                    fontSize: 11.r,
                    color: _statusColor(),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 24.r),
          Text(
            path == null || path.isEmpty
                ? AppLocale.localSyncStatusUnconfigured.getString(context)
                : path,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 13.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontFamily: 'monospace',
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 32.r),
          _buildButton(
            context,
            index: 0,
            icon: Icons.folder_open_rounded,
            label: AppLocale.localSyncBtnPickFolder.getString(context),
          ),
          SizedBox(height: 12.r),
          _buildButton(
            context,
            index: 1,
            icon: Icons.refresh_rounded,
            label: AppLocale.localSyncBtnTest.getString(context),
          ),
          SizedBox(height: 12.r),
          _buildButton(
            context,
            index: 2,
            icon: Icons.list_rounded,
            label: AppLocale.localSyncBtnList.getString(context),
            trailing: _listingResult,
          ),
          const Spacer(),
          _buildNavHint(theme),
        ],
      ),
    );
  }

  Widget _buildButton(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
    String? trailing,
  }) {
    final theme = Theme.of(context);
    final isFocused = index == _focusIndex;
    final accent = theme.colorScheme.secondary;

    return GestureDetector(
      onTap: () {
        setState(() => _focusIndex = index);
        _activateFocused();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 12.r),
        decoration: BoxDecoration(
          color: isFocused
              ? accent.withValues(alpha: 0.15)
              : theme.colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isFocused
                ? accent.withValues(alpha: 0.8)
                : theme.colorScheme.onSurface.withValues(alpha: 0.15),
            width: isFocused ? 1.5.r : 1.r,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20.r,
              color: isFocused ? accent : theme.colorScheme.onSurface,
            ),
            SizedBox(width: 12.r),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.r,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: TextStyle(
                  fontSize: 11.r,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavHint(ThemeData theme) {
    final hintColor = theme.colorScheme.onSurface.withValues(alpha: 0.3);
    final textStyle = TextStyle(color: hintColor, fontSize: 10.r);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('▲▼', style: textStyle),
        SizedBox(width: 6.r),
        Text('Navigate', style: textStyle),
        SizedBox(width: 20.r),
        Image.asset(
          'assets/images/gamepad/Xbox_A_button.png',
          width: 16.r,
          height: 16.r,
          color: hintColor,
        ),
        SizedBox(width: 6.r),
        Text('Select', style: textStyle),
        SizedBox(width: 20.r),
        Image.asset(
          'assets/images/gamepad/Xbox_B_button.png',
          width: 16.r,
          height: 16.r,
          color: hintColor,
        ),
        SizedBox(width: 6.r),
        Text('Back', style: textStyle),
      ],
    );
  }
}
