import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:neostation/services/logger_service.dart';
import '../models/retro_achievements_user.dart';
import '../models/retro_achievements_summary.dart';
import '../models/retro_achievements_game_info.dart';
import '../models/retro_achievements_gotw.dart';

/// Service for interacting with the RetroAchievements API.
///
/// Provides access to user profiles, game achievements, and global community
/// events like "Achievement of the Week". Requires a valid API key provided
/// via `--dart-define=RA_API_KEY=...`.
class RetroAchievementsService {
  static const String _baseUrl = 'https://retroachievements.org/API';
  static const String _apiKey = String.fromEnvironment('RA_API_KEY');
  static final _log = LoggerService.instance;

  /// Fetches the "Achievement of the Week" (GOTW) data.
  ///
  /// Optionally takes a [username] to include user-specific progress toward the achievement.
  static Future<RetroAchievementsGOTW?> getAchievementOfTheWeek({
    String? username,
  }) async {
    try {
      final effectiveUsername = username ?? '';
      final effectiveApiKey = _apiKey;

      final url = Uri.parse('$_baseUrl/API_GetAchievementOfTheWeek.php')
          .replace(
            queryParameters: {'u': effectiveUsername, 'y': effectiveApiKey},
          );

      final response = await http.get(
        url,
        headers: {'User-Agent': 'NeoStation/1.0', 'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data['Achievement'] != null) {
          return RetroAchievementsGOTW.fromJson(data);
        } else if (data != null && data['Error'] != null) {
          _log.e('API Error: ${data['Error']}');
        }
      }
      return null;
    } catch (e) {
      _log.e('Exception getting GOTW: $e');
      return null;
    }
  }

  /// Mapping of NeoStation system identifiers to RetroAchievements console IDs.
  static const Map<String, int> _systemMapping = {
    'nes': 7,
    'snes': 3,
    'gb': 4,
    'gbc': 6,
    'gba': 5,
    'n64': 2,
    'gcn': 16,
    'wii': 82,
    'nds': 18,
    '3ds': 78,
    'genesis': 1,
    'sms': 11,
    'gg': 15,
    'saturn': 39,
    'dreamcast': 40,
    'psx': 12,
    'ps2': 21,
    'psp': 41,
    'atari2600': 25,
    'atari7800': 51,
    'lynx': 13,
    'neogeo': 56,
    'arcade': 27,
    'msx': 29,
  };

  /// Returns the RetroAchievements console ID for a given NeoStation system name.
  static int? getConsoleIdForSystem(String systemFolderName) {
    return _systemMapping[systemFolderName.toLowerCase()];
  }

  /// Retrieves basic profile information for a RetroAchievements user.
  static Future<RetroAchievementsUser?> getUserProfile(String username) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/API_GetUserProfile.php',
      ).replace(queryParameters: {'u': username, 'y': _apiKey});

      final response = await http.get(
        url,
        headers: {'User-Agent': 'NeoStation/1.0', 'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['User'] != null) {
          return RetroAchievementsUser.fromJson(data);
        } else {
          _log.e('User not found: $username');
          return null;
        }
      } else {
        _log.e('HTTP error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      _log.e('Error getting user profile: $e');
      return null;
    }
  }

  /// Checks if a username is registered on RetroAchievements.
  static Future<bool> userExists(String username) async {
    final user = await getUserProfile(username);
    return user != null;
  }

  /// Fetches a comprehensive summary for a user, including recent games and achievements.
  ///
  /// Employs a cache-busting timestamp to ensure fresh data.
  static Future<RetroAchievementsUserSummary?> getUserSummary(
    String username,
  ) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse('$_baseUrl/API_GetUserSummary.php').replace(
        queryParameters: {
          'u': username,
          'g': '1', // Include recent games
          'a': '2', // Include recent achievements
          'y': _apiKey,
          '_t': timestamp.toString(),
        },
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'NeoStation/1.0',
          'Accept': 'application/json',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is Map && data['User'] != null) {
          return RetroAchievementsUserSummary.fromJson(
            data as Map<String, dynamic>,
          );
        } else if (data is List) {
          if (data.isNotEmpty && data.first is Map) {
            final userData = data.first as Map<String, dynamic>;
            if (userData['User'] != null) {
              return RetroAchievementsUserSummary.fromJson(userData);
            }
          }
          _log.e('Unexpected response: list without valid data');
          return null;
        } else {
          _log.e('User not found or invalid response: $username');
          return null;
        }
      } else {
        _log.e('HTTP error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      _log.e('Error getting user summary: $e');
      return null;
    }
  }

  /// Retrieves detailed information for a specific game and the user's progress.
  ///
  /// Can take an [md5Hash] for more accurate game identification within the RA database.
  static Future<GameInfoAndUserProgress?> getGameInfoAndUserProgress(
    int gameId,
    String username, {
    String? md5Hash,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final queryParams = {
        'g': gameId.toString(),
        'u': username,
        'y': _apiKey,
        'a': '1', // Include achievements
        '_t': timestamp.toString(),
      };

      if (md5Hash != null && md5Hash.isNotEmpty) {
        queryParams['m'] = md5Hash;
      }

      final url = Uri.parse(
        '$_baseUrl/API_GetGameInfoAndUserProgress.php',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'NeoStation/1.0',
          'Accept': 'application/json',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['ID'] != null) {
          return GameInfoAndUserProgress.fromJson(data);
        } else {
          _log.e('Game not found: $gameId');
          return null;
        }
      } else {
        _log.e('HTTP error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      _log.e('Error getting game information: $e');
      return null;
    }
  }

  /// Resolves a game's information and user progress using a file hash.
  static Future<GameInfoAndUserProgress?> searchGameByHash(
    String md5Hash,
    String username,
  ) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse('$_baseUrl/API_GetGameInfoAndUserProgress.php')
          .replace(
            queryParameters: {
              'm': md5Hash,
              'u': username,
              'y': _apiKey,
              'a': '1',
              '_t': timestamp.toString(),
            },
          );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'NeoStation/1.0',
          'Accept': 'application/json',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['ID'] != null) {
          return GameInfoAndUserProgress.fromJson(data);
        } else {
          _log.e('Game not found with hash: $md5Hash');
          return null;
        }
      } else {
        _log.e('HTTP error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      _log.e('Error searching game by hash: $e');
      return null;
    }
  }

  static const String apiGetUserAwards = 'API_GetUserAwards.php';

  /// Retrieves the list of site-wide awards earned by a user.
  static Future<Map<String, dynamic>?> getUserAwards(String username) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse('$_baseUrl/$apiGetUserAwards').replace(
        queryParameters: {
          'u': username,
          'y': _apiKey,
          '_t': timestamp.toString(),
        },
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'NeoStation/1.0',
          'Accept': 'application/json',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        return data as Map<String, dynamic>;
      } else {
        _log.e('HTTP error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      _log.e('Error getting user awards: $e');
      return null;
    }
  }

  /// Searches for games by name within a specific console category.
  ///
  /// Performs normalized string matching (removing special characters and
  /// excessive whitespace) to improve discovery.
  static Future<List<Map<String, dynamic>>> searchGamesByName(
    String gameName,
    int consoleId,
  ) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/API_GetGameList.php',
      ).replace(queryParameters: {'i': consoleId.toString(), 'y': _apiKey});

      final response = await http.get(
        url,
        headers: {'User-Agent': 'NeoStation/1.0', 'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is List) {
          final normalizedSearchName = gameName
              .toLowerCase()
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

          final matches = <Map<String, dynamic>>[];

          for (final game in data) {
            final gameTitle = game['Title']?.toString() ?? '';
            final normalizedGameTitle = gameTitle
                .toLowerCase()
                .replaceAll(RegExp(r'[^\w\s]'), '')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();

            if (normalizedGameTitle == normalizedSearchName ||
                normalizedGameTitle.contains(normalizedSearchName) ||
                normalizedSearchName.contains(normalizedGameTitle)) {
              matches.add(game);
            }
          }

          return matches;
        }
      } else {
        _log.e('HTTP error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _log.e('Error searching games: $e');
    }

    return [];
  }
}
