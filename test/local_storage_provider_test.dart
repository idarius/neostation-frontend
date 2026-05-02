import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/sync/i_sync_provider.dart';
import 'package:neostation/sync/providers/local_storage_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_sync_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalStorageProvider config gating', () {
    test('isAuthenticated is false when targetPath is null', () {
      final p = LocalStorageProvider();
      expect(p.isAuthenticated, isFalse);
    });

    test('isAuthenticated is false when targetPath is empty', () {
      final p = LocalStorageProvider(targetPath: '');
      expect(p.isAuthenticated, isFalse);
    });

    test('isAuthenticated is true when targetPath is set', () {
      final p = LocalStorageProvider(targetPath: tempDir.path);
      expect(p.isAuthenticated, isTrue);
    });
  });

  group('LocalStorageProvider initialize', () {
    test('initialize sets connected status when path exists', () async {
      final p = LocalStorageProvider(targetPath: tempDir.path);
      await p.initialize();
      expect(p.status, SyncProviderStatus.connected);
      expect(p.lastError, isNull);
    });

    test('initialize sets error status when path does not exist', () async {
      final missing = '${tempDir.path}/does_not_exist';
      final p = LocalStorageProvider(targetPath: missing);
      await p.initialize();
      expect(p.status, SyncProviderStatus.error);
      expect(p.lastError, contains('does not exist'));
    });
  });

  group('LocalStorageProvider login', () {
    test('login returns failure when not configured', () async {
      final p = LocalStorageProvider();
      final r = await p.login();
      expect(r.success, isFalse);
      expect(r.error, SyncError.configInvalid);
    });

    test('login creates the directory if it is missing', () async {
      final newPath = '${tempDir.path}/created_by_login';
      final p = LocalStorageProvider(targetPath: newPath);
      final r = await p.login();
      expect(r.success, isTrue);
      expect(await Directory(newPath).exists(), isTrue);
      expect(p.status, SyncProviderStatus.connected);
    });
  });

  group('LocalStorageProvider uploadSave', () {
    test('uploadSave writes file under <path>/<gameId>/<filename>', () async {
      final p = LocalStorageProvider(targetPath: tempDir.path);
      await p.initialize();

      final src = File('${tempDir.path}/source.srm');
      await src.writeAsString('save data');

      final r = await p.uploadSave('mario_world', src);
      expect(r.success, isTrue);

      final dest = File('${tempDir.path}/mario_world/source.srm');
      expect(await dest.exists(), isTrue);
      expect(await dest.readAsString(), 'save data');
    });

    test('uploadSave honours customFileName', () async {
      final p = LocalStorageProvider(targetPath: tempDir.path);
      await p.initialize();

      final src = File('${tempDir.path}/source.srm');
      await src.writeAsString('x');

      final r = await p.uploadSave(
        'zelda',
        src,
        customFileName: 'rename.srm',
      );
      expect(r.success, isTrue);
      expect(
        await File('${tempDir.path}/zelda/rename.srm').exists(),
        isTrue,
      );
    });
  });

  group('LocalStorageProvider listSaves', () {
    test('listSaves returns empty when path is empty', () async {
      final p = LocalStorageProvider(targetPath: tempDir.path);
      final result = await p.listSaves();
      expect(result, isEmpty);
    });

    test('listSaves returns uploaded files', () async {
      final targetDir =
          await Directory.systemTemp.createTemp('local_sync_target_');
      addTearDown(() => targetDir.delete(recursive: true));

      final p = LocalStorageProvider(targetPath: targetDir.path);
      await p.initialize();

      // Source file lives outside the target path so listSaves doesn't see it.
      final src = File('${tempDir.path}/source.srm');
      await src.writeAsString('a');
      await p.uploadSave('mario', src);

      final saves = await p.listSaves();
      expect(saves, hasLength(1));
      expect(saves.first.fileName, 'source.srm');
      expect(saves.first.id, contains('mario'));
    });

    test('listSaves filters by gameId', () async {
      final p = LocalStorageProvider(targetPath: tempDir.path);
      await p.initialize();

      final s1 = File('${tempDir.path}/a.srm');
      await s1.writeAsString('a');
      await p.uploadSave('mario', s1);

      final s2 = File('${tempDir.path}/b.srm');
      await s2.writeAsString('b');
      await p.uploadSave('zelda', s2);

      final marioSaves = await p.listSaves(gameId: 'mario');
      expect(marioSaves, hasLength(1));
      expect(marioSaves.first.fileName, 'a.srm');
    });
  });

  group('LocalStorageProvider downloadSave / deleteRemote', () {
    test('downloadSave returns the File when present', () async {
      final p = LocalStorageProvider(targetPath: tempDir.path);
      await p.initialize();

      final src = File('${tempDir.path}/orig.srm');
      await src.writeAsString('payload');
      await p.uploadSave('mario', src);

      final r = await p.downloadSave('mario', 'orig.srm');
      expect(r.success, isTrue);
      expect(r.data, isA<File>());
      expect(await (r.data as File).readAsString(), 'payload');
    });

    test('downloadSave returns fileNotFound when missing', () async {
      final p = LocalStorageProvider(targetPath: tempDir.path);
      await p.initialize();

      final r = await p.downloadSave('mario', 'absent.srm');
      expect(r.success, isFalse);
      expect(r.error, SyncError.fileNotFound);
    });

    test('deleteRemote removes the file', () async {
      final p = LocalStorageProvider(targetPath: tempDir.path);
      await p.initialize();

      final src = File('${tempDir.path}/del.srm');
      await src.writeAsString('x');
      await p.uploadSave('mario', src);

      final r1 = await p.deleteRemote('mario/del.srm');
      expect(r1.success, isTrue);

      final r2 = await p.deleteRemote('mario/del.srm');
      expect(r2.success, isFalse);
      expect(r2.error, SyncError.fileNotFound);
    });
  });
}
