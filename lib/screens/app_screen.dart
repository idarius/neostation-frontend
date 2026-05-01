import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/services/update_service.dart';
import 'package:neostation/widgets/update_dialog.dart';
import 'package:neostation/services/logger_service.dart';
import '../widgets/fixed_header.dart';
import 'systems_screen/system_content.dart';
import 'retro_achievements_screen/ra_content.dart';
import 'settings_screen/new_settings_screen.dart';
import 'scraper_screen/new_scraper_options_screen.dart';
import 'neo_sync_screen/neo_sync_tab.dart';
import '../widgets/scraper_content.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/providers/theme_provider.dart';
import '../models/secondary_display_state.dart';
import 'dart:io';

/// The root screen of the application, managing high-level navigation tabs.
///
/// Coordinates the lifecycle of main features including the System library,
/// Cloud Sync, Achievements, Metadata Scraper, and Global Settings.
class AppScreen extends StatefulWidget {
  const AppScreen({super.key});

  @override
  AppScreenState createState() => AppScreenState();
}

/// Holds the currently selected card index inside the Console (Systems) tab.
/// Wrapped in a dedicated subclass so descendants (the SystemCard widgets and
/// the highlight overlay) can resolve it unambiguously via `context.select`
/// without colliding with any other `ValueNotifier<int>` Providers.
class SelectedSystemIndexNotifier extends ValueNotifier<int> {
  SelectedSystemIndexNotifier() : super(0);
}

/// Bridge class providing static access to the main application navigation state.
///
/// Facilitates tab switching and navigation lifecycle control from deep within
/// the component tree without requiring direct context propagation.
class AppNavigation {
  /// Temporarily suspends global gamepad and keyboard navigation.
  static void deactivate() {
    AppScreenState.deactivateNavigation();
  }

  /// Resumes global gamepad and keyboard navigation.
  static void activate() {
    AppScreenState.activateNavigation();
  }

  /// Switches to the next available navigation tab.
  static void nextTab() {
    AppScreenState._navigateToNextTabStatic();
  }

  /// Switches to the previous available navigation tab.
  static void previousTab() {
    AppScreenState._navigateToPreviousTabStatic();
  }
}

class AppScreenState extends State<AppScreen> {
  static final _log = LoggerService.instance;

  /// Currently active top-level navigation tab index.
  int _selectedTabIndex = 0;

  /// Selected system index inside the Console tab. A `ValueNotifier` (not a
  /// setState-bound field) so grid navigation updates it without rebuilding
  /// the whole AppScreen tree (Consumer2 + Scaffold + IndexedStack + all
  /// mounted tabs). Cards subscribe via `context.select` and only the two
  /// affected by a selection change rebuild — instead of all 26 every press.
  final SelectedSystemIndexNotifier _selectedSystemNotifier =
      SelectedSystemIndexNotifier();

  /// Input orchestration layer for gamepad and keyboard support.
  late GamepadNavigation _gamepadNav;

  /// Total number of top-level tabs (Console, Sync, RA, Scraper, Settings).
  static const int _tabCount = 5;

  /// Tabs that have been mounted at least once. Unvisited tabs render as
  /// placeholders inside the IndexedStack so app boot only pays for tab 0;
  /// other tabs init lazily when first reached via L1/R1.
  final Set<int> _visitedTabs = {0};

  /// Static reference to the currently active instance for global access.
  static AppScreenState? _currentInstance;

  ThemeProvider? _themeProvider;

  /// Tracks the deferred update-check listener so it can be removed cleanly.
  VoidCallback? _updateCheckListener;
  Timer? _updateCheckSafetyTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeProvider = Provider.of<ThemeProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _currentInstance = this;

    // Initialize the navigation bridge with core application callbacks.
    _gamepadNav = GamepadNavigation(
      onNavigateUp: _navigateContentUp,
      onNavigateDown: _navigateContentDown,
      onNavigateLeft: _navigateContentLeft,
      onNavigateRight: _navigateContentRight,
      onPreviousTab: _navigateToPreviousTab,
      onNextTab: _navigateToNextTab,
      onSelectItem: _selectCurrentItem,
      onSettings: _handleSettings,
      onBack: null, // Root level handles back navigation via PopScope.
    );

    // Register the base navigation layer SYNCHRONOUSLY during initState so
    // that any tab content mounted during the first build (via `IndexedStack`
    // + `TabActiveScope`) pushes its own layer ON TOP, not under, the base.
    GamepadNavigationManager.pushLayer(
      'app_screen',
      onActivate: () => _gamepadNav.activate(),
      onDeactivate: () => _gamepadNav.deactivate(),
    );

    // Asynchronous bits: gamepad subscription init and update check.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      _checkForUpdates();
    });

    // Synchronize theme changes with secondary displays (e.g., dual-screen hardware).
    _themeProvider?.addListener(_onThemeChanged);
  }

  /// Evaluates the availability of software updates, respecting active background tasks.
  ///
  /// If a ROM scan is active, defers the check until the scan transitions to
  /// idle, then fires exactly once. The listener self-removes on first
  /// successful invocation so subsequent provider notifications (e.g., a
  /// settings toggle) do not retrigger the update dialog. A 5-minute safety
  /// timer detaches the listener if the scan never completes; both the
  /// listener and timer are cleaned up in `dispose()`.
  Future<void> _checkForUpdates() async {
    try {
      final configProvider = Provider.of<SqliteConfigProvider>(
        context,
        listen: false,
      );

      if (!configProvider.isScanning) {
        _performUpdateCheck();
        return;
      }

      // Capture the initial state so we only fire on the transition
      // scanning -> idle, not on every notifyListeners() that arrives
      // while the provider is still scanning (or already idle).
      bool wasScanning = true;
      late final VoidCallback listener;
      listener = () {
        final isScanning = configProvider.isScanning;
        if (wasScanning && !isScanning) {
          // One-shot: detach immediately so we never fire twice.
          configProvider.removeListener(listener);
          _updateCheckListener = null;
          _updateCheckSafetyTimer?.cancel();
          _updateCheckSafetyTimer = null;
          if (mounted) _performUpdateCheck();
        }
        wasScanning = isScanning;
      };

      _updateCheckListener = listener;
      configProvider.addListener(listener);

      // Safety net: detach the listener if the scan never finishes.
      _updateCheckSafetyTimer = Timer(const Duration(minutes: 5), () {
        if (_updateCheckListener != null) {
          configProvider.removeListener(_updateCheckListener!);
          _updateCheckListener = null;
        }
        _updateCheckSafetyTimer = null;
      });
    } catch (e) {
      _log.e('AppScreen: Failed to initiate update check', error: e);
    }
  }

  /// Executes the version check and renders the update modal if a newer build is found.
  Future<void> _performUpdateCheck() async {
    try {
      final updateInfo = await UpdateService.checkForUpdates();

      if (updateInfo != null && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
      }
    } catch (e) {
      _log.e('AppScreen: Update check failure', error: e);
    }
  }

  @override
  void dispose() {
    _currentInstance = null;
    _themeProvider?.removeListener(_onThemeChanged);
    if (_updateCheckListener != null) {
      try {
        Provider.of<SqliteConfigProvider>(
          context,
          listen: false,
        ).removeListener(_updateCheckListener!);
      } catch (_) {}
      _updateCheckListener = null;
    }
    _updateCheckSafetyTimer?.cancel();
    _updateCheckSafetyTimer = null;
    _selectedSystemNotifier.dispose();
    GamepadNavigationManager.popLayer('app_screen');
    _gamepadNav.dispose();
    super.dispose();
  }

  /// Synchronizes visual state with secondary display hardware (Android OEM targets).
  void _onThemeChanged() {
    if (!mounted || !Platform.isAndroid || _themeProvider == null) return;

    final themeProvider = _themeProvider!;
    final secondaryState = SecondaryDisplayState();

    secondaryState.updateState(
      isOled: themeProvider.isOled,
      backgroundColor: themeProvider.currentTheme.scaffoldBackgroundColor
          .toARGB32(),
      themeName: themeProvider.currentThemeName,
    );

    _log.i(
      'AppScreen: Syncing theme with secondary display (isOled: ${themeProvider.isOled})',
    );
  }

  /// Static hook to suspend global navigation input.
  static void deactivateNavigation() {
    _currentInstance?._gamepadNav.deactivate();
  }

  /// Static hook to resume global navigation input.
  static void activateNavigation() {
    _currentInstance?._gamepadNav.activate();
  }

  static void _navigateToNextTabStatic() {
    _currentInstance?._navigateToNextTab();
  }

  static void _navigateToPreviousTabStatic() {
    _currentInstance?._navigateToPreviousTab();
  }

  // ==========================================
  // NAVIGATION DELEGATION LOGIC
  // ==========================================
  // Directional inputs are delegated to the active tab component
  // to allow for context-aware navigation patterns (Grid vs List vs Paged).

  void _navigateContentRight() {
    if (_selectedTabIndex == 0) {
      return; // Grid navigation delegated to my_systems.dart via provider.
    }
    if (_selectedTabIndex == 3) {
      NewScraperOptionsScreen.navigateRight();
      return;
    }
    if (_selectedTabIndex == 4) {
      NewSettingsScreen.navigateRight();
      return;
    }
  }

  void _navigateContentLeft() {
    if (_selectedTabIndex == 0) return;
    if (_selectedTabIndex == 3) {
      NewScraperOptionsScreen.navigateLeft();
      return;
    }
    if (_selectedTabIndex == 4) {
      NewSettingsScreen.navigateLeft();
      return;
    }
  }

  void _navigateContentDown() {
    if (_selectedTabIndex == 0) return;
    if (_selectedTabIndex == 3) {
      NewScraperOptionsScreen.navigateDown();
      return;
    }
    if (_selectedTabIndex == 4) {
      NewSettingsScreen.navigateDown();
      return;
    }
  }

  void _navigateContentUp() {
    if (_selectedTabIndex == 0) return;
    if (_selectedTabIndex == 3) {
      NewScraperOptionsScreen.navigateUp();
      return;
    }
    if (_selectedTabIndex == 4) {
      NewSettingsScreen.navigateUp();
      return;
    }
  }

  void _handleSettings() {
    // Context-sensitive settings/secondary-action button handler.
    if (_selectedTabIndex == 0) {
      return;
    }
  }

  void _selectCurrentItem() async {
    if (_selectedTabIndex == 0) return;

    if (_selectedTabIndex == 3) {
      NewScraperOptionsScreen.selectCurrent();
    } else if (_selectedTabIndex == 4) {
      NewSettingsScreen.selectCurrent();
    }
  }


  /// Handles tab selection lifecycle including state updates and UI side-effects.
  ///
  /// With `IndexedStack`-based tab content, switching tabs no longer unmounts
  /// the previous tab. Tab-scoped gamepad layers are managed by each tab via
  /// `TabActiveScope` in `didChangeDependencies` (push when becoming active,
  /// pop when becoming inactive), so AppScreen no longer force-activates its
  /// own GamepadNavigation post-frame — that was the source of double-firing
  /// in the first IndexedStack attempt.
  void _onTabSelected(int index) {
    setState(() {
      _selectedTabIndex = index;
      _visitedTabs.add(index);
    });
    // Reset Console grid selection on tab change. Done outside setState so it
    // doesn't trigger a full AppScreen rebuild — the notifier listeners
    // handle the propagation locally.
    _selectedSystemNotifier.value = 0;

    _updateSecondaryScreenTab(index);
  }

  /// Updates secondary display metadata based on the current active tab.
  void _updateSecondaryScreenTab(int index) {
    if (Platform.isAndroid) {
      final secondaryState = SecondaryDisplayState();
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      final isOled = themeProvider.isOled;

      if (index == 0) {
        return; // System tab manages its own secondary display state.
      }

      String tabName = '';
      switch (index) {
        case 1:
          tabName = 'Sync';
          break;
        case 2:
          tabName = 'Achievements';
          break;
        case 3:
          tabName = 'Scraper';
          break;
        case 4:
          tabName = 'Settings';
          break;
      }

      secondaryState.updateState(
        systemName: tabName,
        useFluidShader: true,
        isOled: isOled,
        backgroundColor: themeProvider.currentTheme.scaffoldBackgroundColor
            .toARGB32(),
        themeName: themeProvider.currentThemeName,
        isGameSelected: false,
        clearSystemLogo: true,
        clearSystemBackground: true,
        clearFanart: true,
        clearScreenshot: true,
        clearWheel: true,
        clearVideo: true,
        clearImageBytes: true,
      );
    }
  }

  void _navigateToNextTab() {
    final nextIndex = (_selectedTabIndex + 1) % _tabCount;
    _onTabSelected(nextIndex);
  }

  void _navigateToPreviousTab() {
    final previousIndex = (_selectedTabIndex - 1 + _tabCount) % _tabCount;
    _onTabSelected(previousIndex);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SelectedSystemIndexNotifier>.value(
      value: _selectedSystemNotifier,
      child: Consumer2<SqliteConfigProvider, ThemeProvider>(
        builder: (context, configProvider, themeProvider, child) {
          final isOled = themeProvider.isOled;

        return PopScope(
          canPop: false, // Intercept hardware back button to maintain app flow.
          child: Scaffold(
            body: Stack(
              children: [
                // Background Layer: Adaptive gradients or pure black for OLED efficiency.
                if (!isOled)
                  Positioned.fill(
                    child: Builder(
                      builder: (context) {
                        final bg = Theme.of(context).scaffoldBackgroundColor;
                        final primary = Theme.of(context).colorScheme.primary;
                        return Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [bg, Color.lerp(bg, primary, 0.1)!],
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else
                  Positioned.fill(
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                  ),

                // Main Content Layer.
                Positioned.fill(child: _buildCurrentTabContent()),

                // Global Header: Managed based on app initialization state.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child:
                      (configProvider.initialized || !configProvider.isLoading)
                      ? FixedHeader(
                          selectedTabIndex: _selectedTabIndex,
                          onTabSelected: _onTabSelected,
                        )
                      : const SizedBox.shrink(),
                ),

                // Global Footer Placeholder.
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child:
                      configProvider.hasRomFolder &&
                          !configProvider.isLoading &&
                          !configProvider.isScanning
                      ? _buildFooterForCurrentTab()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      },
      ),
    );
  }

  Widget _buildFooterForCurrentTab() {
    return const SizedBox.shrink();
  }

  /// Builds a single tab widget on demand. Called only for visited tabs.
  Widget _buildTab(int index) {
    switch (index) {
      case 0:
        return const SystemContent();
      case 1:
        return const NeoSyncTab();
      case 2:
        return const RAContent();
      case 3:
        return const ScraperContent();
      case 4:
        return const NewSettingsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Stack of all top-level tabs. Each tab is wrapped in a `TabActiveScope`
  /// so layer-pushing tabs (MySystems, NeoSyncTab, RAContent) can push/pop
  /// their gamepad layer in sync with visibility. Unvisited tabs render as
  /// zero-sized placeholders until first reach.
  Widget _buildCurrentTabContent() {
    return IndexedStack(
      index: _selectedTabIndex,
      sizing: StackFit.expand,
      children: List.generate(_tabCount, (i) {
        if (!_visitedTabs.contains(i)) {
          return const SizedBox.shrink();
        }
        return TabActiveScope(
          isActive: i == _selectedTabIndex,
          child: _buildTab(i),
        );
      }),
    );
  }
}

/// Inherits `isActive` down the tree. Tab content widgets that own a
/// gamepad-navigation layer read this to push their layer when becoming the
/// visible tab and pop it when another tab takes over. Without this, with
/// `IndexedStack` keeping all visited tabs mounted, layers from previously-
/// visited tabs would accumulate and capture L1/R1 events meant for the
/// currently visible tab.
class TabActiveScope extends InheritedWidget {
  final bool isActive;

  const TabActiveScope({
    super.key,
    required this.isActive,
    required super.child,
  });

  /// Returns whether the nearest enclosing tab is the currently visible one.
  /// Defaults to `true` outside any scope (back-compat for code paths that
  /// don't yet read the scope).
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TabActiveScope>();
    return scope?.isActive ?? true;
  }

  @override
  bool updateShouldNotify(TabActiveScope old) => isActive != old.isActive;
}
