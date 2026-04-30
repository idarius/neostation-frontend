import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/models/config_model.dart';
import 'database_test_helper.dart';

/// Tests for the fork-private `showGameWheel` setting.
///
/// Round-trip is verified at the SqliteService level (not via the higher-level
/// SqliteConfigService) to avoid coupling these tests to unrelated parts of
/// the load pipeline (which queries emulator/system tables not present in the
/// minimal test schema).
void main() {
  late DatabaseTestHelper helper;

  setUp(() async {
    helper = DatabaseTestHelper();
    await helper.setUp();
  });

  tearDown(() async {
    await helper.tearDown();
  });

  test('showGameWheel defaults to true on a fresh ConfigModel', () {
    const config = ConfigModel();
    expect(config.showGameWheel, isTrue);
  });

  test('showGameWheel = false round-trips through SqliteService', () async {
    await SqliteService.saveUserConfig(showGameWheel: 0);

    final row = await SqliteService.getUserConfig();
    expect(row, isNotNull);
    expect(row!['show_game_wheel'], 0);
  });

  test('showGameWheel = true round-trips through SqliteService', () async {
    await SqliteService.saveUserConfig(showGameWheel: 1);

    final row = await SqliteService.getUserConfig();
    expect(row, isNotNull);
    expect(row!['show_game_wheel'], 1);
  });

  test('showGameWheel survives copyWith without explicit value', () {
    const original = ConfigModel(showGameWheel: false);
    final copied = original.copyWith();
    expect(copied.showGameWheel, isFalse);
  });

  test('showGameWheel can be overridden via copyWith', () {
    const original = ConfigModel(showGameWheel: false);
    final copied = original.copyWith(showGameWheel: true);
    expect(copied.showGameWheel, isTrue);
  });

  test('toJson includes showGameWheel', () {
    const config = ConfigModel(showGameWheel: false);
    final json = config.toJson();
    expect(json['showGameWheel'], false);
  });

  test('fromJson reads showGameWheel from camelCase key', () {
    final config = ConfigModel.fromJson({'showGameWheel': false});
    expect(config.showGameWheel, isFalse);
  });

  test('fromJson reads showGameWheel from snake_case key (DB read path)', () {
    final config = ConfigModel.fromJson({'show_game_wheel': 0});
    expect(config.showGameWheel, isFalse);
  });

  test('fromJson defaults showGameWheel to true when missing', () {
    final config = ConfigModel.fromJson({});
    expect(config.showGameWheel, isTrue);
  });
}
