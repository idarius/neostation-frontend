import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/repositories/config_repository.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/services/permission_service.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:flutter/services.dart';
import 'package:neostation/widgets/tv_directory_picker.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';

/// A standalone screen for managing root ROM directories and initiating system-wide scans.
///
/// Implements a legacy configuration interface with full gamepad support, SAF
/// (Storage Access Framework) orchestration, and a blocking progress modal for
/// background filesystem indexing.
class DirectoriesScreen extends StatefulWidget {
  const DirectoriesScreen({super.key});

  @override
  State<DirectoriesScreen> createState() => _DirectoriesScreenState();
}

class _DirectoriesScreenState extends State<DirectoriesScreen> {
  late GamepadNavigation _gamepadNav;
  int _selectedIndex = 0;
  String? _currentRomFolder;
  bool _isLoading = true;

  static final _log = LoggerService.instance;

  /// Definitive list of configurable directory entry points.
  final List<Map<String, dynamic>> _baseDirectoryItems = [
    {
      'title': AppLocale.romsFolderTitle,
      'subtitle': AppLocale.romsFolderSubtitle,
      'icon': 'folder-bulk.png',
      'action': 'roms',
    },
  ];

  /// Platform-Contextual filtering for directory items.
  List<Map<String, dynamic>> get _directoryItems {
    // Current implementation treats desktop and mobile platforms with parity
    // for RetroArch config detection and ROM management.
    return _baseDirectoryItems;
  }

  @override
  void initState() {
    super.initState();
    _initializeGamepadNavigation();
    _loadCurrentPaths();
  }

  /// Synchronizes the UI state with the persistent directory configuration.
  Future<void> _loadCurrentPaths() async {
    try {
      final folders = await ConfigRepository.getUserRomFolders();
      _currentRomFolder = folders.isNotEmpty ? folders.first : null;
    } catch (e) {
      _log.e('Failed to load persistent directory configuration: $e');
    } finally {
      // Validate the selection index after data synchronization.
      if (_selectedIndex >= _directoryItems.length &&
          _directoryItems.isNotEmpty) {
        _selectedIndex = 0;
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _gamepadNav.dispose();
    super.dispose();
  }

  /// Configures the gamepad layer for specialized screen-level navigation.
  void _initializeGamepadNavigation() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: () => _navigateUp(),
      onNavigateDown: () => _navigateDown(),
      onNavigateLeft: () => _navigateLeft(),
      onNavigateRight: () => _navigateRight(),
      onSelectItem: () => _selectItem(),
      onBack: () => Navigator.of(context).pop(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      _gamepadNav.activate();
    });
  }

  void _navigateUp() {
    setState(() {
      _selectedIndex =
          (_selectedIndex - 1 + _directoryItems.length) %
          _directoryItems.length;
    });
  }

  void _navigateDown() {
    setState(() {
      _selectedIndex = (_selectedIndex + 1) % _directoryItems.length;
    });
  }

  void _navigateLeft() {
    // No horizontal navigation defined for the current vertical list layout.
  }

  void _navigateRight() {
    // No horizontal navigation defined for the current vertical list layout.
  }

  void _selectItem() {
    if (_selectedIndex < _directoryItems.length) {
      final item = _directoryItems[_selectedIndex];
      _handleItemTap(item);
    }
  }

  /// Dispatches directory-related events based on the user-selected action.
  Future<void> _handleItemTap(Map<String, dynamic> item) async {
    switch (item['action']) {
      case 'roms':
        await _selectRomFolder();
        break;
    }
  }

  /// Platform-Adaptive Directory Selection flow.
  Future<void> _selectRomFolder() async {
    try {
      String? selectedDirectory;

      if (Platform.isAndroid) {
        try {
          // Attempt standard SAF (Storage Access Framework) folder request.
          final uri = await PermissionService.requestFolderAccess();
          selectedDirectory = uri?.toString();
        } on PlatformException catch (e) {
          // Android TV Fallback: Custom browser for D-pad only environments.
          if (e.code == 'PICKER_FAILED' && mounted) {
            selectedDirectory = await TvDirectoryPicker.show(context);
          }
        }
      } else {
        // Desktop Platforms: Native system directory selector.
        selectedDirectory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: AppLocale.selectRomFolder.getString(context),
          initialDirectory: _currentRomFolder,
        );
      }

      if (selectedDirectory != null) {
        if (mounted) {
          setState(() {
            _currentRomFolder = selectedDirectory;
          });
        }

        if (!mounted) return;
        final configProvider = Provider.of<SqliteConfigProvider>(
          context,
          listen: false,
        );

        // Commit the directory path to the persistent provider state.
        await configProvider.addRomFolder(selectedDirectory);

        // Trigger the atomic background scan flow.
        await _showScanningDialog();

        if (mounted) {
          AppNotification.showNotification(
            context,
            AppLocale.romFolderUpdated.getString(context),
            type: NotificationType.success,
          );
        }
      }
    } catch (e) {
      _log.e('Directory selection flow interrupted: $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          'Error selecting ROM folder: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  /// Orchestrates an atomic, blocking progress modal during background ROM scanning.
  Future<void> _showScanningDialog() async {
    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );

    // Platform: Android - Verify directory access permissions before initiating scan.
    if (Platform.isAndroid) {
      final romFolder = _currentRomFolder;
      if (romFolder != null) {
        final canAccess = await PermissionService.canAccessDirectory(romFolder);

        if (!canAccess) {
          _log.e('Cannot access ROM folder: $romFolder');

          if (mounted) {
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    SizedBox(width: 8.r),
                    Expanded(
                      child: Text(
                        AppLocale.cannotAccessFolder.getString(context),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cannot access: $romFolder\n'),
                      Text(AppLocale.ensureValidFolderDesc.getString(context)),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLocale.ok.getString(context)),
                  ),
                ],
              ),
            );
          }
          return; // Abort the scan if directory access is denied.
        }
      }
    }

    // Blocking Modal: Prevent user interaction during critical database indexing.
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Consumer<SqliteConfigProvider>(
          builder: (dialogContext, provider, child) {
            return Dialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Container(
                constraints: BoxConstraints(maxWidth: 500.w, maxHeight: 400.h),
                padding: EdgeInsets.all(32.r),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Visual Status Indicator
                    Container(
                      width: 64.r,
                      height: 64.r,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(32.r),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 32.r,
                          height: 32.r,
                          child: provider.scanCompleted
                              ? Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 32.r,
                                )
                              : CircularProgressIndicator(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                        ),
                      ),
                    ),
                    SizedBox(height: 24.r),

                    // Contextual Header
                    Text(
                      provider.scanCompleted
                          ? AppLocale.scanningComplete.getString(context)
                          : AppLocale.scanningRoms.getString(context),
                      style: TextStyle(
                        fontSize: 20.r,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 8.r),

                    // Technical Status Metadata
                    Text(
                      provider.scanStatus.isNotEmpty
                          ? provider.scanStatus
                          : AppLocale.scanningSystemsRoms.getString(context),
                      style: TextStyle(
                        fontSize: 14.r,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    // Deterministic Progress Tracking
                    if (provider.totalSystemsToScan > 0) ...[
                      SizedBox(height: 24.r),
                      LinearProgressIndicator(
                        value: provider.scanProgress,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      SizedBox(height: 12.r),
                      Text(
                        AppLocale.ofSystems
                            .getString(context)
                            .replaceFirst(
                              '{scanned}',
                              provider.scannedSystemsCount.toString(),
                            )
                            .replaceFirst(
                              '{total}',
                              provider.totalSystemsToScan.toString(),
                            ),
                        style: TextStyle(
                          fontSize: 12.r,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // Protocol: Initiate background scanning engine.
    await configProvider.scanSystems();

    // Protocol: Close the blocking modal upon completion.
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modular Header: Branding and navigation context.
          Container(
            margin: EdgeInsets.all(8.r),
            padding: EdgeInsets.all(12.r),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: theme.colorScheme.primary, width: 1.r),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.arrow_back,
                    color: theme.colorScheme.primary,
                    size: 24.r,
                  ),
                ),
                SizedBox(width: 8.r),
                Container(
                  padding: EdgeInsets.all(4.r),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.2),
                        blurRadius: 8.r,
                        offset: Offset(0, 2.h),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: 32.r,
                    height: 32.r,
                    child: Image.asset(
                      'assets/images/icons/folder-bulk.png',
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                SizedBox(width: 12.r),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocale.directories.getString(context),
                        style: TextStyle(
                          fontSize: 18.r,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Text(
                        AppLocale.configureRomsFolder.getString(context),
                        style: TextStyle(
                          fontSize: 12.r,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 12.r),

          // Lifecycle-aware Content Layer.
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primary,
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.r),
                    child: ListView.builder(
                      itemCount: _directoryItems.length,
                      itemBuilder: (context, index) {
                        final item = _directoryItems[index];
                        final isSelected = _selectedIndex == index;
                        return _buildDirectoryCard(
                          context,
                          item,
                          isSelected,
                          index,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Constructs a standardized configuration card for managed directories.
  Widget _buildDirectoryCard(
    BuildContext context,
    Map<String, dynamic> item,
    bool isSelected,
    int index,
  ) {
    final theme = Theme.of(context);
    String? currentPath;
    if (item['action'] == 'roms') {
      currentPath = _currentRomFolder;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 6.r),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.primary.withValues(alpha: 0.5),
          width: isSelected ? 2.r : 1.r,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : theme.colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: isSelected ? 12.r : 6.r,
            offset: Offset(0, 3.h),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          canRequestFocus: false,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          borderRadius: BorderRadius.circular(12.r),
          onTap: () {
            SfxService().playNavSound();
            _handleItemTap(item);
          },
          child: Padding(
            padding: EdgeInsets.all(12.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36.r,
                      height: 36.r,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primary.withValues(alpha: 0.15)
                            : theme.colorScheme.primary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8.r),
                        boxShadow: [
                          BoxShadow(
                            color: isSelected
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.3,
                                  )
                                : Colors.black.withValues(alpha: 0.2),
                            blurRadius: 6.r,
                            offset: Offset(0, 1.5.r),
                          ),
                        ],
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 20.r,
                          height: 20.r,
                          child: Image.asset(
                            'assets/images/icons/${item['icon']}',
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary.withValues(
                                    alpha: 0.5,
                                  ),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(width: 12.r),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title'].getString(context),
                            style: TextStyle(
                              fontSize: 14.r,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.primary.withValues(
                                      alpha: 0.5,
                                    ),
                            ),
                          ),
                          SizedBox(height: 2.r),
                          Text(
                            item['subtitle'].getString(context),
                            style: TextStyle(
                              fontSize: 11.r,
                              color: isSelected
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.8,
                                    )
                                  : theme.colorScheme.primary.withValues(
                                      alpha: 0.5,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Icon(
                      Icons.chevron_right,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.primary.withValues(alpha: 0.5),
                      size: 20.r,
                    ),
                  ],
                ),

                // Metadata Layer: Active filesystem path visualization.
                if (currentPath != null) ...[
                  SizedBox(height: 8.r),
                  Container(
                    padding: EdgeInsets.all(6.r),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder,
                          size: 14.r,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        SizedBox(width: 6.r),
                        Expanded(
                          child: Text(
                            currentPath,
                            style: TextStyle(
                              fontSize: 11.r,
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.5,
                              ),
                              fontFamily: 'monospace',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
