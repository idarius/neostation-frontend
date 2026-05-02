import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/services/game_service.dart';
import 'database_test_helper.dart';

void main() {
  late DatabaseTestHelper helper;

  setUp(() async {
    helper = DatabaseTestHelper();
    await helper.setUp();
  });

  tearDown(() async {
    await helper.tearDown();
  });

  Future<void> seedSystem(String id, String folderName) async {
    final db = await SqliteService.getDatabase();
    await db.insert('app_systems', {
      'id': id,
      'real_name': folderName.toUpperCase(),
      'folder_name': folderName,
      'short_name': folderName,
    });
  }

  Future<void> seedGame({
    required String filename,
    required String systemId,
    String? scrapedRealName,
  }) async {
    final db = await SqliteService.getDatabase();
    await db.insert('user_roms', {
      'filename': filename,
      'rom_path': '/roms/$systemId/$filename',
      'app_system_id': systemId,
    });
    if (scrapedRealName != null) {
      await db.insert('user_screenscraper_metadata', {
        'app_system_id': systemId,
        'filename': filename,
        'real_name': scrapedRealName,
      });
    }
  }

  SystemModel searchSystem() => SystemModel(
    id: 'search',
    folderName: 'search',
    realName: 'Search',
    iconImage: '',
    color: '#5C6BC0',
    color1: '#5C6BC0',
    color2: '#9FA8DA',
    hideLogo: false,
    imageVersion: 0,
    romCount: 0,
    detected: true,
  );

  group('loadGamesForSystem(searchSystem, searchQuery)', () {
    test('returns empty list when searchQuery is null or empty', () async {
      await seedSystem('snes', 'snes');
      await seedGame(filename: 'mario.smc', systemId: 'snes');
      final result = await GameService.loadGamesForSystem(searchSystem());
      expect(result, isEmpty);
      final result2 = await GameService.loadGamesForSystem(
        searchSystem(),
        searchQuery: '',
      );
      expect(result2, isEmpty);
    });

    test('returns matches when searchQuery is provided', () async {
      await seedSystem('snes', 'snes');
      await seedGame(
        filename: 'super_mario_world.smc',
        systemId: 'snes',
        scrapedRealName: 'Super Mario World',
      );
      await seedGame(filename: 'sonic.smc', systemId: 'snes');
      final result = await GameService.loadGamesForSystem(
        searchSystem(),
        searchQuery: 'mario',
      );
      expect(result.length, 1);
      expect(result[0].romname, 'super_mario_world.smc');
      expect(
        result[0].systemId,
        'snes',
      ); // crucial: per-game system id populated
      expect(result[0].systemFolderName, 'snes');
    });
  });
}
