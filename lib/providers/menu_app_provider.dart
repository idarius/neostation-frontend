import 'package:flutter/material.dart';

class MenuAppProvider extends ChangeNotifier {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  void controlMenu() {
    if (!_scaffoldKey.currentState!.isDrawerOpen) {
      _scaffoldKey.currentState!.openDrawer();
    }
  }

  /// Set in [dispose] to short-circuit [notifyListeners] callbacks that
  /// resolve after the notifier has been torn down (late `await`s, async
  /// callbacks, etc.). Without this guard a setState-after-dispose throws
  /// in release builds and is silently swallowed in debug.
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
