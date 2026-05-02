import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
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
    int isFavorite = 0,
    String? scrapedRealName,
  }) async {
    final db = await SqliteService.getDatabase();
    await db.insert('user_roms', {
      'filename': filename,
      'rom_path': '/roms/$systemId/$filename',
      'app_system_id': systemId,
      'is_favorite': isFavorite,
    });
    if (scrapedRealName != null) {
      await db.insert('user_screenscraper_metadata', {
        'app_system_id': systemId,
        'filename': filename,
        'real_name': scrapedRealName,
      });
    }
  }

  group('searchGames', () {
    test('returns games whose display name contains the query (case-insensitive)', () async {
      await seedSystem('snes', 'snes');
      await seedGame(filename: 'super_mario_world.smc', systemId: 'snes', scrapedRealName: 'Super Mario World');
      await seedGame(filename: 'sonic.smc', systemId: 'snes', scrapedRealName: 'Sonic');
      final result = await SqliteService.searchGames('mario');
      expect(result.length, 1);
      expect(result[0].filename, 'super_mario_world.smc');
    });

    test('matches case-insensitively (uppercase query)', () async {
      await seedSystem('snes', 'snes');
      await seedGame(filename: 'mario.smc', systemId: 'snes', scrapedRealName: 'Super Mario World');
      final result = await SqliteService.searchGames('MARIO');
      expect(result.length, 1);
    });

    test('falls back to filename for non-scraped games', () async {
      await seedSystem('snes', 'snes');
      await seedGame(filename: 'zelda.smc', systemId: 'snes'); // no scrape metadata
      final result = await SqliteService.searchGames('zelda');
      expect(result.length, 1);
      expect(result[0].filename, 'zelda.smc');
    });

    test('returns empty list when nothing matches', () async {
      await seedSystem('snes', 'snes');
      await seedGame(filename: 'mario.smc', systemId: 'snes', scrapedRealName: 'Super Mario World');
      final result = await SqliteService.searchGames('xyzzz');
      expect(result, isEmpty);
    });

    test('orders favorites first then alphabetically', () async {
      await seedSystem('snes', 'snes');
      await seedGame(filename: 'b.smc', systemId: 'snes', scrapedRealName: 'B Mario', isFavorite: 0);
      await seedGame(filename: 'c.smc', systemId: 'snes', scrapedRealName: 'C Mario', isFavorite: 1);
      await seedGame(filename: 'a.smc', systemId: 'snes', scrapedRealName: 'A Mario', isFavorite: 0);
      final result = await SqliteService.searchGames('mario');
      expect(result.length, 3);
      expect(result[0].filename, 'c.smc'); // favorite first
      expect(result[1].filename, 'a.smc'); // then alpha
      expect(result[2].filename, 'b.smc');
    });

    test('respects custom limit', () async {
      await seedSystem('snes', 'snes');
      for (var i = 0; i < 25; i++) {
        await seedGame(filename: 'mario_$i.smc', systemId: 'snes');
      }
      final result = await SqliteService.searchGames('mario', limit: 10);
      expect(result.length, 10);
    });

    test('default limit is 200', () async {
      await seedSystem('snes', 'snes');
      for (var i = 0; i < 250; i++) {
        await seedGame(filename: 'mario_${i.toString().padLeft(3, '0')}.smc', systemId: 'snes');
      }
      final result = await SqliteService.searchGames('mario');
      expect(result.length, 200);
    });
  });
}
