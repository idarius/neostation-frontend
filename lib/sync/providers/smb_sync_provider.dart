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
///
/// Phase 4 additions:
///   - Auto-trigger methods: syncGameSavesAfterClose, syncGameSavesBeforeLaunch,
///     detectGameSaveFiles, getGameSyncState.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/neo_sync_models.dart';
import 'package:neostation/repositories/sync_repository.dart';
import 'package:neostation/services/save_discovery_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:neostation/models/smb_credentials_model.dart';
import 'package:neostation/repositories/smb_credentials_repository.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/smb/smb_client.dart';
import 'package:neostation/services/smb/smb_exceptions.dart';
import 'package:neostation/sync/i_sync_provider.dart';

class SmbSyncProvider extends ChangeNotifier implements ISyncProvider {
  static const String kProviderId = 'smb';
  static final _log = LoggerService.instance;

  final SmbCredentialsRepository _repository;

  SmbConnection? _connection;
  SmbCredentialsModel? _config;
  // Password stays in memory for the lifetime of the connection. Cleared on
  // logout. Never persisted in plain text — see SmbCredentialsRepository.
  String? _password;

  SyncProviderStatus _status = SyncProviderStatus.disconnected;
  String? _lastError;

  /// In-memory sync state per game, keyed by game.romname.
  /// Updated by auto-trigger methods and detectGameSaveFiles.
  final Map<String, GameSyncState> _gameSyncStates = {};

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
    _log.d('[SMB] initialize() — loading config from SQLite...');
    final cfg = await _repository.loadConfig();
    _log.d('[SMB] config loaded: ${cfg == null ? "null" : "host=${cfg.host} share=${cfg.share} user=${cfg.username}"}');
    if (cfg == null) {
      _status = SyncProviderStatus.disconnected;
      return;
    }
    _log.d('[SMB] loading password from secure_storage...');
    final pw = await _repository.loadPassword();
    _log.d('[SMB] password loaded: ${pw == null ? "null (BUG)" : "OK (${pw.length} chars)"}');
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
    _log.d('[SMB] reconnecting with stored credentials...');
    final r = await _doConnect();
    _log.d('[SMB] _doConnect result: success=${r.success} message=${r.message}');
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

  /// True iff a non-empty password is currently held in memory (typically
  /// loaded at startup from secure storage). Used by the UI form to detect
  /// when the password field can be left empty (= keep the saved one).
  bool get hasStoredPassword => _password != null && _password!.isNotEmpty;

  /// Persists new credentials and reconnects without app restart.
  ///
  /// If [password] is empty AND a stored password is already in memory, the
  /// stored password is preserved (the UI can leave the password field blank
  /// to mean "keep my saved password"). If [password] is non-empty, it
  /// replaces the stored one.
  ///
  /// Returns the result of the new connection attempt.
  Future<SyncResult> updateCredentials({
    required SmbCredentialsModel config,
    required String password,
  }) async {
    // Disconnect existing.
    _disconnectQuietly();

    // Resolve effective password: keep the stored one if the form was empty.
    final effectivePassword =
        password.isEmpty && hasStoredPassword ? _password! : password;

    // Persist new (atomic from caller's perspective — both halves saved
    // before reconnect).
    await _repository.save(config: config, password: effectivePassword);
    _config = config;
    _password = effectivePassword;

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
      if (gameId != null) {
        final searchPath = cfg.subdirectory.isEmpty
            ? gameId
            : '${cfg.subdirectory}/$gameId';
        final entries = await _connection!.listDirectory(searchPath);
        return entries.where((e) => !e.isDir).map((e) => SyncFile(
              id: '$gameId/${e.name}',
              fileName: e.name,
              fileSize: e.size,
              uploadedAt: e.modifiedAt,
              modifiedAt: e.modifiedAt,
              gameId: gameId,
            )).toList();
      }
      return _recursiveListSaves(cfg.subdirectory, '');
    } on SmbException {
      return const [];
    }
  }

  /// Recursively walks [basePath]/[relativePath] and returns every regular
  /// file found, with `id` set to the path relative to [basePath].
  Future<List<SyncFile>> _recursiveListSaves(
    String basePath,
    String relativePath,
  ) async {
    final fullPath = relativePath.isEmpty
        ? basePath
        : (basePath.isEmpty ? relativePath : '$basePath/$relativePath');
    final entries = await _connection!.listDirectory(fullPath);
    final files = <SyncFile>[];
    for (final e in entries) {
      final entryRelative = relativePath.isEmpty
          ? e.name
          : '$relativePath/${e.name}';
      if (e.isDir) {
        files.addAll(await _recursiveListSaves(basePath, entryRelative));
      } else {
        // Treat the first path segment as the gameId for SyncFile metadata.
        final firstSlash = entryRelative.indexOf('/');
        final gameId = firstSlash > 0
            ? entryRelative.substring(0, firstSlash)
            : '';
        files.add(SyncFile(
          id: entryRelative,
          fileName: e.name,
          fileSize: e.size,
          uploadedAt: e.modifiedAt,
          modifiedAt: e.modifiedAt,
          gameId: gameId.isEmpty ? null : gameId,
        ));
      }
    }
    return files;
  }

  @override
  Future<SyncResult> fullSync() async {
    return SyncResult.fail(
      SyncError.unknown,
      message: 'fullSync not yet implemented',
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

  // ── Auto-trigger: game save sync ──────────────────────────────────────────

  @override
  Future<SyncResult> syncGameSavesAfterClose(GameModel game) async {
    if (!isAuthenticated) {
      return SyncResult.fail(SyncError.authRequired, message: 'Not connected');
    }
    // 1s delay so the emulator has flushed save buffers to disk.
    await Future.delayed(const Duration(seconds: 1));

    final saves = await SaveDiscoveryService.instance.findSaveFilesForGame(game);
    if (saves.isEmpty) {
      _gameSyncStates[game.romname] = GameSyncState(
        gameId: game.romname,
        gameName: game.name,
        status: GameSyncStatus.noSaveFound,
        cloudEnabled: true,
      );
      notifyListeners();
      return SyncResult.ok(message: 'No local saves for ${game.name}');
    }

    int uploaded = 0;
    int conflicted = 0;
    String? lastError;

    for (final localSave in saves) {
      try {
        final outcome = await _syncOneFileAfterPlay(game, localSave);
        if (outcome == _SyncOutcome.uploaded) {
          uploaded++;
        } else if (outcome == _SyncOutcome.conflict) {
          conflicted++;
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    final status = conflicted > 0
        ? GameSyncStatus.conflict
        : GameSyncStatus.upToDate;
    _gameSyncStates[game.romname] = GameSyncState(
      gameId: game.romname,
      gameName: game.name,
      status: status,
      cloudEnabled: true,
      lastSync: DateTime.now(),
      errorMessage: lastError,
    );
    notifyListeners();

    return SyncResult.ok(
      message:
          'Uploaded $uploaded file(s)${conflicted > 0 ? ", $conflicted conflict(s)" : ""}',
    );
  }

  @override
  Future<SyncResult> syncGameSavesBeforeLaunch(GameModel game) async {
    if (!isAuthenticated) {
      return SyncResult.fail(SyncError.authRequired, message: 'Not connected');
    }

    final saves = await SaveDiscoveryService.instance.findSaveFilesForGame(game);
    if (saves.isEmpty) {
      _gameSyncStates[game.romname] = GameSyncState(
        gameId: game.romname,
        gameName: game.name,
        status: GameSyncStatus.noSaveFound,
        cloudEnabled: true,
      );
      notifyListeners();
      return SyncResult.ok(message: 'No local saves for ${game.name}');
    }

    int downloaded = 0;
    int conflicted = 0;
    String? lastError;

    for (final localSave in saves) {
      try {
        final outcome = await _syncOneFileBeforeLaunch(game, localSave);
        if (outcome == _SyncOutcome.downloaded) {
          downloaded++;
        } else if (outcome == _SyncOutcome.conflict) {
          conflicted++;
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    final status = conflicted > 0
        ? GameSyncStatus.conflict
        : GameSyncStatus.upToDate;
    _gameSyncStates[game.romname] = GameSyncState(
      gameId: game.romname,
      gameName: game.name,
      status: status,
      cloudEnabled: true,
      lastSync: DateTime.now(),
      errorMessage: lastError,
    );
    notifyListeners();

    return SyncResult.ok(
      message:
          'Downloaded $downloaded file(s)${conflicted > 0 ? ", $conflicted conflict(s)" : ""}',
    );
  }

  @override
  Future<SyncResult> detectGameSaveFiles(GameModel game) async {
    if (!isAuthenticated) {
      return SyncResult.fail(SyncError.authRequired);
    }

    final saves = await SaveDiscoveryService.instance.findSaveFilesForGame(game);
    if (saves.isEmpty) {
      _gameSyncStates[game.romname] = GameSyncState(
        gameId: game.romname,
        gameName: game.name,
        status: GameSyncStatus.noSaveFound,
        cloudEnabled: true,
      );
      notifyListeners();
      return SyncResult.ok();
    }

    // Pure inspection — no side-effects. Compute aggregate status.
    var anyConflict = false;
    var anyLocalOnly = false;
    var anyCloudOnly = false;
    var anyUpToDate = false;

    for (final localSave in saves) {
      final localFile = File(localSave.filePath);
      if (!await localFile.exists()) continue;

      final cfg = _config!;
      final remotePath = cfg.subdirectory.isEmpty
          ? '${game.romname}/${localSave.relativePath}'
          : '${cfg.subdirectory}/${game.romname}/${localSave.relativePath}';

      final remoteStat = await _connection!.stat(remotePath);
      if (remoteStat == null) {
        anyLocalOnly = true;
        continue;
      }

      final localStat = await localFile.stat();
      final localTime = localStat.modified.millisecondsSinceEpoch;
      final remoteTime = remoteStat.modifiedAt.millisecondsSinceEpoch;

      if ((localTime - remoteTime).abs() < 2000) {
        anyUpToDate = true;
        continue;
      }

      final synced = await SyncRepository.getSyncState(localSave.filePath);
      if (synced != null) {
        final syncedLocalMs = synced['local_modified_at'] as int? ?? 0;
        final syncedCloudMs = synced['cloud_updated_at'] as int? ?? 0;
        final localChanged = (localTime - syncedLocalMs).abs() > 2000;
        final cloudChanged = remoteTime > syncedCloudMs + 2000;
        if (localChanged && cloudChanged) {
          anyConflict = true;
        } else if (localChanged) {
          anyLocalOnly = true;
        } else if (cloudChanged) {
          anyCloudOnly = true;
        } else {
          anyUpToDate = true;
        }
      } else {
        // Unknown state — flag conservatively.
        anyConflict = true;
      }
    }

    final status = anyConflict
        ? GameSyncStatus.conflict
        : (anyLocalOnly && anyCloudOnly)
            ? GameSyncStatus.conflict
            : anyLocalOnly
                ? GameSyncStatus.localOnly
                : anyCloudOnly
                    ? GameSyncStatus.cloudOnly
                    : anyUpToDate
                        ? GameSyncStatus.upToDate
                        : GameSyncStatus.noSaveFound;

    _gameSyncStates[game.romname] = GameSyncState(
      gameId: game.romname,
      gameName: game.name,
      status: status,
      cloudEnabled: true,
    );
    notifyListeners();
    return SyncResult.ok();
  }

  @override
  GameSyncState? getGameSyncState(String gameId) => _gameSyncStates[gameId];

  @override
  Future<void> updateGameCloudSyncEnabled(
      String gameId, bool enabled) async {}

  @override
  Future<SyncResult> resolveConflict({
    required GameModel game,
    required bool useLocal,
  }) async {
    if (!isAuthenticated) {
      return SyncResult.fail(SyncError.authRequired, message: 'Not connected');
    }

    final saves = await SaveDiscoveryService.instance.findSaveFilesForGame(game);
    if (saves.isEmpty) {
      _gameSyncStates[game.romname] = GameSyncState(
        gameId: game.romname,
        gameName: game.name,
        status: GameSyncStatus.noSaveFound,
        cloudEnabled: true,
      );
      notifyListeners();
      return SyncResult.ok(message: 'No saves to resolve');
    }

    final cfg = _config!;
    int processed = 0;
    String? lastError;

    for (final localSave in saves) {
      try {
        final localFile = File(localSave.filePath);
        final remotePath = cfg.subdirectory.isEmpty
            ? '${game.romname}/${localSave.relativePath}'
            : '${cfg.subdirectory}/${game.romname}/${localSave.relativePath}';

        if (useLocal) {
          if (!await localFile.exists()) continue;
          final bytes = await localFile.readAsBytes();
          await _connection!.writeFile(remotePath, bytes);
          final localStat = await localFile.stat();
          await SyncRepository.saveSyncState(
            localSave.filePath,
            localStat.modified.millisecondsSinceEpoch,
            DateTime.now().millisecondsSinceEpoch,
            localStat.size,
          );
        } else {
          final remoteStat = await _connection!.stat(remotePath);
          if (remoteStat == null) continue;
          final bytes = await _connection!.readFile(remotePath);
          await localFile.parent.create(recursive: true);
          await localFile.writeAsBytes(bytes);
          await SyncRepository.saveSyncState(
            localSave.filePath,
            DateTime.now().millisecondsSinceEpoch,
            remoteStat.modifiedAt.millisecondsSinceEpoch,
            bytes.length,
          );
        }
        processed++;
      } catch (e) {
        lastError = e.toString();
      }
    }

    _gameSyncStates[game.romname] = GameSyncState(
      gameId: game.romname,
      gameName: game.name,
      status: GameSyncStatus.upToDate,
      cloudEnabled: true,
      lastSync: DateTime.now(),
      errorMessage: lastError,
    );
    notifyListeners();

    if (lastError != null) {
      return SyncResult.fail(SyncError.unknown, message: lastError);
    }
    return SyncResult.ok(
      message: 'Resolved $processed file(s) — kept ${useLocal ? "local" : "remote"}',
    );
  }

  // ── Per-file sync helpers ─────────────────────────────────────────────────

  /// After-play: bias toward upload (user just played and saved).
  Future<_SyncOutcome> _syncOneFileAfterPlay(
    GameModel game,
    LocalSaveFile localSave,
  ) async {
    final localFile = File(localSave.filePath);
    if (!await localFile.exists()) return _SyncOutcome.skippedUpToDate;

    final cfg = _config!;
    final remotePath = cfg.subdirectory.isEmpty
        ? '${game.romname}/${localSave.relativePath}'
        : '${cfg.subdirectory}/${game.romname}/${localSave.relativePath}';

    final localStat = await localFile.stat();
    final localTime = localStat.modified.millisecondsSinceEpoch;
    final localSize = localStat.size;
    final remoteStat = await _connection!.stat(remotePath);
    final synced = await SyncRepository.getSyncState(localSave.filePath);

    // Case A: no remote — just upload.
    if (remoteStat == null) {
      final bytes = await localFile.readAsBytes();
      await _connection!.writeFile(remotePath, bytes);
      await SyncRepository.saveSyncState(
        localSave.filePath,
        localTime,
        DateTime.now().millisecondsSinceEpoch,
        localSize,
      );
      return _SyncOutcome.uploaded;
    }

    // Case B: timestamps within 2s — up-to-date.
    final remoteTime = remoteStat.modifiedAt.millisecondsSinceEpoch;
    if ((localTime - remoteTime).abs() < 2000) {
      return _SyncOutcome.skippedUpToDate;
    }

    // Case C: persisted snapshot — figure out who changed.
    if (synced != null) {
      final syncedLocalMs = synced['local_modified_at'] as int? ?? 0;
      final syncedCloudMs = synced['cloud_updated_at'] as int? ?? 0;
      final localChanged = (localTime - syncedLocalMs).abs() > 2000;
      final cloudChanged = remoteTime > syncedCloudMs + 2000;

      if (localChanged && !cloudChanged) {
        final bytes = await localFile.readAsBytes();
        await _connection!.writeFile(remotePath, bytes);
        await SyncRepository.saveSyncState(
          localSave.filePath,
          localTime,
          DateTime.now().millisecondsSinceEpoch,
          localSize,
        );
        return _SyncOutcome.uploaded;
      }
      if (!localChanged && cloudChanged) {
        final bytes = await _connection!.readFile(remotePath);
        await localFile.writeAsBytes(bytes);
        await SyncRepository.saveSyncState(
          localSave.filePath,
          DateTime.now().millisecondsSinceEpoch,
          remoteTime,
          bytes.length,
        );
        return _SyncOutcome.downloaded;
      }
      if (localChanged && cloudChanged) {
        return _SyncOutcome.conflict;
      }
      return _SyncOutcome.skippedUpToDate;
    }

    // Case D: no snapshot, timestamps diverge — after-play biases toward
    // upload.
    if (localTime > remoteTime + 2000) {
      final bytes = await localFile.readAsBytes();
      await _connection!.writeFile(remotePath, bytes);
      await SyncRepository.saveSyncState(
        localSave.filePath,
        localTime,
        DateTime.now().millisecondsSinceEpoch,
        localSize,
      );
      return _SyncOutcome.uploaded;
    }
    // Local is older — leave remote alone; pre-launch hook will sync down.
    return _SyncOutcome.skippedUpToDate;
  }

  /// Before-launch: bias toward download (pull the latest save from the NAS).
  Future<_SyncOutcome> _syncOneFileBeforeLaunch(
    GameModel game,
    LocalSaveFile localSave,
  ) async {
    final localFile = File(localSave.filePath);
    final cfg = _config!;
    final remotePath = cfg.subdirectory.isEmpty
        ? '${game.romname}/${localSave.relativePath}'
        : '${cfg.subdirectory}/${game.romname}/${localSave.relativePath}';

    final remoteStat = await _connection!.stat(remotePath);
    // No remote — nothing to download.
    if (remoteStat == null) return _SyncOutcome.skippedUpToDate;

    final remoteTime = remoteStat.modifiedAt.millisecondsSinceEpoch;

    // If local doesn't exist, always download.
    if (!await localFile.exists()) {
      final bytes = await _connection!.readFile(remotePath);
      await localFile.parent.create(recursive: true);
      await localFile.writeAsBytes(bytes);
      await SyncRepository.saveSyncState(
        localSave.filePath,
        DateTime.now().millisecondsSinceEpoch,
        remoteTime,
        bytes.length,
      );
      return _SyncOutcome.downloaded;
    }

    final localStat = await localFile.stat();
    final localTime = localStat.modified.millisecondsSinceEpoch;

    // Timestamps within 2s — up-to-date.
    if ((localTime - remoteTime).abs() < 2000) {
      return _SyncOutcome.skippedUpToDate;
    }

    final synced = await SyncRepository.getSyncState(localSave.filePath);

    // Persisted snapshot — figure out who changed.
    if (synced != null) {
      final syncedLocalMs = synced['local_modified_at'] as int? ?? 0;
      final syncedCloudMs = synced['cloud_updated_at'] as int? ?? 0;
      final localChanged = (localTime - syncedLocalMs).abs() > 2000;
      final cloudChanged = remoteTime > syncedCloudMs + 2000;

      if (!localChanged && cloudChanged) {
        final bytes = await _connection!.readFile(remotePath);
        await localFile.writeAsBytes(bytes);
        await SyncRepository.saveSyncState(
          localSave.filePath,
          DateTime.now().millisecondsSinceEpoch,
          remoteTime,
          bytes.length,
        );
        return _SyncOutcome.downloaded;
      }
      if (localChanged && cloudChanged) {
        return _SyncOutcome.conflict;
      }
      if (localChanged && !cloudChanged) {
        // Local is newer — don't overwrite. After-close will upload.
        return _SyncOutcome.skippedUpToDate;
      }
      return _SyncOutcome.skippedUpToDate;
    }

    // No snapshot, timestamps diverge — before-launch biases toward download.
    if (remoteTime > localTime + 2000) {
      final bytes = await _connection!.readFile(remotePath);
      await localFile.writeAsBytes(bytes);
      await SyncRepository.saveSyncState(
        localSave.filePath,
        DateTime.now().millisecondsSinceEpoch,
        remoteTime,
        bytes.length,
      );
      return _SyncOutcome.downloaded;
    }
    // Local is newer — don't overwrite.
    return _SyncOutcome.skippedUpToDate;
  }
}

/// Internal outcome of a per-file sync operation.
enum _SyncOutcome { uploaded, downloaded, skippedUpToDate, conflict }
