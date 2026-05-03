import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/smb_credentials_model.dart';
import 'package:neostation/sync/i_sync_provider.dart';
import 'package:neostation/sync/providers/smb_sync_provider.dart';

void main() {
  group('SmbSyncProvider identity', () {
    test('providerId is smb', () {
      final provider = SmbSyncProvider();
      expect(provider.providerId, 'smb');
    });

    test('meta is human-readable', () {
      final provider = SmbSyncProvider();
      expect(provider.meta.id, 'smb');
      expect(provider.meta.name, 'Network');
      expect(provider.meta.description, contains('SMB'));
    });

    test('initial status is disconnected', () {
      final provider = SmbSyncProvider();
      expect(provider.status, SyncProviderStatus.disconnected);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.lastError, isNull);
      expect(provider.config, isNull);
    });
  });

  group('SmbSyncProvider login without credentials', () {
    test('login fails when no credentials saved', () async {
      final provider = SmbSyncProvider();
      final r = await provider.login();
      expect(r.success, isFalse);
      expect(r.error, SyncError.configInvalid);
    });
  });

  group('SmbSyncProvider operations require auth', () {
    test('uploadSave fails when not authenticated', () async {
      final provider = SmbSyncProvider();
      final r = await provider.uploadSave(
        'mario',
        File('/tmp/dummy_does_not_exist.srm'),
      );
      expect(r.success, isFalse);
      expect(r.error, SyncError.authRequired);
    });

    test('downloadSave fails when not authenticated', () async {
      final provider = SmbSyncProvider();
      final r = await provider.downloadSave('mario', 'save.srm');
      expect(r.success, isFalse);
      expect(r.error, SyncError.authRequired);
    });

    test('listSaves returns empty when not authenticated', () async {
      final provider = SmbSyncProvider();
      final saves = await provider.listSaves();
      expect(saves, isEmpty);
    });

    test('deleteRemote fails when not authenticated', () async {
      final provider = SmbSyncProvider();
      final r = await provider.deleteRemote('mario/save.srm');
      expect(r.success, isFalse);
      expect(r.error, SyncError.authRequired);
    });

    test('fullSync returns "not yet implemented"', () async {
      final provider = SmbSyncProvider();
      final r = await provider.fullSync();
      expect(r.success, isFalse);
      expect(r.message, contains('not yet implemented'));
    });

    test('getQuota returns null', () async {
      final provider = SmbSyncProvider();
      expect(await provider.getQuota(), isNull);
    });
  });

  group('SmbSyncProvider logout clears state', () {
    test('logout resets status to disconnected', () async {
      final provider = SmbSyncProvider();
      await provider.logout();
      expect(provider.status, SyncProviderStatus.disconnected);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.lastError, isNull);
    });
  });

  group('SmbSyncProvider ISyncProvider contract', () {
    test('implements ISyncProvider', () {
      final provider = SmbSyncProvider();
      expect(provider, isA<ISyncProvider>());
    });

    test(
        'detectGameSaveFiles inherits default fail from ISyncProvider',
        () async {
      final provider = SmbSyncProvider();
      // We cannot call detectGameSaveFiles without a real GameModel, but we
      // can verify that getGameSyncState returns null (the default).
      expect(provider.getGameSyncState('any'), isNull);
    });
  });

  group('SmbSyncProvider credentials model', () {
    test('SmbCredentialsModel defaults are sensible', () {
      const cfg = SmbCredentialsModel(
        host: '192.168.0.1',
        share: 'saves',
        username: 'user',
      );
      expect(cfg.subdirectory, 'idastation_saves');
      expect(cfg.domain, 'WORKGROUP');
      expect(cfg.enabled, isTrue);
    });

    test('SmbCredentialsModel.fromRow returns null for missing host', () {
      final result = SmbCredentialsModel.fromRow({'share': 's', 'username': 'u'});
      expect(result, isNull);
    });

    test('SmbCredentialsModel.fromRow returns null for missing share', () {
      final result = SmbCredentialsModel.fromRow({'host': 'h', 'username': 'u'});
      expect(result, isNull);
    });

    test('SmbCredentialsModel.fromRow returns null for missing username', () {
      final result = SmbCredentialsModel.fromRow({'host': 'h', 'share': 's'});
      expect(result, isNull);
    });

    test('SmbCredentialsModel.fromRow builds correctly from full row', () {
      final result = SmbCredentialsModel.fromRow({
        'host': '192.168.0.1',
        'share': 'nas',
        'username': 'admin',
        'subdirectory': 'saves',
        'domain': 'HOME',
        'enabled': 1,
      });
      expect(result, isNotNull);
      expect(result!.host, '192.168.0.1');
      expect(result.subdirectory, 'saves');
      expect(result.domain, 'HOME');
      expect(result.enabled, isTrue);
    });

    test('SmbCredentialsModel.fromRow uses defaults for blank subdir/domain',
        () {
      final result = SmbCredentialsModel.fromRow({
        'host': 'h',
        'share': 's',
        'username': 'u',
        'subdirectory': '',
        'domain': '',
        'enabled': 0,
      });
      expect(result, isNotNull);
      expect(result!.subdirectory, 'idastation_saves');
      expect(result.domain, 'WORKGROUP');
      expect(result.enabled, isFalse);
    });
  });
}
