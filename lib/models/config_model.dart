import 'emulator_model.dart';

/// Represents the global application configuration and user preferences.
class ConfigModel {
  /// List of absolute paths to directories containing game ROMs.
  final List<String> romFolders;

  /// List of platform identifiers for the emulated systems detected during the last scan.
  final List<String> detectedSystems;

  /// Timestamp of the last successful ROM folder synchronization.
  final DateTime? lastScan;

  /// Map of emulator configurations, keyed by their unique identifier.
  final Map<String, EmulatorModel> emulators;

  /// Preferred display mode for the game list (e.g., 'list', 'grid', 'carousel').
  final String gameViewMode;

  /// Preferred display mode for the system list (e.g., 'grid', 'list').
  final String systemViewMode;

  /// Identifier of the currently active UI theme.
  final String themeName;

  /// Whether to display detailed game metadata by default.
  final bool showGameInfo;

  /// Whether to display the per-game wheel logo overlay on the games page.
  final bool showGameWheel;

  /// Delay before the video preview starts when navigating between games (ms).
  ///
  /// Range is enforced to `[500, 3000]` at every layer (model parse,
  /// provider update, datasource load) to be defensive against bad DB values.
  final int videoDelayMs;

  /// Whether the application should run in exclusive fullscreen mode.
  final bool isFullscreen;

  /// Whether the device should shut down immediately upon exiting the application (optimized for bartop/cabinets).
  final bool bartopExitPoweroff;

  /// Whether to automatically trigger a ROM scan when the application starts.
  final bool scanOnStartup;

  /// Whether the initial onboarding/setup process has been finished.
  final bool setupCompleted;

  /// Whether to hide the secondary screen interface (useful for dual-monitor setups).
  final bool hideBottomScreen;

  /// Whether to play background audio/music from game preview videos.
  final bool videoSound;

  /// Whether UI sound effects (navigation, clicks) are enabled.
  final bool sfxEnabled;

  /// The property used to sort the system list (e.g., 'alphabetical', 'release_year').
  final String systemSortBy;

  /// The sort direction for the system list ('asc' or 'desc').
  final String systemSortOrder;

  /// The ISO language code for the application interface (e.g., 'en', 'es').
  final String appLanguage;

  /// Whether to hide the "Recently Played" card from the main dashboard.
  final bool hideRecentCard;

  /// Whether to hide the "Recently Played" virtual system from the system grid.
  final bool hideRecentSystem;

  /// ID of the active sync provider (matches [ISyncProvider.providerId]).
  final String activeSyncProvider;

  const ConfigModel({
    this.romFolders = const [],
    this.detectedSystems = const [],
    this.lastScan,
    this.emulators = const {},
    this.gameViewMode = 'list',
    this.systemViewMode = 'grid',
    this.themeName = 'system',
    this.showGameInfo = false,
    this.showGameWheel = true,
    this.videoDelayMs = 1500,
    this.isFullscreen = true,
    this.bartopExitPoweroff = false,
    this.scanOnStartup = true,
    this.setupCompleted = false,
    this.hideBottomScreen = false,
    this.videoSound = false,
    this.sfxEnabled = true,
    this.systemSortBy = 'alphabetical',
    this.systemSortOrder = 'asc',
    this.appLanguage = 'es',
    this.hideRecentCard = false,
    this.hideRecentSystem = false,
    this.activeSyncProvider = 'neosync',
  });

  /// Convenience getter that returns the primary ROM folder, if any are configured.
  String? get romFolder => romFolders.isNotEmpty ? romFolders.first : null;

  /// Creates a [ConfigModel] from a JSON-compatible map.
  factory ConfigModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> emulatorsJson;
    if (json['emulators'] is Map) {
      emulatorsJson = Map<String, dynamic>.from(json['emulators']);
    } else {
      emulatorsJson = {};
    }

    final emulators = <String, EmulatorModel>{};

    for (final entry in emulatorsJson.entries) {
      if (entry.value is Map) {
        emulators[entry.key.toString()] = EmulatorModel.fromJson(
          entry.key.toString(),
          Map<String, dynamic>.from(entry.value),
        );
      }
    }

    return ConfigModel(
      romFolders:
          (json['romFolders'] as List?)?.map((e) => e.toString()).toList() ??
          [],
      detectedSystems:
          (json['detectedSystems'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      lastScan: json['lastScan'] != null
          ? DateTime.tryParse(json['lastScan'].toString())
          : null,
      emulators: emulators,
      gameViewMode: (json['gameViewMode'] ?? 'list').toString(),
      systemViewMode: (json['systemViewMode'] ?? 'grid').toString(),
      themeName: (json['themeName'] ?? 'system').toString(),
      showGameInfo:
          (json['showGameInfo'] ?? false).toString().toLowerCase() == 'true',
      showGameWheel: _parseBool(
        json['showGameWheel'] ?? json['show_game_wheel'],
        defaultValue: true,
      ),
      videoDelayMs: _parseClampedInt(
        json['videoDelayMs'] ?? json['video_delay_ms'],
        defaultValue: 1500,
        min: 500,
        max: 3000,
      ),
      isFullscreen:
          (json['isFullscreen'] ?? true).toString().toLowerCase() == 'true',
      bartopExitPoweroff:
          (json['bartopExitPoweroff'] ?? false).toString().toLowerCase() ==
          'true',
      scanOnStartup:
          (json['scanOnStartup'] ?? true).toString().toLowerCase() == 'true',
      setupCompleted:
          (json['setupCompleted'] ?? false).toString().toLowerCase() ==
              'true' ||
          (json['setup_completed'] ?? false).toString().toLowerCase() == 'true',
      hideBottomScreen:
          (json['hideBottomScreen'] ?? false).toString().toLowerCase() ==
          'true',
      videoSound:
          (json['videoSound'] ?? false).toString().toLowerCase() == 'true' ||
          (json['video_sound'] ?? 0).toString() == '1' ||
          (json['video_sound'] ?? 'off').toString() == 'on',
      sfxEnabled:
          (json['sfxEnabled'] ?? true).toString().toLowerCase() == 'true' ||
          (json['sfx_enabled'] ?? 1).toString() == '1',
      systemSortBy:
          (json['systemSortBy'] ?? json['system_sort_by'] ?? 'alphabetical')
              .toString(),
      systemSortOrder:
          (json['systemSortOrder'] ?? json['system_sort_order'] ?? 'asc')
              .toString(),
      appLanguage: (json['appLanguage'] ?? json['app_language'] ?? 'en')
          .toString(),
      hideRecentCard:
          (json['hideRecentCard'] ?? json['hide_recent_card'] ?? 0)
                  .toString() ==
              '1' ||
          (json['hideRecentCard'] ?? false).toString().toLowerCase() == 'true',
      hideRecentSystem:
          (json['hideRecentSystem'] ?? json['hide_recent_system'] ?? 0)
                  .toString() ==
              '1' ||
          (json['hideRecentSystem'] ?? false).toString().toLowerCase() ==
              'true',
      activeSyncProvider:
          (json['activeSyncProvider'] ??
                  json['active_sync_provider'] ??
                  'neosync')
              .toString(),
    );
  }

  /// Converts the configuration model into a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final emulatorsJson = <String, dynamic>{};
    for (final entry in emulators.entries) {
      emulatorsJson[entry.key] = entry.value.toJson();
    }

    return {
      'romFolders': romFolders,
      'detectedSystems': detectedSystems,
      if (lastScan != null) 'lastScan': lastScan!.toIso8601String(),
      'emulators': emulatorsJson,
      'gameViewMode': gameViewMode,
      'systemViewMode': systemViewMode,
      'themeName': themeName,
      'showGameInfo': showGameInfo,
      'showGameWheel': showGameWheel,
      'videoDelayMs': videoDelayMs,
      'isFullscreen': isFullscreen,
      'bartopExitPoweroff': bartopExitPoweroff,
      'scanOnStartup': scanOnStartup,
      'setupCompleted': setupCompleted,
      'hideBottomScreen': hideBottomScreen,
      'videoSound': videoSound,
      'sfxEnabled': sfxEnabled,
      'systemSortBy': systemSortBy,
      'systemSortOrder': systemSortOrder,
      'appLanguage': appLanguage,
      'hideRecentCard': hideRecentCard,
      'hideRecentSystem': hideRecentSystem,
      'activeSyncProvider': activeSyncProvider,
    };
  }

  /// Returns a new [ConfigModel] with updated fields.
  ConfigModel copyWith({
    List<String>? romFolders,
    List<String>? detectedSystems,
    DateTime? lastScan,
    Map<String, EmulatorModel>? emulators,
    String? gameViewMode,
    String? systemViewMode,
    String? themeName,
    bool? showGameInfo,
    bool? showGameWheel,
    int? videoDelayMs,
    bool? isFullscreen,
    bool? bartopExitPoweroff,
    bool? scanOnStartup,
    bool? setupCompleted,
    bool? hideBottomScreen,
    bool? videoSound,
    bool? sfxEnabled,
    String? systemSortBy,
    String? systemSortOrder,
    String? appLanguage,
    bool? hideRecentCard,
    bool? hideRecentSystem,
    String? activeSyncProvider,
  }) {
    return ConfigModel(
      romFolders: romFolders ?? this.romFolders,
      detectedSystems: detectedSystems ?? this.detectedSystems,
      lastScan: lastScan ?? this.lastScan,
      emulators: emulators ?? this.emulators,
      gameViewMode: gameViewMode ?? this.gameViewMode,
      systemViewMode: systemViewMode ?? this.systemViewMode,
      themeName: themeName ?? this.themeName,
      showGameInfo: showGameInfo ?? this.showGameInfo,
      showGameWheel: showGameWheel ?? this.showGameWheel,
      videoDelayMs: videoDelayMs ?? this.videoDelayMs,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      bartopExitPoweroff: bartopExitPoweroff ?? this.bartopExitPoweroff,
      scanOnStartup: scanOnStartup ?? this.scanOnStartup,
      setupCompleted: setupCompleted ?? this.setupCompleted,
      hideBottomScreen: hideBottomScreen ?? this.hideBottomScreen,
      videoSound: videoSound ?? this.videoSound,
      sfxEnabled: sfxEnabled ?? this.sfxEnabled,
      systemSortBy: systemSortBy ?? this.systemSortBy,
      systemSortOrder: systemSortOrder ?? this.systemSortOrder,
      appLanguage: appLanguage ?? this.appLanguage,
      hideRecentCard: hideRecentCard ?? this.hideRecentCard,
      hideRecentSystem: hideRecentSystem ?? this.hideRecentSystem,
      activeSyncProvider: activeSyncProvider ?? this.activeSyncProvider,
    );
  }

  /// Static instance representing a default, empty configuration.
  static const empty = ConfigModel();

  /// Parses a JSON value into a bool, handling camelCase/snake_case payloads
  /// that mix string/int/bool representations.
  static bool _parseBool(dynamic raw, {required bool defaultValue}) {
    if (raw == null) return defaultValue;
    if (raw is bool) return raw;
    final s = raw.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  /// Parses a JSON value into an int and clamps to `[min, max]`. Returns
  /// [defaultValue] if the value is null or unparseable.
  static int _parseClampedInt(
    dynamic raw, {
    required int defaultValue,
    required int min,
    required int max,
  }) {
    if (raw == null) return defaultValue;
    final parsed = raw is int ? raw : int.tryParse(raw.toString());
    if (parsed == null) return defaultValue;
    return parsed.clamp(min, max);
  }

  @override
  String toString() {
    return 'ConfigModel(romFolders: ${romFolders.length}, detectedSystems: ${detectedSystems.length}, emulators: ${emulators.length}, showGameInfo: $showGameInfo, showGameWheel: $showGameWheel, videoDelayMs: $videoDelayMs, isFullscreen: $isFullscreen, bartopExitPoweroff: $bartopExitPoweroff, scanOnStartup: $scanOnStartup, setupCompleted: $setupCompleted, hideBottomScreen: $hideBottomScreen, videoSound: $videoSound)';
  }
}
