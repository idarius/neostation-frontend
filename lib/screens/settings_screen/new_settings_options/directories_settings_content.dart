import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/repositories/config_repository.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:provider/provider.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/services/permission_service.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/widgets/tv_directory_picker.dart';
import 'package:flutter/services.dart';
import 'settings_title.dart';

/// A specialized content panel for managing filesystem entry points for ROM discovery.
///
/// Orchestrates folder-level persistence in SQLite, handles platform-specific
/// directory pickers (with Android TV support), and synchronizes background
/// scanning status and progress.
class DirectoriesSettingsContent extends StatefulWidget {
  final bool isContentFocused;
  final int selectedContentIndex;

  const DirectoriesSettingsContent({
    super.key,
    required this.isContentFocused,
    required this.selectedContentIndex,
  });

  @override
  State<DirectoriesSettingsContent> createState() =>
      DirectoriesSettingsContentState();
}

class DirectoriesSettingsContentState
    extends State<DirectoriesSettingsContent> {
  final ScrollController _scrollController = ScrollController();
  List<String> _currentRomFolders = [];
  bool _isLoading = true;

  /// Guards the one-time post-init bootstrap to prevent re-entry on
  /// every didChangeDependencies fire (locale change, theme switch, …).
  bool _bootstrapped = false;

  static final _log = LoggerService.instance;

  /// Dynamic list of navigable directory actions and managed paths.
  final List<Map<String, dynamic>> _directoryItems = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // _buildDirectoryItems calls AppLocale.getString(context), which requires
    // the inherited Localizations scope to be wired up — not yet the case in
    // initState. didChangeDependencies fires once after that scope is ready.
    if (_bootstrapped) return;
    _bootstrapped = true;
    _buildDirectoryItems();
    _loadCurrentPaths();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Synchronizes the scroll viewport with the gamepad-focused item.
  void scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      index * 60.h, // Heuristic height based on standard list item geometry.
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  /// Rebuilds the internal navigation model based on the current persistent ROM folders.
  void _buildDirectoryItems() {
    _directoryItems.clear();

    // Primary Action: System-wide ROM Rescan.
    _directoryItems.add({
      'title': AppLocale.rescanAllFolders.getString(context),
      'subtitle': AppLocale.rescanAllFoldersSubtitle.getString(context),
      'action': 'rescan',
    });

    // Secondary Action: Addition of new ROM entry points.
    _directoryItems.add({
      'title': AppLocale.directories.getString(context),
      'subtitle': AppLocale.romsFolderSubtitle.getString(context),
      'action': 'roms',
    });

    // Dynamic Managed Paths: Individual entries for established ROM folders.
    for (final path in _currentRomFolders) {
      _directoryItems.add({
        'title': path,
        'subtitle': AppLocale.pressToRemoveFolder.getString(context),
        'action': 'remove_rom',
        'path': path,
      });
    }
  }

  /// Fetches the currently managed ROM directories from the SQLite service.
  Future<void> _loadCurrentPaths() async {
    try {
      _currentRomFolders = await ConfigRepository.getUserRomFolders();
    } catch (e) {
      _log.e('Failed to retrieve managed ROM paths: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _buildDirectoryItems();
        });
      }
    }
  }

  /// Dispatches directory-related events based on the user-selected action.
  Future<void> _handleItemTap(Map<String, dynamic> item) async {
    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );

    switch (item['action']) {
      case 'rescan':
        await configProvider.scanSystems();
        break;
      case 'roms':
        await _selectRomFolder();
        break;
      case 'remove_rom':
        await _removeRomFolder(item['path'] as String);
        break;
    }
  }

  /// Platform-Adaptive Directory Selection flow.
  Future<void> _selectRomFolder() async {
    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );

    // Hard Limit Arbitration: Enforce maximum manageable directory paths.
    if (configProvider.config.romFolders.length >= 5) {
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.maxRomFoldersReached.getString(context),
          type: NotificationType.info,
        );
      }
      return;
    }

    try {
      String? selectedDirectory;

      if (Platform.isAndroid) {
        final isTV = await PermissionService.isTelevision();
        if (isTV) {
          // Use specialized D-pad friendly picker for Android TV environments.
          if (mounted) {
            selectedDirectory = await TvDirectoryPicker.show(context);
          }
        } else {
          try {
            // Attempt standard SAF (Storage Access Framework) folder request.
            final uri = await PermissionService.requestFolderAccess();
            selectedDirectory = uri?.toString();
          } on PlatformException catch (e) {
            // Fallback to internal picker if SAF is unavailable or fails.
            if (e.code == 'PICKER_FAILED' && mounted) {
              selectedDirectory = await TvDirectoryPicker.show(context);
            }
          }
        }
      } else {
        // Desktop Platforms: Invoke the native system directory selector.
        selectedDirectory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: AppLocale.selectRomsFolder.getString(context),
        );
      }

      if (selectedDirectory != null) {
        await configProvider.addRomFolder(selectedDirectory);
        await _loadCurrentPaths();
      }
    } catch (e) {
      _log.e('Directory selection flow interrupted: $e');
    }
  }

  /// Removes a directory from the managed list and purges associated ROM metadata.
  Future<void> _removeRomFolder(String path) async {
    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );
    try {
      await configProvider.removeRomFolder(path);
      await _loadCurrentPaths();
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.romFolderRemoved.getString(context),
          type: NotificationType.info,
        );
      }
    } catch (e) {
      _log.e('Failed to remove directory: $e');
    }
  }

  int getItemCount() {
    return _directoryItems.length;
  }

  void selectItem(int index) {
    if (index < _directoryItems.length) {
      _handleItemTap(_directoryItems[index]);
    }
  }

  /// Builds a visual action indicator (Add/Remove/Refresh).
  Widget _buildActionButton(
    ThemeData theme,
    bool isSelected,
    IconData icon, {
    bool isDestructive = false,
  }) {
    final color = isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Container(
      padding: EdgeInsets.all(4.r),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isSelected ? 1.0 : 0.8),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 4.r,
            offset: Offset(0, 2.r),
          ),
        ],
      ),
      child: Icon(icon, color: theme.colorScheme.onPrimary, size: 16.r),
    );
  }

  /// Progress Orchestration: Displays real-time status of the background scanning engine.
  Widget _buildScanProgress(ThemeData theme, SqliteConfigProvider provider) {
    if (!provider.isScanning || provider.totalSystemsToScan <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.r),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1.r,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                provider.scanStatus,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10.r,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                '${(provider.scanProgress * 100).toInt()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10.r,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.r),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: LinearProgressIndicator(
              value: provider.scanProgress,
              minHeight: 6.r,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
          SizedBox(height: 4.r),
          Text(
            '${AppLocale.scanningSystem.getString(context)} ${provider.scannedSystemsCount} of ${provider.totalSystemsToScan}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsTitle(
            title: AppLocale.configureDirectories.getString(context),
            subtitle: AppLocale.configureRomsFolder.getString(context),
          ),
          SizedBox(height: 24.h),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    return Consumer<SqliteConfigProvider>(
      builder: (context, configProvider, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsTitle(
              title: AppLocale.configureDirectories.getString(context),
              subtitle: AppLocale.configureRomsFolder.getString(context),
            ),
            SizedBox(height: 12.r),
            _buildScanProgress(theme, configProvider),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                physics: const ClampingScrollPhysics(),
                itemCount: _directoryItems.length,
                itemBuilder: (context, index) {
                  final item = _directoryItems[index];
                  final isSelected =
                      widget.isContentFocused &&
                      widget.selectedContentIndex == index;

                  final isRemoveItem = item['action'] == 'remove_rom';
                  final borderColor = isSelected
                      ? (isRemoveItem
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary)
                      : theme.colorScheme.outline.withValues(alpha: 0);

                  return Container(
                    decoration: BoxDecoration(
                      color: isSelected && isRemoveItem
                          ? theme.colorScheme.error.withValues(alpha: 0.08)
                          : theme.cardColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: borderColor,
                        width: isSelected ? 2.r : 1.r,
                      ),
                    ),
                    margin: EdgeInsets.only(bottom: 12.r),
                    child: InkWell(
                      onTap: () {
                        SfxService().playNavSound();
                        _handleItemTap(item);
                      },
                      borderRadius: BorderRadius.circular(12.r),
                      canRequestFocus: false,
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: 12.r,
                          right: 12.r,
                          top: 6.r,
                          bottom: 6.r,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isRemoveItem
                                  ? Icons.folder
                                  : item['action'] == 'rescan'
                                  ? Icons.refresh
                                  : Icons.folder_outlined,
                              color: isSelected
                                  ? (isRemoveItem
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.primary)
                                  : theme.colorScheme.onSurface,
                              size: 20.r,
                            ),
                            SizedBox(width: 12.r),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['title'] as String,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: isRemoveItem ? 10.r : 12.r,
                                      color: isSelected
                                          ? (isRemoveItem
                                                ? theme.colorScheme.error
                                                : theme.colorScheme.primary)
                                          : theme.colorScheme.onSurface,
                                      fontFamily: isRemoveItem
                                          ? 'monospace'
                                          : null,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: 4.r),
                                  Text(
                                    item['subtitle'] as String,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: isSelected && isRemoveItem
                                          ? theme.colorScheme.error.withValues(
                                              alpha: 0.7,
                                            )
                                          : theme.colorScheme.onSurface
                                                .withValues(alpha: 0.6),
                                      fontSize: 9.r,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isRemoveItem)
                              _buildActionButton(
                                theme,
                                isSelected,
                                Icons.delete_outline,
                                isDestructive: true,
                              )
                            else if (item['action'] == 'roms')
                              _buildActionButton(theme, isSelected, Icons.add)
                            else if (item['action'] == 'rescan')
                              _buildActionButton(
                                theme,
                                isSelected,
                                Icons.refresh,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
