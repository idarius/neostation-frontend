import 'dart:io';
import 'package:neostation/services/logger_service.dart';
import 'package:path/path.dart' as path;
import '../repositories/emulator_repository.dart';

/// Service responsible for detecting Nintendo Switch save data for emulators such as Yuzu, Citron, and Eden.
///
/// Locates save files by parsing emulator configuration files and searching within NAND directories
/// using specific Title IDs.
class SwitchSaveDetector {
  static final _log = LoggerService.instance;

  /// Retrieves a list of potential configuration file paths based on the current platform.
  static List<String> _getConfigPaths() {
    final paths = <String>[];

    if (Platform.isAndroid) {
      // Standard Android data paths for supported emulators.
      final androidDataBase = '/storage/emulated/0/Android/data';

      // Eden Variants
      paths.add(
        path.join(
          androidDataBase,
          'dev.eden.eden_emulator',
          'files',
          'config',
          'config.ini',
        ),
      );
      paths.add(
        path.join(
          androidDataBase,
          'dev.legacy.eden_emulator',
          'files',
          'config',
          'config.ini',
        ),
      );
      paths.add(
        path.join(
          androidDataBase,
          'com.miHoYo.Yuanshen',
          'files',
          'config',
          'config.ini',
        ),
      );
      paths.add(
        path.join(
          androidDataBase,
          'dev.eden.eden_nightly',
          'files',
          'config',
          'config.ini',
        ),
      );

      // Citron
      paths.add(
        path.join(
          androidDataBase,
          'org.citron.citron_emu',
          'files',
          'config',
          'config.ini',
        ),
      );
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];

      // Standard Roaming AppData paths.
      if (appData != null) {
        paths.add(path.join(appData, 'eden', 'config', 'qt-config.ini'));
        paths.add(path.join(appData, 'yuzu', 'config', 'qt-config.ini'));
      }
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'];

      if (home != null) {
        // Standard and Flatpak paths.
        paths.add(
          path.join(home, '.local', 'share', 'yuzu', 'config', 'qt-config.ini'),
        );
        paths.add(
          path.join(home, '.local', 'share', 'eden', 'config', 'qt-config.ini'),
        );
        paths.add(
          path.join(
            home,
            '.var',
            'app',
            'org.yuzu_emu.yuzu',
            'config',
            'yuzu',
            'qt-config.ini',
          ),
        );
      }
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        paths.add(
          path.join(
            home,
            'Library',
            'Application Support',
            'eden',
            'config',
            'qt-config.ini',
          ),
        );
        paths.add(
          path.join(
            home,
            'Library',
            'Application Support',
            'citron',
            'config',
            'qt-config.ini',
          ),
        );
      }
    }

    return paths;
  }

  /// Parses an INI configuration file to extract the `nand_directory` or `save_directory`.
  static String? _parseNandDirectory(
    String configContent, {
    bool isAndroid = false,
  }) {
    try {
      final lines = configContent.split('\n');

      if (isAndroid) {
        String? nandValue;
        String? saveValue;

        // Simple key-value parsing for Android INI files.
        for (var line in lines) {
          line = line.trim();
          if (line.startsWith('nand_directory=')) {
            nandValue = line.substring('nand_directory='.length).trim();
          } else if (line.startsWith('save_directory=')) {
            saveValue = line.substring('save_directory='.length).trim();
          }
        }
        return (saveValue != null && saveValue.isNotEmpty)
            ? saveValue
            : nandValue;
      } else {
        // Qt-style INI parsing for desktop platforms.
        bool inDataStorageSection = false;
        String? nandValue;
        String? saveValue;

        for (var line in lines) {
          line = line.trim();

          if (line == '[Data%20Storage]' || line == '[Data Storage]') {
            inDataStorageSection = true;
            continue;
          }

          if (line.startsWith('[') && inDataStorageSection) break;

          if (inDataStorageSection) {
            if (line.startsWith('nand_directory=')) {
              nandValue = line.substring('nand_directory='.length).trim();
            } else if (line.startsWith('save_directory=')) {
              saveValue = line.substring('save_directory='.length).trim();
            }
          }
        }

        final bestValue = (saveValue != null && saveValue.isNotEmpty)
            ? saveValue
            : nandValue;
        if (bestValue != null && bestValue.isNotEmpty) {
          // Normalize path separators from Qt format (/) to native format.
          return bestValue.replaceAll('/', Platform.pathSeparator);
        }
      }
    } catch (e) {
      _log.e('Error parsing configuration file: $e');
    }
    return null;
  }

  /// Detects all active emulator installations and their respective NAND directories.
  static Future<List<EmulatorNandInfo>> detectEmulatorNandPaths() async {
    final results = <EmulatorNandInfo>[];

    if (Platform.isAndroid) {
      final androidDataBase = '/storage/emulated/0/Android/data';
      final androidEmulators = [
        {'name': 'Eden', 'package': 'dev.eden.eden_emulator'},
        {'name': 'Eden Legacy', 'package': 'dev.legacy.eden_emulator'},
        {'name': 'Eden Optimized', 'package': 'com.miHoYo.Yuanshen'},
        {'name': 'Eden Nightly', 'package': 'dev.eden.eden_nightly'},
        {'name': 'Citron', 'package': 'org.citron.citron_emu'},
      ];

      for (var emu in androidEmulators) {
        try {
          final packageName = emu['package']!;
          final defaultNandPath = path.join(
            androidDataBase,
            packageName,
            'files',
            'nand',
          );
          final configPath = path.join(
            androidDataBase,
            packageName,
            'files',
            'config',
            'config.ini',
          );

          String nandPath = defaultNandPath;

          // Override with custom nand_directory if defined in config.ini.
          final configFile = File(configPath);
          if (await configFile.exists()) {
            final content = await configFile.readAsString();
            final customNandPath = _parseNandDirectory(
              content,
              isAndroid: true,
            );
            if (customNandPath != null && customNandPath.isNotEmpty) {
              nandPath = customNandPath;
            }
          }

          if (await Directory(nandPath).exists()) {
            results.add(
              EmulatorNandInfo(
                emulatorName: emu['name']!,
                configPath: configPath,
                nandDirectory: nandPath,
              ),
            );
          }
        } catch (e) {
          _log.e('Error detecting Android emulator ${emu['name']}: $e');
        }
      }
    } else {
      final configPaths = _getConfigPaths();

      // For Windows, explicitly query the active emulator defined in the database.
      if (Platform.isWindows) {
        try {
          final emulators =
              await EmulatorRepository.getStandaloneEmulatorsBySystemId(
                'switch',
              );
          for (final emu in emulators) {
            if (emu['is_user_default'] == 1 || emu['is_default'] == 1) {
              final exePath = emu['emulator_path']?.toString();
              if (exePath != null && exePath.trim().isNotEmpty) {
                // Check for portable configuration folders.
                final portableConfig = path.join(
                  path.dirname(exePath),
                  'user',
                  'config',
                  'qt-config.ini',
                );
                if (!configPaths.contains(portableConfig)) {
                  configPaths.add(portableConfig);
                }
              }
            }
          }
        } catch (e) {
          _log.e('Error querying active emulators from database: $e');
        }
      }

      for (var configPath in configPaths) {
        try {
          final configFile = File(configPath);
          if (await configFile.exists()) {
            final content = await configFile.readAsString();
            final nandPath = _parseNandDirectory(content, isAndroid: false);

            if (nandPath != null &&
                nandPath.isNotEmpty &&
                await Directory(nandPath).exists()) {
              String emulatorName = 'Unknown';
              final lowerPath = configPath.toLowerCase();

              if (lowerPath.contains('eden')) {
                emulatorName = 'Eden';
              } else if (lowerPath.contains('citron')) {
                emulatorName = 'Citron';
              } else {
                continue; // Skip unrecognized emulators for NeoSync compatibility.
              }

              results.add(
                EmulatorNandInfo(
                  emulatorName: emulatorName,
                  configPath: configPath,
                  nandDirectory: nandPath,
                ),
              );
            }
          }
        } catch (e) {
          _log.e('Error verifying configuration at $configPath: $e');
        }
      }

      // Linux Fallback: check default paths if config parsing failed or was skipped.
      if (Platform.isLinux) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          final linuxDefaults = [
            {
              'name': 'Eden',
              'nand': path.join(home, '.local', 'share', 'eden', 'nand'),
              'config': path.join(
                home,
                '.local',
                'share',
                'eden',
                'config',
                'qt-config.ini',
              ),
            },
            {
              'name': 'Citron',
              'nand': path.join(home, '.local', 'share', 'citron', 'nand'),
              'config': path.join(
                home,
                '.local',
                'share',
                'citron',
                'config',
                'qt-config.ini',
              ),
            },
          ];

          for (var def in linuxDefaults) {
            final nandDir = def['nand']!;
            if (!results.any(
                  (r) =>
                      r.emulatorName == def['name'] &&
                      r.nandDirectory == nandDir,
                ) &&
                await Directory(nandDir).exists()) {
              results.add(
                EmulatorNandInfo(
                  emulatorName: def['name']!,
                  configPath: def['config']!,
                  nandDirectory: nandDir,
                ),
              );
            }
          }
        }
      }
    }

    return results;
  }

  /// Locates the save data for a specific Title ID within a given NAND directory.
  static Future<SwitchSaveInfo?> findSaveForTitleId(
    String nandDirectory,
    String titleId,
  ) async {
    try {
      // Standard save path structure: nand/user/save/0000000000000000/[USER_ID]/[TITLE_ID]/
      final saveBasePath = path.join(
        nandDirectory,
        'user',
        'save',
        '0000000000000000',
      );
      final saveBaseDir = Directory(saveBasePath);

      if (!await saveBaseDir.exists()) return null;

      // Iterate through all potential User IDs.
      await for (var userIdEntity in saveBaseDir.list()) {
        if (userIdEntity is Directory) {
          final titleIdPath = path.join(userIdEntity.path, titleId);
          final titleIdDir = Directory(titleIdPath);

          if (await titleIdDir.exists() && await titleIdDir.list().length > 0) {
            return SwitchSaveInfo(
              titleId: titleId,
              savePath: titleIdPath,
              userId: path.basename(userIdEntity.path),
              nandDirectory: nandDirectory,
            );
          }
        }
      }
    } catch (e) {
      _log.e('Error locating save for Title ID $titleId: $e');
    }
    return null;
  }

  /// Searches for a specific Title ID's save data across all detected emulators.
  static Future<List<SwitchSaveInfo>> findSaveAcrossEmulators(
    String titleId,
  ) async {
    final results = <SwitchSaveInfo>[];
    final emulators = await detectEmulatorNandPaths();

    for (var emulator in emulators) {
      final saveInfo = await findSaveForTitleId(
        emulator.nandDirectory,
        titleId,
      );
      if (saveInfo != null) {
        results.add(
          SwitchSaveInfo(
            titleId: saveInfo.titleId,
            savePath: saveInfo.savePath,
            userId: saveInfo.userId,
            nandDirectory: saveInfo.nandDirectory,
            emulatorName: emulator.emulatorName,
          ),
        );
      }
    }
    return results;
  }

  /// Lists all available save data entries found in a specific NAND directory.
  static Future<List<SwitchSaveInfo>> listAllSavesInNand(
    String nandDirectory,
  ) async {
    final results = <SwitchSaveInfo>[];

    try {
      final saveBasePath = path.join(
        nandDirectory,
        'user',
        'save',
        '0000000000000000',
      );
      final saveBaseDir = Directory(saveBasePath);
      if (!await saveBaseDir.exists()) return results;

      await for (var userIdEntity in saveBaseDir.list()) {
        if (userIdEntity is Directory) {
          final userId = path.basename(userIdEntity.path);

          await for (var titleIdEntity in userIdEntity.list()) {
            if (titleIdEntity is Directory) {
              final titleId = path.basename(titleIdEntity.path);

              // Validate Title ID format (16 hexadecimal characters).
              if (RegExp(r'^[0-9A-F]{16}$').hasMatch(titleId)) {
                if (await titleIdEntity.list().length > 0) {
                  results.add(
                    SwitchSaveInfo(
                      titleId: titleId,
                      savePath: titleIdEntity.path,
                      userId: userId,
                      nandDirectory: nandDirectory,
                    ),
                  );
                }
              }
            }
          }
        }
      }
    } catch (e) {
      _log.e('Error listing save entries: $e');
    }
    return results;
  }

  /// Aggregates all save data found across all detected emulators.
  static Future<Map<String, List<SwitchSaveInfo>>>
  listAllSavesAcrossEmulators() async {
    final results = <String, List<SwitchSaveInfo>>{};
    final emulators = await detectEmulatorNandPaths();

    for (var emulator in emulators) {
      final saves = await listAllSavesInNand(emulator.nandDirectory);
      results[emulator.emulatorName] = saves
          .map(
            (save) => SwitchSaveInfo(
              titleId: save.titleId,
              savePath: save.savePath,
              userId: save.userId,
              nandDirectory: save.nandDirectory,
              emulatorName: emulator.emulatorName,
            ),
          )
          .toList();
    }
    return results;
  }

  /// Recursively calculates the total size in bytes of a save directory.
  static Future<int> calculateSaveSize(String savePath) async {
    int totalSize = 0;
    try {
      final saveDir = Directory(savePath);
      if (!await saveDir.exists()) return 0;

      await for (var entity in saveDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          totalSize += (await entity.stat()).size;
        }
      }
    } catch (e) {
      _log.e('Error calculating save size: $e');
    }
    return totalSize;
  }
}

/// Holds NAND location and metadata for a specific emulator installation.
class EmulatorNandInfo {
  final String emulatorName;
  final String configPath;
  final String nandDirectory;

  EmulatorNandInfo({
    required this.emulatorName,
    required this.configPath,
    required this.nandDirectory,
  });

  @override
  String toString() => '$emulatorName: $nandDirectory';
}

/// Metadata identifying a specific Nintendo Switch save entry.
class SwitchSaveInfo {
  /// The 16-character hexadecimal Title ID of the game.
  final String titleId;

  /// Full filesystem path to the save directory.
  final String savePath;

  /// The 32-character hexadecimal User ID hash associated with the save.
  final String userId;

  /// The root NAND directory containing this save.
  final String nandDirectory;

  /// The name of the emulator where this save was located.
  final String? emulatorName;

  SwitchSaveInfo({
    required this.titleId,
    required this.savePath,
    required this.userId,
    required this.nandDirectory,
    this.emulatorName,
  });

  @override
  String toString() {
    final emu = emulatorName != null ? '[$emulatorName] ' : '';
    return '${emu}Title: $titleId, Path: $savePath';
  }

  /// Unique identifier generated from the Title ID and User ID.
  String get uniqueId => '$titleId-$userId';
}
