import 'package:shared_preferences/shared_preferences.dart';
import 'package:neostation/services/logger_service.dart';

/// Service responsible for persisting game session state across application restarts.
///
/// Primarily used on Android to ensure that playtime can be recovered even if the
/// OS terminates the application process while an emulator is running.
class GameSessionPersistence {
  static const String _keyGameActive = 'game_session_active';
  static const String _keySystemFolderName = 'game_session_system_folder';
  static const String _keyFilename = 'game_session_filename';
  static const String _keyStartTimestamp = 'game_session_start_timestamp';

  static final _log = LoggerService.instance;

  /// Persists the initiation of a new game session.
  static Future<void> saveGameSession({
    required String systemFolderName,
    required String filename,
    required int startTimestamp,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyGameActive, true);
      await prefs.setString(_keySystemFolderName, systemFolderName);
      await prefs.setString(_keyFilename, filename);
      await prefs.setInt(_keyStartTimestamp, startTimestamp);
    } catch (e) {
      _log.e('Error saving game session: $e');
    }
  }

  /// Retrieves the active game session metadata if a session was previously flagged as active.
  ///
  /// Returns null if no active session is found or if the persisted data is incomplete.
  static Future<Map<String, dynamic>?> getActiveGameSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive = prefs.getBool(_keyGameActive) ?? false;

      if (!isActive) return null;

      final systemFolderName = prefs.getString(_keySystemFolderName);
      final filename = prefs.getString(_keyFilename);
      final startTimestamp = prefs.getInt(_keyStartTimestamp);

      if (systemFolderName == null ||
          filename == null ||
          startTimestamp == null) {
        return null;
      }

      return {
        'systemFolderName': systemFolderName,
        'filename': filename,
        'startTimestamp': startTimestamp,
      };
    } catch (e) {
      _log.e('Error reading game session: $e');
      return null;
    }
  }

  /// Purges all persisted game session metadata from shared preferences.
  static Future<void> clearGameSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyGameActive);
      await prefs.remove(_keySystemFolderName);
      await prefs.remove(_keyFilename);
      await prefs.remove(_keyStartTimestamp);
    } catch (e) {
      _log.e('Error clearing game session: $e');
    }
  }

  /// Checks if an active session flag exists without reading the full metadata.
  static Future<bool> hasActiveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyGameActive) ?? false;
    } catch (e) {
      return false;
    }
  }
}
