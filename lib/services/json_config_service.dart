import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:neostation/services/logger_service.dart';
import '../models/system_model.dart';
import '../models/system_configuration.dart';

/// Service responsible for loading and parsing system configuration JSON files from assets.
///
/// Discovers all JSON files in `assets/systems/`, parses their nested structures,
/// and transforms them into [SystemConfiguration] objects containing both
/// system metadata and emulator definitions.
class JsonConfigService {
  static final JsonConfigService _instance = JsonConfigService._internal();
  static JsonConfigService get instance => _instance;
  JsonConfigService._internal();

  static final _log = LoggerService.instance;

  /// Loads and parses all system configuration files located in `assets/systems/`.
  ///
  /// Uses the [AssetManifest] to discover available files and applies data
  /// transformation logic to map nested JSON structures into the flattened
  /// [SystemModel] format.
  Future<List<SystemConfiguration>> loadSystems() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

      final systemFiles = manifest
          .listAssets()
          .where(
            (String key) =>
                key.startsWith('assets/systems/') && key.endsWith('.json'),
          )
          .toList();

      List<SystemConfiguration> systems = [];

      for (final filePath in systemFiles) {
        try {
          final content = await rootBundle.loadString(filePath);
          final Map<String, dynamic> jsonMap = json.decode(content);

          if (jsonMap.containsKey('system')) {
            final systemData = jsonMap['system'];

            final flatMap = <String, dynamic>{
              'id': _generateId(systemData['id']),
              'folderName': systemData['id'],
              'realName': systemData['name'],
              'shortName': systemData['short_name'],
              'launchDate': systemData['details']?['release_date'],
              'description': systemData['details']?['description'],
              'manufacturer': systemData['details']?['manufacturer'],
              'type': systemData['details']?['type'],
              'screenscraperId': systemData['ids']?['screenscraper'],
              'raId': systemData['ids']?['retroachievements'],
              'iconImage': 'assets/images/systems/${systemData['id']}-icon.png',
              'backgroundImage':
                  'assets/images/systems/${systemData['id']}-bg.jpg',
              'color1':
                  (systemData['colors'] is List &&
                      (systemData['colors'] as List).isNotEmpty)
                  ? systemData['colors'][0].toString()
                  : null,
              'color2':
                  (systemData['colors'] is List &&
                      (systemData['colors'] as List).length > 1)
                  ? systemData['colors'][1].toString()
                  : null,
              'extensions': systemData['extensions'] ?? [],
              'folders': systemData['folders'] ?? [],
              'neosync': jsonMap['neosync'],
            };

            final systemModel = SystemModel.fromJson(flatMap);

            List<EmulatorDefinition> emulators = [];
            final emulatorsKey = jsonMap.containsKey('emulators')
                ? 'emulators'
                : (jsonMap.containsKey('players') ? 'players' : null);

            if (emulatorsKey != null) {
              final playersList = jsonMap[emulatorsKey] as List;
              emulators = playersList
                  .map((e) => EmulatorDefinition.fromJson(e))
                  .toList();
            }

            systems.add(
              SystemConfiguration(system: systemModel, emulators: emulators),
            );
          }
        } catch (e) {
          _log.e('Error parsing system JSON $filePath: $e');
        }
      }

      return systems;
    } catch (e) {
      _log.e('Error loading system configurations: $e');
      return [];
    }
  }

  /// Generates a numeric identifier from a string ID using its hash code.
  int _generateId(String id) {
    return id.hashCode;
  }
}
