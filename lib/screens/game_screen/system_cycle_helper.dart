import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/system_model.dart';
import '../../providers/sqlite_config_provider.dart';
import '../../services/recent_system_helper.dart';

/// Builds the ordered list of systems traversed by the L2/R2 shortcut on the
/// games list, and resolves the previous/next neighbour with wrap-around.
///
/// Cycle order mirrors the Console grid:
///   1. `recent` virtual system (when not hidden by user setting).
///   2. All visible detected systems — already filters out user-hidden folders
///      via `SqliteConfigProvider.visibleDetectedSystems`. Includes the `all`
///      virtual system.
///
/// Excluded:
///   - The single-game "Recent" card on the grid (launch shortcut, not a
///     system games list).
///   - The `android` system: it lives in a different screen
///     ([AndroidAppsGrid]) and the cycle reuses the same `SystemGamesList`
///     widget in-place; routing to a different screen mid-cycle would
///     reintroduce widget tear-down on every press.
///   - The `search` virtual system: cycling away would lose the typed
///     query. Excluded by [_cycleToNeighbourSystem] in `my_games_list.dart`,
///     not by this helper (the helper's cycle list never contains 'search'
///     since neither RecentSystemHelper nor visibleDetectedSystems return it).
class SystemCycleHelper {
  /// Returns systems in display order. Async because the `recent` virtual
  /// system is built from a JSON asset (cached after first load).
  static Future<List<SystemModel>> getOrderedSystems(
    BuildContext context,
  ) async {
    final config = context.read<SqliteConfigProvider>();
    final result = <SystemModel>[];

    if (!config.config.hideRecentSystem) {
      result.add(await RecentSystemHelper.getRecentSystemModel(context));
    }
    result.addAll(
      config.visibleDetectedSystems.where((s) => s.folderName != 'android'),
    );

    return result;
  }

  /// Returns the neighbour system in [forward] direction with wrap-around.
  /// Returns null if the cycle has fewer than 2 entries or [currentFolderName]
  /// is not in the cycle (defensive — should not happen in practice).
  static Future<SystemModel?> getNeighbour(
    BuildContext context,
    String currentFolderName, {
    required bool forward,
  }) async {
    final ordered = await getOrderedSystems(context);
    if (ordered.length < 2) return null;

    final idx = ordered.indexWhere((s) => s.folderName == currentFolderName);
    if (idx < 0) return null;

    final next = forward
        ? (idx + 1) % ordered.length
        : (idx - 1 + ordered.length) % ordered.length;
    return ordered[next];
  }
}
