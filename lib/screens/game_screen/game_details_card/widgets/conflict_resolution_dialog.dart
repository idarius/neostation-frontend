import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/utils/game_utils.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/neo_sync_models.dart';
import 'package:neostation/sync/i_sync_provider.dart';

/// A specialized dialog for resolving save-data conflicts between local and cloud storage providers.
///
/// Implements a Steam-style arbitration interface that allows users to compare modification
/// timestamps and select the authoritative version of their game progress.
class ConflictResolutionDialog extends StatefulWidget {
  final GameModel game;
  final GameSyncState gameState;
  final ISyncProvider syncProvider;

  const ConflictResolutionDialog({
    super.key,
    required this.game,
    required this.gameState,
    required this.syncProvider,
  });

  @override
  State<ConflictResolutionDialog> createState() {
    return _ConflictResolutionDialogState();
  }
}

class _ConflictResolutionDialogState extends State<ConflictResolutionDialog> {
  bool _isResolving = false;
  static final _log = LoggerService.instance;

  /// Executes the resolution logic by marking the selected version as authoritative.
  Future<void> _resolveConflict(bool useCloudVersion) async {
    setState(() {
      _isResolving = true;
    });

    try {
      final result = await widget.syncProvider.resolveConflict(
        game: widget.game,
        useLocal: !useCloudVersion,
      );

      if (mounted) {
        Navigator.of(context).pop();
        AppNotification.showNotification(
          context,
          result.success
              ? 'Conflict resolved - ${useCloudVersion ? "Cloud" : "Local"} version kept'
              : 'Failed to resolve conflict: ${result.message ?? "unknown error"}',
          type: result.success
              ? NotificationType.success
              : NotificationType.error,
        );
      }
    } catch (e) {
      _log.e('Conflict resolution operation failed: $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          'Failed to resolve conflict',
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResolving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localSave = widget.gameState.localSave;
    final cloudSave = widget.gameState.cloudSave;

    // Resolve human-readable timestamps for comparison.
    final localDate = localSave != null
        ? localSave.lastModified
        : DateTime.now();
    final cloudDate =
        cloudSave != null && cloudSave.fileModifiedAtTimestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(
            cloudSave.fileModifiedAtTimestamp!,
          )
        : DateTime.now();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 24.r, vertical: 24.r),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: screenSize.width * 0.85,
            constraints: BoxConstraints(maxHeight: screenSize.height * 0.85),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8.r,
                  offset: Offset(0, 4.r),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header: Warning status and game identity.
                Container(
                  padding: EdgeInsets.all(12.r),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16.r),
                      topRight: Radius.circular(16.r),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: colorScheme.error,
                        size: 28.r,
                      ),
                      SizedBox(width: 12.r),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Save Conflict Detected',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 18.r,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2.r),
                            Text(
                              GameUtils.formatGameName(widget.game.name),
                              style: TextStyle(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                                fontSize: 12.r,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Content: Arbitration prompt and option cards.
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(16.r),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'This game has different save files on your device and in the cloud. Which version would you like to keep?',
                          style: TextStyle(
                            color: colorScheme.onSurface
                                .withValues(alpha: 0.9),
                            fontSize: 14.r,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 16.r),

                        // Option A: Authority assigned to local storage.
                        _buildVersionCard(
                          context: context,
                          title:
                              AppLocale.localSave.getString(context),
                          subtitle: AppLocale.localSaveSubtitle
                              .getString(context),
                          date: localDate,
                          icon: Icons.phone_android,
                          color: colorScheme.primary,
                          onTap: _isResolving
                              ? null
                              : () {
                                  SfxService().playNavSound();
                                  _resolveConflict(false);
                                },
                        ),

                        SizedBox(height: 10.r),

                        // Option B: Authority assigned to cloud storage.
                        _buildVersionCard(
                          context: context,
                          title:
                              AppLocale.cloudSaveTitle.getString(context),
                          subtitle: AppLocale.cloudSaveSubtitle
                              .getString(context),
                          date: cloudDate,
                          icon: Icons.cloud,
                          color: colorScheme.tertiary,
                          onTap: _isResolving
                              ? null
                              : () {
                                  SfxService().playNavSound();
                                  _resolveConflict(true);
                                },
                        ),

                        SizedBox(height: 12.r),

                        // Termination Actions.
                        if (!_isResolving)
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              AppLocale.cancel.getString(context),
                              style: TextStyle(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                                fontSize: 14.r,
                              ),
                            ),
                          ),

                        // Transition/Loading State.
                        if (_isResolving)
                          Column(
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colorScheme.primary,
                                ),
                              ),
                              SizedBox(height: 8.r),
                              Text(
                                'Resolving conflict...',
                                style: TextStyle(
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                  fontSize: 12.r,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds a high-contrast card representing a candidate save-state for resolution.
  Widget _buildVersionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required DateTime date,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        canRequestFocus: false,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        onTap: onTap != null
            ? () {
                SfxService().playNavSound();
                onTap();
              }
            : null,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          padding: EdgeInsets.all(12.r),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.22),
                color.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: color.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.r),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(icon, color: color, size: 28.r),
              ),
              SizedBox(width: 12.r),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 15.r,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2.r),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.6),
                        fontSize: 11.r,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 3.r),
                    Text(
                      'Last modified: ${_formatDate(date)}',
                      style: TextStyle(
                        color: color,
                        fontSize: 11.r,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color, size: 22.r),
            ],
          ),
        ),
      ),
    );
  }

  /// Helper to convert raw modification dates into relative human-readable strings.
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
      }
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }
}
