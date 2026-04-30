import 'package:flutter/foundation.dart';
import 'package:neostation/services/logger_service.dart';
import '../models/retro_achievements_user.dart';
import '../models/retro_achievements_summary.dart';
import '../services/retro_achievements_service.dart';
import '../repositories/retro_achievements_repository.dart';
import '../models/retro_achievements_game_info.dart';
import '../models/retro_achievements_gotw.dart';
import '../models/retro_achievements_user_awards.dart';
import 'retroachievements/strategy_factory.dart';

/// Provider responsible for managing the integration with RetroAchievements.org.
///
/// Handles user authentication, profile synchronization, achievement progress
/// tracking, and ROM identification via console-specific hashing algorithms.
class RetroAchievementsProvider extends ChangeNotifier {
  /// Basic profile information for the authenticated user.
  RetroAchievementsUser? _user;

  /// Whether a data retrieval task is currently in progress.
  bool _isLoading = false;

  /// Whether a successful connection has been established with the API.
  bool _isConnected = false;

  /// Last error message encountered during API interactions.
  String? _error;

  /// Current authenticated username.
  String _username = '';

  static final _log = LoggerService.instance;

  /// Whether a ROM scanning process for RA compatibility is active.
  bool _isScanning = false;

  /// Normalized progress of the ROM scan (0.0 to 1.0).
  final double _scanProgress = 0.0;

  /// Human-readable status message for the scan operation.
  String _scanStatus = '';

  /// Total number of ROMs identified for the scan.
  final int _totalRoms = 0;

  /// Count of ROMs processed in the current scan.
  final int _processedRoms = 0;

  /// Count of ROMs that were successfully identified as RA-compatible.
  final int _retroAchievementsCompatibleRoms = 0;

  /// History of identifiers processed in the current scanning session.
  final List<String> _processedItems = [];

  /// Total count of ROMs in the user's local database.
  int _totalLocalRoms = 0;

  /// Count of local ROMs that have a valid RA hash.
  int _retroAchievementsCompatibleLocalRoms = 0;

  /// Whether local statistics have been successfully computed.
  bool _localStatsLoaded = false;

  /// Full user summary including recent activity and badges.
  RetroAchievementsUserSummary? _userSummary;

  /// Whether the full user summary has been loaded.
  bool _summaryLoaded = false;

  /// Memory cache for detailed game metadata and user progress, keyed by Game ID.
  final Map<int, GameInfoAndUserProgress> _gameInfoCache = {};

  /// Mapping of game titles to their corresponding RetroAchievements Game IDs.
  final Map<String, int> _gameIdMapping = {};

  /// Current "Game of the Week" metadata.
  RetroAchievementsGOTW? _gotw;

  /// Whether the GOTW metadata has been loaded.
  bool _gotwLoaded = false;

  /// List of special awards and site badges earned by the user.
  RetroAchievementsUserAwards? _userAwards;

  /// Whether the user awards have been loaded.
  bool _userAwardsLoaded = false;

  // Getters
  RetroAchievementsUser? get user => _user;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  String? get error => _error;
  String get username => _username;

  bool get isScanning => _isScanning;
  double get scanProgress => _scanProgress;
  String get scanStatus => _scanStatus;
  int get totalRoms => _totalRoms;
  int get processedRoms => _processedRoms;
  int get retroAchievementsCompatibleRoms => _retroAchievementsCompatibleRoms;
  List<String> get processedItems => _processedItems;

  int get totalLocalRoms => _totalLocalRoms;
  int get retroAchievementsCompatibleLocalRoms =>
      _retroAchievementsCompatibleLocalRoms;
  bool get localStatsLoaded => _localStatsLoaded;

  RetroAchievementsUserSummary? get userSummary => _userSummary;
  bool get summaryLoaded => _summaryLoaded;

  Map<int, GameInfoAndUserProgress> get gameInfoCache => _gameInfoCache;
  Map<String, int> get gameIdMapping => _gameIdMapping;

  RetroAchievementsGOTW? get gotw => _gotw;
  bool get gotwLoaded => _gotwLoaded;

  RetroAchievementsUserAwards? get userAwards => _userAwards;
  bool get userAwardsLoaded => _userAwardsLoaded;

  /// Authenticates with RetroAchievements using the specified username.
  ///
  /// Upon successful connection, it persists the credentials for auto-login
  /// and triggers a background fetch of user statistics, summaries, and awards.
  Future<bool> connect(String username) async {
    if (username.trim().isEmpty) {
      _error = 'Please enter a username';
      notifyListeners();
      return false;
    }

    _setLoading(true);
    _error = null;
    _username = username.trim();

    try {
      final userProfile = await RetroAchievementsService.getUserProfile(
        _username,
      );

      if (userProfile != null) {
        _user = userProfile;
        _isConnected = true;

        await _saveRAUserToConfig(_username);
        await loadLocalStats();
        await loadUserSummary();
        await fetchUserAwards();

        notifyListeners();
        return true;
      } else {
        _error = 'User not found on RetroAchievements';
        _isConnected = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Error connecting to RetroAchievements: $e';
      _isConnected = false;
      _log.e('$_error');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Refreshes the full user summary, including recent achievements and active game list.
  Future<bool> loadUserSummary() async {
    if (!_isConnected || _username.isEmpty) {
      _error = 'User not connected';
      notifyListeners();
      return false;
    }

    _setLoading(true);
    _error = null;

    try {
      final summary = await RetroAchievementsService.getUserSummary(_username);

      if (summary != null) {
        _userSummary = summary;
        _summaryLoaded = true;
        await fetchUserAwards();
        notifyListeners();
        return true;
      } else {
        _error = 'User summary could not be loaded';
        _summaryLoaded = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Error loading user summary: $e';
      _summaryLoaded = false;
      _log.e('$_error');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Fetches metadata for the current site-wide "Game of the Week".
  Future<bool> fetchGOTW() async {
    _error = null;
    _setLoading(true);

    try {
      final gotw = await RetroAchievementsService.getAchievementOfTheWeek(
        username: _user?.user,
      );

      if (gotw != null) {
        _gotw = gotw;
        _gotwLoaded = true;
        notifyListeners();
        return true;
      } else {
        _log.w('fetchAOTW returned null');
        _gotwLoaded = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _log.e('Error loading achievement of the week: $e');
      _gotwLoaded = false;
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Fetches the user's earned badges and awards from the API.
  Future<bool> fetchUserAwards() async {
    if (!_isConnected || _username.isEmpty) return false;

    try {
      final awardsData = await RetroAchievementsService.getUserAwards(
        _username,
      );
      if (awardsData != null) {
        _userAwards = RetroAchievementsUserAwards.fromJson(awardsData);
        _userAwardsLoaded = true;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _log.e('Error loading user awards: $e');
      _userAwardsLoaded = false;
      return false;
    }
  }

  /// Retrieves detailed information for a game and the current user's achievement progress.
  ///
  /// Leverages an internal cache to avoid redundant network calls.
  /// The [md5Hash] parameter is used for precise identification of ROM versions.
  Future<GameInfoAndUserProgress?> getGameInfoAndUserProgress(
    int gameId, {
    bool forceRefresh = false,
    String? md5Hash,
  }) async {
    if (!_isConnected || _username.isEmpty) {
      _error = 'User not connected';
      return null;
    }

    if (forceRefresh && _gameInfoCache.containsKey(gameId)) {
      _gameInfoCache.remove(gameId);
    }

    if (!forceRefresh && _gameInfoCache.containsKey(gameId)) {
      return _gameInfoCache[gameId];
    }

    _error = null;

    try {
      final gameInfo =
          await RetroAchievementsService.getGameInfoAndUserProgress(
            gameId,
            _username,
            md5Hash: md5Hash,
          );

      if (gameInfo != null) {
        _gameInfoCache[gameId] = gameInfo;
        return gameInfo;
      } else {
        _error = 'Game information could not be loaded';
        return null;
      }
    } catch (e) {
      _error = 'Error loading game information: $e';
      _log.e('$_error');
      return null;
    }
  }

  /// Initializes the provider and attempts automatic login with stored credentials.
  Future<void> initialize() async {
    try {
      await tryAutoLogin();
      await fetchGOTW();
    } catch (e) {
      _log.e('Error initializing RA: $e');
    }
  }

  /// Attempts to re-authenticate using the username persisted in the local configuration.
  Future<bool> tryAutoLogin() async {
    try {
      final savedUsername = await _loadRAUserFromConfig();

      if (savedUsername != null && savedUsername.isNotEmpty) {
        final success = await connect(savedUsername);
        if (!success) {
          _log.e(
            'Auto-login failed for: $savedUsername (user preserved for retry)',
          );
        }
        return success;
      } else {
        return false;
      }
    } catch (e) {
      _log.e('Error loading user: $e (user preserved for retry)');
    }
    return false;
  }

  /// Clears the current user session and memory state.
  ///
  /// If [clearSavedUser] is true, the credentials are removed from persistent storage.
  void disconnect({bool clearSavedUser = true}) {
    _user = null;
    _isConnected = false;
    _username = '';
    _error = null;
    _userSummary = null;
    _summaryLoaded = false;

    if (clearSavedUser) {
      _clearRAUserFromConfig();
    }

    notifyListeners();
  }

  /// Calculates the RetroAchievements-specific hash for a given ROM file.
  Future<String?> calculateRomRAHash(String filePath, String? systemId) async {
    return await _calculateRAHash(filePath, systemId);
  }

  /// Internal logic to dispatch hash calculation to the appropriate platform strategy.
  Future<String?> _calculateRAHash(String filePath, String? systemId) async {
    try {
      final strategy = RetroAchievementsStrategyFactory.getStrategy(systemId);
      return await strategy.calculateHash(filePath);
    } catch (e) {
      _log.e('Error calculating RA hash for $filePath: $e');
      return null;
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Interrupts an active ROM scanning operation.
  void stopScanning() {
    _isScanning = false;
    _scanStatus = 'Scan stopped by user';
    notifyListeners();
  }

  /// Loads ROM statistics (total count and RA-compatible count) from the local database.
  Future<void> loadLocalStats() async {
    try {
      final stats = await RetroAchievementsRepository.getLocalRomStats();
      _totalLocalRoms = stats.totalRoms;
      _retroAchievementsCompatibleLocalRoms = stats.raCompatibleRoms;
      _localStatsLoaded = true;
      notifyListeners();
    } catch (e) {
      _log.e('Error loading local stats: $e');
      _localStatsLoaded = false;
      notifyListeners();
    }
  }

  /// Resets the current error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Persists the RetroAchievements username to the local user configuration table.
  Future<void> _saveRAUserToConfig(String username) async {
    try {
      await RetroAchievementsRepository.saveRAUser(username);
    } catch (e) {
      _log.e('Error saving RA user: $e');
    }
  }

  /// Retrieves the persisted RetroAchievements username from the configuration table.
  Future<String?> _loadRAUserFromConfig() async {
    try {
      return await RetroAchievementsRepository.getRAUser();
    } catch (e) {
      _log.e('Error loading RA user from DB: $e');
    }
    return null;
  }

  /// Removes the RetroAchievements username from persistent storage.
  Future<void> _clearRAUserFromConfig() async {
    try {
      await RetroAchievementsRepository.clearRAUser();
    } catch (e) {
      _log.e('Error clearing RA user: $e');
    }
  }
}
