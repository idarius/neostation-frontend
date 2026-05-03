/// SMB sync provider — copies emulator save files to a network share.
///
/// Lifecycle:
///   - initialize() at startup loads credentials from repository and attempts
///     connect.
///   - login() and logout() are user-driven (UI buttons).
///   - updateCredentials() handles hot-swap (disconnect old, connect new).
///
/// Phase 2 scope:
///   - Implements: initialize, login, logout, uploadSave, downloadSave,
///     listSaves, deleteRemote, getQuota (null), fullSync (stub).
///   - Auto-trigger methods (syncGameSavesBeforeLaunch / AfterClose,
///     detectGameSaveFiles) inherit ISyncProvider's default failure
///     implementations. Phase 4 wires them.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/neo_sync_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:neostation/models/smb_credentials_model.dart';
import 'package:neostation/repositories/smb_credentials_repository.dart';
import 'package:neostation/services/smb/smb_client.dart';
import 'package:neostation/services/smb/smb_exceptions.dart';
import 'package:neostation/sync/i_sync_provider.dart';

class SmbSyncProvider extends ChangeNotifier implements ISyncProvider {
  static const String kProviderId = 'smb';

  final SmbCredentialsRepository _repository;

  SmbConnection? _connection;
  SmbCredentialsModel? _config;
  // Password stays in memory for the lifetime of the connection. Cleared on
  // logout. Never persisted in plain text — see SmbCredentialsRepository.
  String? _password;

  SyncProviderStatus _status = SyncProviderStatus.disconnected;
  String? _lastError;

  SmbSyncProvider({SmbCredentialsRepository? repository})
      : _repository = repository ?? SmbCredentialsRepository();

  // ── Identity ───────────────────────────────────────────────────────────────

  @override
  String get providerId => kProviderId;

  @override
  SyncProviderMeta get meta => const SyncProviderMeta(
        id: kProviderId,
        name: 'Network',
        description: 'Sync save files to a SMB network share (NAS).',
        author: 'Idastation',
      );

  // ── State ──────────────────────────────────────────────────────────────────

  @override
  SyncProviderStatus get status => _status;

  @override
  String? get lastError => _lastError;

  @override
  bool get isAuthenticated =>
      _connection != null && !_connection!.isClosed && _config != null;

  /// Currently loaded config (null when not configured).
  SmbCredentialsModel? get config => _config;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    final cfg = await _repository.loadConfig();
    if (cfg == null) {
      _status = SyncProviderStatus.disconnected;
      return;
    }
    final pw = await _repository.loadPassword();
    if (pw == null) {
      // Config exists but no password (rare: secure storage cleared
      // independently). Treat as needing login.
      _config = cfg;
      _password = null;
      _status = SyncProviderStatus.disconnected;
      _lastError = 'Password missing — please re-enter credentials';
      return;
    }
    _config = cfg;
    _password = pw;
    if (!cfg.enabled) {
      _status = SyncProviderStatus.disconnected;
      return;
    }
    await _doConnect();
  }

  @override
  void dispose() {
    _disconnectQuietly();
    super.dispose();
  }

  // ── Authentication ─────────────────────────────────────────────────────────

  @override
  Future<SyncResult> login() async {
    if (_config == null || _password == null) {
      return SyncResult.fail(
        SyncError.configInvalid,
        message: 'No credentials saved — fill the form first',
      );
    }
    return _doConnect();
  }

  @override
  Future<void> logout() async {
    _disconnectQuietly();
    _password = null;
    _status = SyncProviderStatus.disconnected;
    _lastError = null;
    notifyListeners();
  }

  /// Persists new credentials and reconnects without app restart.
  /// Returns the result of the new connection attempt.
  Future<SyncResult> updateCredentials({
    required SmbCredentialsModel config,
    required String password,
  }) async {
    // Disconnect existing.
    _disconnectQuietly();

    // Persist new (atomic from caller's perspective — both halves saved
    // before reconnect).
    await _repository.save(config: config, password: password);
    _config = config;
    _password = password;

    if (!config.enabled) {
      _status = SyncProviderStatus.disconnected;
      _lastError = null;
      notifyListeners();
      return SyncResult.ok(message: 'Saved (provider disabled)');
    }

    return _doConnect();
  }

  Future<SyncResult> _doConnect() async {
    final cfg = _config;
    final pw = _password;
    if (cfg == null || pw == null) {
      return SyncResult.fail(
        SyncError.configInvalid,
        message: 'Missing config or password',
      );
    }
    _status = SyncProviderStatus.connecting;
    _lastError = null;
    notifyListeners();

    try {
      final conn = await SmbClient.connect(
        host: cfg.host,
        share: cfg.share,
        user: cfg.username,
        pass: pw,
        domain: cfg.domain,
      );
      _connection = conn;
      _status = SyncProviderStatus.connected;
      _lastError = null;
      notifyListeners();
      return SyncResult.ok(message: 'Connected to ${cfg.host}/${cfg.share}');
    } on SmbException catch (e) {
      _status = SyncProviderStatus.error;
      _lastError = e.message;
      notifyListeners();
      return SyncResult.fail(_mapErrorToSyncError(e), message: e.message);
    }
  }

  void _disconnectQuietly() {
    final conn = _connection;
    _connection = null;
    if (conn != null && !conn.isClosed) {
      // Fire-and-forget — don't await.
      conn.disconnect();
    }
  }

  SyncError _mapErrorToSyncError(SmbException e) {
    if (e is SmbAuthFailedException) return SyncError.authRequired;
    if (e is SmbHostUnreachableException) return SyncError.networkError;
    if (e is SmbShareNotFoundException) return SyncError.configInvalid;
    if (e is SmbAccessDeniedException) return SyncError.authRequired;
    if (e is SmbTimeoutException) return SyncError.networkError;
    if (e is SmbPathNotFoundException) return SyncError.fileNotFound;
    return SyncError.unknown;
  }

  // ── Core Sync Operations ───────────────────────────────────────────────────

  /// Computes the path inside the share where save files for [gameId] go.
  /// Format: `<subdirectory>/<gameId>/[<filename>]`.
  String _remotePath(String gameId, [String? filename]) {
    final cfg = _config!;
    final base =
        cfg.subdirectory.isEmpty ? gameId : '${cfg.subdirectory}/$gameId';
    return filename == null ? base : '$base/$filename';
  }

  @override
  Future<SyncResult> uploadSave(
    String gameId,
    File file, {
    String? customFileName,
  }) async {
    if (!isAuthenticated) {
      return SyncResult.fail(SyncError.authRequired, message: 'Not connected');
    }
    try {
      final filename = customFileName ?? p.basename(file.path);
      final remote = _remotePath(gameId, filename);
      final Uint8List bytes = await file.readAsBytes();
      await _connection!.writeFile(remote, bytes);
      return SyncResult.ok(message: 'Uploaded to $remote');
    } on SmbException catch (e) {
      return SyncResult.fail(_mapErrorToSyncError(e), message: e.message);
    } catch (e) {
      return SyncResult.fail(SyncError.unknown, message: e.toString());
    }
  }

  @override
  Future<SyncResult> downloadSave(String gameId, String fileId) async {
    if (!isAuthenticated) {
      return SyncResult.fail(SyncError.authRequired, message: 'Not connected');
    }
    try {
      // fileId is the relative path inside <subdirectory>/<gameId>/.
      final remote = _remotePath(gameId, fileId);
      final bytes = await _connection!.readFile(remote);
      // Write to temp, return the local File.
      final tempDir = await getTemporaryDirectory();
      final localFile = File(p.join(
        tempDir.path,
        'smb_download_${DateTime.now().millisecondsSinceEpoch}_${p.basename(fileId)}',
      ));
      await localFile.writeAsBytes(bytes);
      return SyncResult.ok(data: localFile);
    } on SmbException catch (e) {
      return SyncResult.fail(_mapErrorToSyncError(e), message: e.message);
    } catch (e) {
      return SyncResult.fail(SyncError.unknown, message: e.toString());
    }
  }

  @override
  Future<List<SyncFile>> listSaves({String? gameId}) async {
    if (!isAuthenticated) return const [];
    try {
      final cfg = _config!;
      final searchPath = gameId != null
          ? (cfg.subdirectory.isEmpty
              ? gameId
              : '${cfg.subdirectory}/$gameId')
          : cfg.subdirectory;

      final entries = await _connection!.listDirectory(searchPath);
      final files = <SyncFile>[];
      for (final e in entries) {
        if (e.isDir) continue;
        files.add(SyncFile(
          id: gameId != null ? '$gameId/${e.name}' : e.name,
          fileName: e.name,
          fileSize: e.size,
          uploadedAt: e.modifiedAt,
          modifiedAt: e.modifiedAt,
          gameId: gameId,
        ));
      }
      return files;
    } on SmbException {
      return const [];
    }
  }

  @override
  Future<SyncResult> fullSync() async {
    return SyncResult.fail(
      SyncError.unknown,
      message: 'fullSync not yet implemented — Phase 4 will scan local saves',
    );
  }

  @override
  Future<SyncQuota?> getQuota() async => null;

  @override
  Future<SyncResult> deleteRemote(String fileId) async {
    if (!isAuthenticated) {
      return SyncResult.fail(SyncError.authRequired);
    }
    try {
      final cfg = _config!;
      final remote =
          cfg.subdirectory.isEmpty ? fileId : '${cfg.subdirectory}/$fileId';
      await _connection!.delete(remote);
      return SyncResult.ok();
    } on SmbException catch (e) {
      return SyncResult.fail(_mapErrorToSyncError(e), message: e.message);
    }
  }

  // ── Game-specific sync (Phase 4 will override) ────────────────────────────
  // Explicit overrides are required because ChangeNotifier + ISyncProvider
  // together make the Dart analyser treat the interface defaults as abstract
  // unless we re-declare them. The bodies exactly mirror ISyncProvider's
  // defaults — Phase 4 will replace them with real implementations.

  @override
  Future<SyncResult> detectGameSaveFiles(GameModel game) async =>
      SyncResult.fail(
        SyncError.unknown,
        message: 'detectGameSaveFiles not supported by $providerId',
      );

  @override
  GameSyncState? getGameSyncState(String gameId) => null;

  @override
  Future<SyncResult> syncGameSavesBeforeLaunch(GameModel game) async =>
      SyncResult.fail(
        SyncError.unknown,
        message: 'syncGameSavesBeforeLaunch not supported by $providerId',
      );

  @override
  Future<SyncResult> syncGameSavesAfterClose(GameModel game) async =>
      SyncResult.fail(
        SyncError.unknown,
        message: 'syncGameSavesAfterClose not supported by $providerId',
      );

  @override
  Future<void> updateGameCloudSyncEnabled(
      String gameId, bool enabled) async {}
}
