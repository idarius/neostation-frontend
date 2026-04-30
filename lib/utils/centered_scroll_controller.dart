import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:neostation/main.dart' show FullscreenNotifier;
import 'package:neostation/services/logger_service.dart';

/// A custom controller designed to handle scrollable lists where a specific item
/// is always centered smoothly within the viewport.
///
/// Cross-platform behavior:
/// - Desktop: Utilizes [WindowListener] to handle maximization, restoration, and resizing.
/// - Mobile: Uses [WidgetsBindingObserver] to monitor orientation and screen metric changes.
/// - Synchronization: Forces UI rebuilds when the viewport changes and re-centers the active item.
class CenteredScrollController with WindowListener, WidgetsBindingObserver {
  /// The underlying [ScrollController] used by the ListView.
  final ScrollController scrollController;

  /// The relative position within the viewport (0.0 to 1.0) where items should center.
  /// Default is 0.5 (middle of the screen).
  final double centerPosition;

  /// Duration for centering animations.
  final Duration animationDuration;

  /// Animation curve used for centering transitions.
  final Curve animationCurve;

  static final _log = LoggerService.instance;

  Timer? _debounceTimer;
  int? _currentSelectedIndex;
  int _totalItems = 0;
  Size? _lastSize;

  /// Notifier to trigger manual rebuilds of the list when layout changes occur.
  final ValueNotifier<int> rebuildNotifier = ValueNotifier<int>(0);

  VoidCallback? _fullscreenListener;

  CenteredScrollController({
    ScrollController? scrollController,
    this.centerPosition = 0.5,
    this.animationDuration = const Duration(milliseconds: 360),
    this.animationCurve = Curves.easeInOut,
  }) : scrollController = scrollController ?? ScrollController();

  /// Initializes the controller and registers platform-specific listeners.
  void initialize({
    required BuildContext context,
    required int initialIndex,
    int? totalItems,
  }) {
    _currentSelectedIndex = initialIndex;
    _totalItems = totalItems ?? 0;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (!Platform.isLinux) {
        windowManager.addListener(this);
      }

      _fullscreenListener = () {
        _handleWindowStateChange();
      };
      FullscreenNotifier().addListener(_fullscreenListener!);
    }

    if (Platform.isAndroid || Platform.isIOS) {
      WidgetsBinding.instance.addObserver(this);
      _lastSize = MediaQuery.of(context).size;
    }

    // Perform an initial centering after the frame is rendered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (scrollController.hasClients) {
          scrollToIndex(initialIndex, immediate: true);
        }
      });
    });
  }

  @override
  void onWindowMaximize() {
    _handleWindowStateChange();
  }

  @override
  void onWindowUnmaximize() {
    _handleWindowStateChange();
  }

  @override
  void onWindowResized() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _handleWindowStateChange();
    });
  }

  @override
  void onWindowEnterFullScreen() {
    _handleWindowStateChange();
  }

  @override
  void onWindowLeaveFullScreen() {
    _handleWindowStateChange();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    if (Platform.isAndroid || Platform.isIOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;

        final currentSize = MediaQuery.of(
          scrollController.position.context.notificationContext!,
        ).size;

        if (_lastSize != null) {
          final widthChanged =
              (currentSize.width - _lastSize!.width).abs() > 10;
          final heightChanged =
              (currentSize.height - _lastSize!.height).abs() > 10;

          if (widthChanged || heightChanged) {
            _lastSize = currentSize;
            _handleWindowStateChange();
          }
        } else {
          _lastSize = currentSize;
        }
      });
    }
  }

  /// Triggers a re-centering logic when the window state or screen metrics change.
  void _handleWindowStateChange() {
    if (_currentSelectedIndex == null) {
      return;
    }

    rebuildNotifier.value++;

    // Sequential post-frame callbacks to ensure the layout has fully settled before re-centering.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 200), () {
            if (scrollController.hasClients && _currentSelectedIndex != null) {
              _performRecenter(_currentSelectedIndex!);
            }
          });
        });
      });
    });
  }

  /// Internal logic to calculate and execute the re-centering jump.
  void _performRecenter(int index) {
    if (!scrollController.hasClients || _totalItems == 0) {
      return;
    }

    try {
      final viewportHeight = scrollController.position.viewportDimension;
      final scrollableHeight = scrollController.position.maxScrollExtent;

      if (_totalItems <= 1 || scrollableHeight == 0) {
        return;
      }

      final contentHeight = scrollableHeight + viewportHeight;
      final itemHeight = contentHeight / _totalItems;
      final itemCenterPosition = (index * itemHeight) + (itemHeight / 2);
      final targetOffset =
          itemCenterPosition - (viewportHeight * centerPosition);

      final clampedOffset = targetOffset.clamp(
        0.0,
        scrollController.position.maxScrollExtent,
      );

      scrollController.jumpTo(clampedOffset);
    } catch (e) {
      _log.e('CenteredScrollController: Error during re-centering: $e');
    }
  }

  /// Scrolls the list to a specific index, ensuring it sits at the [centerPosition].
  void scrollToIndex(
    int index, {
    bool immediate = false,
    Duration? duration,
    Curve? curve,
  }) {
    if (!scrollController.hasClients || _totalItems == 0) {
      return;
    }

    _currentSelectedIndex = index;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;

      try {
        final viewportHeight = scrollController.position.viewportDimension;
        final scrollableHeight = scrollController.position.maxScrollExtent;

        if (_totalItems <= 1 || scrollableHeight == 0) {
          return;
        }

        final contentHeight = scrollableHeight + viewportHeight;
        final itemHeight = contentHeight / _totalItems;
        final itemCenterPosition = (index * itemHeight) + (itemHeight / 2);

        // Position target so that itemCenterPosition sits at centerPosition * viewportHeight from top.
        final targetOffset =
            itemCenterPosition - (viewportHeight * centerPosition);

        final clampedOffset = targetOffset.clamp(
          0.0,
          scrollController.position.maxScrollExtent,
        );

        if (immediate) {
          scrollController.jumpTo(clampedOffset);
        } else {
          scrollController.animateTo(
            clampedOffset,
            duration: duration ?? animationDuration,
            curve: curve ?? animationCurve,
          );
        }
      } catch (e) {
        _log.e('CenteredScrollController: Error scrolling to index: $e');
      }
    });
  }

  /// Calculates the index of the item currently closest to the [centerPosition].
  int? getCenteredItemIndex(int maxItems) {
    if (!scrollController.hasClients || _totalItems == 0 || maxItems == 0) {
      return null;
    }

    try {
      final viewportHeight = scrollController.position.viewportDimension;
      final currentOffset = scrollController.offset;
      final scrollableHeight = scrollController.position.maxScrollExtent;

      if (scrollableHeight == 0) {
        return 0;
      }

      final contentHeight = scrollableHeight + viewportHeight;
      final itemHeight = contentHeight / _totalItems;
      final centerPositionInContent =
          currentOffset + (viewportHeight * centerPosition);

      int closestIndex = 0;
      double closestDistance = double.infinity;

      for (int i = 0; i < _totalItems; i++) {
        final itemCenter = (i * itemHeight) + (itemHeight / 2);
        final distance = (itemCenter - centerPositionInContent).abs();

        if (distance < closestDistance) {
          closestDistance = distance;
          closestIndex = i;
        }
      }

      return closestIndex.clamp(0, maxItems - 1);
    } catch (e) {
      _log.e('CenteredScrollController: Error identifying centered index: $e');
      return null;
    }
  }

  /// Manually updates the tracked selected index without triggering a scroll.
  void updateSelectedIndex(int index) {
    _currentSelectedIndex = index;
  }

  /// Updates the total item count used for scroll calculations.
  void updateTotalItems(int totalItems) {
    _totalItems = totalItems;
  }

  /// Unregisters listeners and disposes of the underlying controller.
  void dispose() {
    _debounceTimer?.cancel();
    rebuildNotifier.dispose();

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (!Platform.isLinux) {
        windowManager.removeListener(this);
      }

      if (_fullscreenListener != null) {
        FullscreenNotifier().removeListener(_fullscreenListener!);
        _fullscreenListener = null;
      }
    }

    if (Platform.isAndroid || Platform.isIOS) {
      WidgetsBinding.instance.removeObserver(this);
    }

    scrollController.dispose();
  }
}
