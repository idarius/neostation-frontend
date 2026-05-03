/// Provider-agnostic save discovery facade.
///
/// Wraps NeoSyncProvider.findGameSaveFiles (formerly _findGameSaveFiles) so
/// that new sync providers (SMB, future Drive/RomM) can use the same save
/// discovery logic without depending on NeoSync internals. NeoSync itself
/// continues to call its own internals directly — no refactor of the existing
/// flow.
///
/// Lifecycle:
///   Call [SaveDiscoveryService.init] once in main() after NeoSyncProvider is
///   constructed, before any auto-trigger methods may fire.
library;

import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/neo_sync_models.dart';
import 'package:neostation/providers/neo_sync_provider.dart';

class SaveDiscoveryService {
  static SaveDiscoveryService? _instance;

  static SaveDiscoveryService get instance =>
      _instance ??= SaveDiscoveryService._();

  SaveDiscoveryService._();

  NeoSyncProvider? _neoSyncProvider;

  /// Must be called once at app startup (in main.dart) after [NeoSyncProvider]
  /// is constructed, so that [findSaveFilesForGame] has a live provider.
  // ignore: use_setters_to_change_properties
  void init(NeoSyncProvider provider) {
    _neoSyncProvider = provider;
  }

  /// Returns local save files matching [game] using NeoSync's discovery logic.
  ///
  /// Each [LocalSaveFile] carries: filePath, fileName, fileSize, lastModified,
  /// gameName, isSynced, and [LocalSaveFile.relativePath] (the cloud key path
  /// to use under `<subdir>/<game.id>/`).
  ///
  /// Returns an empty list if [init] has not been called or if no save files
  /// are found.
  Future<List<LocalSaveFile>> findSaveFilesForGame(GameModel game) async {
    final provider = _neoSyncProvider;
    if (provider == null) {
      // init() not yet called — safe no-op so callers don't crash at boot.
      return const [];
    }
    return provider.findGameSaveFiles(game);
  }
}
