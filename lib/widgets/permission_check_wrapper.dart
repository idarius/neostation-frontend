import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:neostation/services/logger_service.dart';
import '../providers/sqlite_config_provider.dart';
import 'setup_wizard.dart';

/// Widget that checks the initial configuration and shows the wizard if necessary
class PermissionCheckWrapper extends StatefulWidget {
  final Widget child;

  const PermissionCheckWrapper({super.key, required this.child});

  @override
  State<PermissionCheckWrapper> createState() => _PermissionCheckWrapperState();
}

class _PermissionCheckWrapperState extends State<PermissionCheckWrapper> {
  bool _needsSetup = false;
  bool _isChecking = true;

  static final _log = LoggerService.instance;

  @override
  void initState() {
    super.initState();

    // Check whether initial configuration is needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialSetup();
    });
  }

  Future<void> _checkInitialSetup() async {
    try {
      final configProvider = Provider.of<SqliteConfigProvider>(
        context,
        listen: false,
      );

      // Wait for the provider to be initialized
      if (!configProvider.initialized) {
        await configProvider.initialize();
      }

      // We no longer force the wizard based solely on legacy storage permissions,
      // since we use SAF (Storage Access Framework) by default on Android.
      // The wizard will be shown if no folders are configured or if setup has not been completed.

      // Check whether a ROM folder is already configured OR if setup was already completed
      final hasRomFolder = configProvider.config.romFolder?.isNotEmpty == true;
      final setupCompleted = configProvider.config.setupCompleted;

      if (hasRomFolder || setupCompleted) {
        setState(() {
          _needsSetup = false;
          _isChecking = false;
        });
      } else {
        setState(() {
          _needsSetup = true;
          _isChecking = false;
        });
      }
    } catch (e) {
      _log.e('Error checking initial setup: $e');

      setState(() {
        _needsSetup = false;
        _isChecking = false;
      });
    }
  }

  void _completeSetup() async {
    // Persist that setup was completed
    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );
    await configProvider.completeSetup();

    setState(() {
      _needsSetup = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      // Show loading while checking
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_needsSetup) {
      // Show configuration wizard
      return SetupWizard(onComplete: _completeSetup);
    }

    // Show the normal app
    return widget.child;
  }
}
