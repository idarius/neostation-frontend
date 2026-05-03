import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:neostation/repositories/system_repository.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:neostation/services/config_service.dart';
import 'package:neostation/services/logger_service.dart';

/// Provider responsible for abstracting filesystem access across Android and Desktop platforms.
///
/// Handles resolution of system-specific paths for user data, game media
/// (screenshots, videos), and localized assets. Implements smart ROM extension
/// stripping and standardizes I/O operations.
class FileProvider extends ChangeNotifier {
  /// Default folder name for internal user configuration and database.
  static const String userDataFolder = 'user-data';

  /// Default folder name for game artwork and media assets.
  static const String mediaFolder = 'media';

  /// Subfolder name for game preview videos.
  static const String videosFolder = 'videos';

  /// Subfolder name for game screenshots.
  static const String screenshotsFolder = 'screenshots';

  static final _log = LoggerService.instance;

  /// Absolute path to the user-data directory.
  String? _userDataPath;

  /// Absolute path to the root media directory.
  String? _mediaPath;

  /// Absolute path to the user's standard Documents directory.
  String? _documentsPath;

  /// Whether the provider has finished resolving all platform-specific paths.
  bool _isInitialized = false;

  /// Cached map of supported file extensions per system, loaded from the database.
  Map<String, Set<String>> _systemExtensions = {};

  // Getters
  String? get userDataPath => _userDataPath;
  String? get mediaPath => _mediaPath;
  String? get documentsPath => _documentsPath;
  bool get isInitialized => _isInitialized;

  /// Resolves physical filesystem paths based on the current operating system.
  ///
  /// On Android, prioritizes Scoped Storage directories and internal app support paths.
  /// On Desktop, uses paths provided by [ConfigService] or current working directory fallbacks.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final appSupportDir = await getApplicationSupportDirectory();
        _documentsPath = appSupportDir.path;
        _userDataPath = appSupportDir.path;

        if (Platform.isAndroid) {
          final userDataPath = await ConfigService.getUserDataPath();
          _mediaPath = userDataPath;
        } else {
          _mediaPath = appSupportDir.path;
        }
      } else {
        final userDataPath = await ConfigService.getUserDataPath();
        final userDataDir = Directory(userDataPath);
        _userDataPath = userDataDir.path;

        final fullMediaPath = await ConfigService.getMediaPath();
        _mediaPath = path.dirname(fullMediaPath);

        _documentsPath = path.dirname(userDataDir.path);
      }

      // Ensure directory structures exist.
      if (_userDataPath != null) {
        final userDataDir = Directory(_userDataPath!);
        if (!await userDataDir.exists()) {
          await userDataDir.create(recursive: true);
        }
      }

      if (_mediaPath != null) {
        final mediaDir = Directory(_mediaPath!);
        if (!await mediaDir.exists()) {
          await mediaDir.create(recursive: true);
        }
      }

      _systemExtensions = await SystemRepository.getSystemExtensionsMap();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _log.e('FileProvider: Error initializing: $e');
      _userDataPath = null;
      _mediaPath = null;
      _documentsPath = null;
      _isInitialized = false;
      notifyListeners();
    }
  }

  /// Sanitizes a ROM filename by stripping its extension.
  ///
  /// Implements a multi-stage logic to prevent false positives:
  /// 1. Checks against the database-backed system extension whitelist.
  /// 2. Preserves version-like strings (e.g., '.v1').
  /// 3. Checks against common ROM extensions.
  /// 4. Fallback for short, non-spaced substrings following the final dot.
  String _stripRomExtension(String romName, [String? systemFolderName]) {
    if (!romName.contains('.')) return romName;

    final lastDot = romName.lastIndexOf('.');
    final ext = romName.substring(lastDot + 1).toLowerCase();

    if (systemFolderName != null &&
        _systemExtensions.containsKey(systemFolderName)) {
      final validExtensions = _systemExtensions[systemFolderName]!;
      if (validExtensions.contains(ext)) {
        return romName.substring(0, lastDot);
      }
    }

    final isVersion =
        RegExp(r'^\d+$').hasMatch(ext) || RegExp(r'^v\d+').hasMatch(ext);

    if (isVersion) return romName;

    const commonRomExts = {
      'zip',
      '7z',
      'rar',
      'iso',
      'bin',
      'cue',
      'chd',
      'nes',
      'sfc',
      'smc',
      'gba',
      'gbc',
      'gb',
      'nsp',
      'xci',
      'nca',
      'nro',
      'nso',
      'rvz',
      'wbfs',
      'gcm',
      'rpx',
    };
    if (commonRomExts.contains(ext)) {
      return romName.substring(0, lastDot);
    }

    if (ext.length <= 4 && !ext.contains(' ')) {
      return romName.substring(0, lastDot);
    }

    return romName;
  }

  /// Resolves the absolute path for a game's preview video.
  String getVideoPath(String systemFolderName, String romName) {
    final baseName = _stripRomExtension(romName, systemFolderName);

    if (!_isInitialized || _mediaPath == null) {
      return path.join(
        mediaFolder,
        systemFolderName,
        videosFolder,
        '$baseName.mp4',
      );
    }
    return path.join(
      _mediaPath!,
      mediaFolder,
      systemFolderName,
      videosFolder,
      '$baseName.mp4',
    );
  }

  /// Resolves the absolute path for a game's screenshot.
  String getScreenshotPath(String systemFolderName, String romName) {
    final baseName = _stripRomExtension(romName, systemFolderName);

    if (!_isInitialized || _mediaPath == null) {
      return path.join(
        mediaFolder,
        systemFolderName,
        screenshotsFolder,
        '$baseName.png',
      );
    }
    return path.join(
      _mediaPath!,
      mediaFolder,
      systemFolderName,
      screenshotsFolder,
      '$baseName.png',
    );
  }

  /// Resolves the absolute path for any specific media type and extension.
  String getMediaPath(
    String systemFolderName,
    String imageType,
    String romName,
    String extension,
  ) {
    final baseName = _stripRomExtension(romName, systemFolderName);

    if (!_isInitialized || _mediaPath == null) {
      return path.join(
        mediaFolder,
        systemFolderName,
        imageType,
        '$baseName.$extension',
      );
    }
    return path.join(
      _mediaPath!,
      mediaFolder,
      systemFolderName,
      imageType,
      '$baseName.$extension',
    );
  }

  /// Joins a relative path with the absolute user-data directory.
  String getAbsolutePath(String relativePath) {
    if (!_isInitialized || _userDataPath == null) {
      return path.join(userDataFolder, relativePath);
    }
    return path.join(_userDataPath!, relativePath);
  }

  /// Resolves the expected internal path for a ROM file.
  String getRomPath(String systemFolderName, String romName) {
    if (!_isInitialized || _userDataPath == null) {
      return path.join(
        userDataFolder,
        'roms',
        systemFolderName,
        '$romName.zip',
      );
    }
    return path.join(_userDataPath!, 'roms', systemFolderName, '$romName.zip');
  }

  /// Checks if a file exists asynchronously.
  Future<bool> fileExists(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      _log.e('Error checking file existence $filePath: $e');
      return false;
    }
  }

  /// Recursively creates the parent directories for a given file path if they do not exist.
  Future<void> ensureDirectoryExists(String filePath) async {
    try {
      final directory = Directory(path.dirname(filePath));
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    } catch (e) {
      _log.e('Error creating directory for $filePath: $e');
    }
  }

  /// Returns a list of all files and directories within a given path.
  Future<List<FileSystemEntity>> getFilesInDirectory(
    String directoryPath,
  ) async {
    try {
      final directory = Directory(directoryPath);
      if (await directory.exists()) {
        return directory.list().toList();
      }
      return [];
    } catch (e) {
      _log.e('Error listing files in $directoryPath: $e');
      return [];
    }
  }

  /// Retrieves the file size in bytes.
  Future<int> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      _log.e('Error getting file size $filePath: $e');
      return 0;
    }
  }

  /// Copies a file to a new location, ensuring destination directories exist.
  Future<bool> copyFile(String sourcePath, String destinationPath) async {
    try {
      await ensureDirectoryExists(destinationPath);
      final sourceFile = File(sourcePath);
      await sourceFile.copy(destinationPath);
      return true;
    } catch (e) {
      _log.e('Error copying file $sourcePath to $destinationPath: $e');
      return false;
    }
  }

  /// Deletes a file from the filesystem if it exists.
  Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      _log.e('Error deleting file $filePath: $e');
      return false;
    }
  }

  /// Returns the system's Documents directory path.
  String getDocumentsPath() {
    return _documentsPath ?? Directory.current.path;
  }

  /// Returns the absolute path to the application's user-data directory.
  String getAppDirectoryPath() {
    return _userDataPath ?? userDataFolder;
  }

  /// Returns the absolute path to the application's root media directory.
  String getMediaDirectoryPath() {
    if (!_isInitialized || _mediaPath == null) {
      return mediaFolder;
    }
    return path.join(_mediaPath!, mediaFolder);
  }

  /// Resets the internal state of the provider.
  void reset() {
    _userDataPath = null;
    _mediaPath = null;
    _documentsPath = null;
    _isInitialized = false;
    notifyListeners();
  }

  /// Set in [dispose] to short-circuit [notifyListeners] callbacks that
  /// resolve after the notifier has been torn down (late `await`s, async
  /// callbacks, etc.). Without this guard a setState-after-dispose throws
  /// in release builds and is silently swallowed in debug.
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
