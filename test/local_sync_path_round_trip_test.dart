import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'database_test_helper.dart';

/// Tests for the fork-private `local_sync_path` column.
///
/// Round-trip is verified at the SqliteService level to mirror the
/// `show_game_wheel_test.dart` pattern.
void main() {
  late DatabaseTestHelper helper;

  setUp(() async {
    helper = DatabaseTestHelper();
    await helper.setUp();
  });

  tearDown(() async {
    await helper.tearDown();
  });

  test('local_sync_path defaults to NULL on a fresh user_config', () async {
    await SqliteService.saveUserConfig(themeName: 'system');

    final row = await SqliteService.getUserConfig();
    expect(row, isNotNull);
    expect(row!['local_sync_path'], isNull);
  });

  test('local_sync_path round-trips a non-empty value', () async {
    await SqliteService.saveUserConfig(localSyncPath: '/mnt/nas/saves');

    final row = await SqliteService.getUserConfig();
    expect(row, isNotNull);
    expect(row!['local_sync_path'], '/mnt/nas/saves');
  });

  test('local_sync_path can be cleared back to empty string', () async {
    await SqliteService.saveUserConfig(localSyncPath: '/mnt/nas/saves');
    await SqliteService.saveUserConfig(localSyncPath: '');

    final row = await SqliteService.getUserConfig();
    expect(row, isNotNull);
    expect(row!['local_sync_path'], '');
  });
}
