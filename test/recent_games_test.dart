import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/repositories/game_repository.dart';
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
    String? lastPlayed,
  }) async {
    final db = await SqliteService.getDatabase();
    await db.insert('user_roms', {
      'filename': filename,
      'rom_path': '/roms/$systemId/$filename',
      'app_system_id': systemId,
      'last_played': lastPlayed,
    });
  }

  group('getRecentlyPlayedGames', () {
    test('returns empty list when no game has lastPlayed', () async {
      await seedSystem('snes', 'snes');
      await seedGame(filename: 'mario.smc', systemId: 'snes');
      final result = await SqliteService.getRecentlyPlayedGames();
      expect(result, isEmpty);
    });

    test('returns games sorted desc by last_played', () async {
      await seedSystem('snes', 'snes');
      await seedGame(
        filename: 'old.smc',
        systemId: 'snes',
        lastPlayed: '2026-05-01T10:00:00Z',
      );
      await seedGame(
        filename: 'new.smc',
        systemId: 'snes',
        lastPlayed: '2026-05-02T10:00:00Z',
      );
      final result = await SqliteService.getRecentlyPlayedGames();
      expect(result.length, 2);
      expect(result[0].filename, 'new.smc');
      expect(result[1].filename, 'old.smc');
    });

    test('respects limit parameter', () async {
      await seedSystem('snes', 'snes');
      for (var i = 0; i < 25; i++) {
        await seedGame(
          filename: 'g$i.smc',
          systemId: 'snes',
          lastPlayed: '2026-05-02T10:00:${i.toString().padLeft(2, "0")}Z',
        );
      }
      final result = await SqliteService.getRecentlyPlayedGames(limit: 20);
      expect(result.length, 20);
    });

    test('excludes android system games by default', () async {
      await seedSystem('android', 'android');
      await seedSystem('snes', 'snes');
      await seedGame(
        filename: 'YouTube',
        systemId: 'android',
        lastPlayed: '2026-05-02T10:00:00Z',
      );
      await seedGame(
        filename: 'mario.smc',
        systemId: 'snes',
        lastPlayed: '2026-05-02T09:00:00Z',
      );
      final result = await SqliteService.getRecentlyPlayedGames();
      expect(result.length, 1);
      expect(result[0].filename, 'mario.smc');
    });

    test('honors custom excludeFolders', () async {
      await seedSystem('snes', 'snes');
      await seedSystem('nes', 'nes');
      await seedGame(
        filename: 'mario.smc',
        systemId: 'snes',
        lastPlayed: '2026-05-02T10:00:00Z',
      );
      await seedGame(
        filename: 'duckhunt.nes',
        systemId: 'nes',
        lastPlayed: '2026-05-02T09:00:00Z',
      );
      final result = await SqliteService.getRecentlyPlayedGames(
        excludeFolders: {'nes'},
      );
      expect(result.length, 1);
      expect(result[0].filename, 'mario.smc');
    });

    test('GameRepository delegates to SqliteService', () async {
      await seedSystem('snes', 'snes');
      await seedGame(
        filename: 'mario.smc',
        systemId: 'snes',
        lastPlayed: '2026-05-02T10:00:00Z',
      );
      final result = await GameRepository.getRecentlyPlayedGames();
      expect(result.length, 1);
      expect(result[0].filename, 'mario.smc');
    });
  });
}
