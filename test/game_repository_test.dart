import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/repositories/game_repository.dart';

import 'database_test_helper.dart';

void main() {
  final dbHelper = DatabaseTestHelper();
  late dynamic db;

  setUp(() async {
    db = await dbHelper.setUp();
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('switch', 'Nintendo Switch', 'switch')",
    );
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('snes', 'Super Nintendo', 'snes')",
    );
  });

  tearDown(() async {
    await dbHelper.tearDown();
  });

  group('GameRepository', () {
    test('getSystemFolderForGame returns folder name for matching ROM', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id) VALUES ('game.nsp', '/roms/switch/game.nsp', 'switch')",
      );

      final folder = await GameRepository.getSystemFolderForGame('game.nsp');
      expect(folder, 'switch');
    });

    test('getSystemFolderForGame returns null when ROM not found', () async {
      final folder = await GameRepository.getSystemFolderForGame('missing.nsp');
      expect(folder, isNull);
    });

    test('getSystemIdForGame returns app_system_id for matching ROM', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id) VALUES ('game.nsp', '/roms/switch/game.nsp', 'switch')",
      );

      final systemId = await GameRepository.getSystemIdForGame('game.nsp');
      expect(systemId, 'switch');
    });

    test('findSwitchGameByName finds by title_name', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, title_name, title_id, app_system_id) VALUES ('game.nsp', '/roms/switch/game.nsp', 'Super Mario', '0100000000010000', 'switch')",
      );

      final result = await GameRepository.findSwitchGameByName('Mario');
      expect(result, isNotNull);
      expect(result!['title_name'], 'Super Mario');
    });

    test('findRomByFilenamePrefix returns ROM with folder', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, title_name, app_system_id) VALUES ('zelda.smc', '/roms/snes/zelda.smc', 'Zelda', 'snes')",
      );

      final result = await GameRepository.findRomByFilenamePrefix('zelda');
      expect(result, isNotNull);
      expect(result!['filename'], 'zelda.smc');
      expect(result['folder_name'], 'snes');
    });

    test('findSwitchGameByTitleId returns match by title_id', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, title_name, title_id, app_system_id) VALUES ('game.nsp', '/roms/switch/game.nsp', 'Super Mario', '0100000000010000', 'switch')",
      );

      final result = await GameRepository.findSwitchGameByTitleId(
        '0100000000010000',
      );
      expect(result, isNotNull);
      expect(result!['filename'], 'game.nsp');
    });

    test('getTitleIdForGame returns title_id by filename', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, title_id, app_system_id) VALUES ('game.nsp', '/roms/switch/game.nsp', '0100000000010000', 'switch')",
      );

      final titleId = await GameRepository.getTitleIdForGame(
        'game.nsp',
        'Super Mario',
      );
      expect(titleId, '0100000000010000');
    });

    test('updateGameTitleId persists title_id', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id) VALUES ('game.nsp', '/roms/switch/game.nsp', 'switch')",
      );

      await GameRepository.updateGameTitleId('game.nsp', '0100000000010000');

      final result = await db.rawQuery(
        "SELECT title_id FROM user_roms WHERE filename = 'game.nsp'",
      );
      expect(result.first['title_id'], '0100000000010000');
    });

    test('deleteRomsByFolderPath removes ROMs by prefix', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id) VALUES ('game.smc', '/roms/snes/game.smc', 'snes')",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id) VALUES ('other.smc', '/roms/snes/sub/other.smc', 'snes')",
      );

      final deleted = await GameRepository.deleteRomsByFolderPath('/roms/snes');
      expect(deleted, 2);

      final remaining = await db.rawQuery(
        'SELECT COUNT(*) as c FROM user_roms',
      );
      expect(remaining.first['c'], 0);
    });
  });
}
