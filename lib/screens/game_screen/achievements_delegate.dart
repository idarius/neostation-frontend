import 'package:flutter/foundation.dart';

/// Mutable delegate object collecting the achievements-overlay callbacks
/// registered by [GameDetailsCardList].
///
/// Replaces the previous spread of 6 nullable fields on [_SystemGamesListState]
/// (_isAchievementsOpen + _moveAchievement{Up,Down,Left,Right} +
/// _refreshAchievementsCallback) with a single object that can be passed
/// down to extracted widgets.
///
/// All fields are nullable until the achievements card registers itself
/// via the relevant [GameDetailsCardList] callbacks.
class AchievementsDelegate {
  /// Returns true when the achievements overlay is currently open.
  bool Function()? isOpen;

  /// Moves the achievements selection in the given direction.
  VoidCallback? moveUp;
  VoidCallback? moveDown;
  VoidCallback? moveLeft;
  VoidCallback? moveRight;

  /// Re-fetches achievements progress after a game has been played.
  VoidCallback? refresh;

  /// True if the overlay is open AND a navigation handler is wired.
  bool get isOpenAndNavigable {
    return (isOpen?.call() ?? false);
  }
}
