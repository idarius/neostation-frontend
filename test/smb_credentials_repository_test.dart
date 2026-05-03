import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/smb_credentials_model.dart';
import 'package:neostation/repositories/smb_credentials_repository.dart';

import 'database_test_helper.dart';

/// In-memory substitute for FlutterSecureStorage.
///
/// The real plugin requires Android Keystore / platform channels which are
/// unavailable in `flutter test`. We extend the class and override the 4
/// methods the repository uses so we stay type-compatible with the constructor
/// injection parameter.
class _InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  _InMemorySecureStorage() : super();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.clear();
  }
}

void main() {
  late DatabaseTestHelper helper;
  late SmbCredentialsRepository repo;

  setUp(() async {
    helper = DatabaseTestHelper();
    await helper.setUp();
    repo = SmbCredentialsRepository(secureStorage: _InMemorySecureStorage());
  });

  tearDown(() async {
    await helper.tearDown();
  });

  test('loadConfig returns null when nothing saved', () async {
    final cfg = await repo.loadConfig();
    expect(cfg, isNull);
  });

  test('loadPassword returns null when nothing saved', () async {
    final pw = await repo.loadPassword();
    expect(pw, isNull);
  });

  test('save + load round-trips both halves', () async {
    const cfg = SmbCredentialsModel(
      host: '192.168.0.10',
      share: 'Aeris',
      subdirectory: 'HomeLab/Backups/Idastation',
      username: 'sylvain',
      domain: 'WORKGROUP',
    );
    await repo.save(config: cfg, password: 'secret');

    final loadedCfg = await repo.loadConfig();
    expect(loadedCfg, isNotNull);
    expect(loadedCfg!.host, '192.168.0.10');
    expect(loadedCfg.share, 'Aeris');
    expect(loadedCfg.subdirectory, 'HomeLab/Backups/Idastation');
    expect(loadedCfg.username, 'sylvain');
    expect(loadedCfg.domain, 'WORKGROUP');
    expect(loadedCfg.enabled, isTrue);

    final loadedPw = await repo.loadPassword();
    expect(loadedPw, 'secret');
  });

  test('save uses defaults when subdirectory and domain omitted in model',
      () async {
    const cfg = SmbCredentialsModel(
      host: '192.168.0.10',
      share: 'Aeris',
      username: 'sylvain',
    );
    await repo.save(config: cfg, password: 'p');

    final loaded = await repo.loadConfig();
    expect(loaded, isNotNull);
    expect(loaded!.subdirectory, 'idastation_saves');
    expect(loaded.domain, 'WORKGROUP');
  });

  test('clear deletes both halves', () async {
    const cfg = SmbCredentialsModel(host: 'h', share: 's', username: 'u');
    await repo.save(config: cfg, password: 'p');
    await repo.clear();

    expect(await repo.loadConfig(), isNull);
    expect(await repo.loadPassword(), isNull);
  });

  test('save overwrites previous values (single-row pattern)', () async {
    await repo.save(
      config: const SmbCredentialsModel(host: 'a', share: 'b', username: 'c'),
      password: 'p1',
    );
    await repo.save(
      config: const SmbCredentialsModel(host: 'x', share: 'y', username: 'z'),
      password: 'p2',
    );

    final loaded = await repo.loadConfig();
    expect(loaded!.host, 'x');
    expect(loaded.share, 'y');
    expect(loaded.username, 'z');
    expect(await repo.loadPassword(), 'p2');
  });
}
