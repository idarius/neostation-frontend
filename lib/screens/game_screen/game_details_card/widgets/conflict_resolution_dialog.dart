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
      // Logic for both paths currently converges on detectGameSaveFiles to refresh state.
      if (useCloudVersion) {
        await widget.syncProvider.detectGameSaveFiles(widget.game);
      } else {
        await widget.syncProvider.detectGameSaveFiles(widget.game);
      }

      if (mounted) {
        Navigator.of(context).pop();
        AppNotification.showNotification(
          context,
          'Conflict resolved - ${useCloudVersion ? "Cloud" : "Local"} version kept',
          type: NotificationType.success,
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

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: Colors.deepOrangeAccent.withValues(alpha: 0.5),
            width: 2.r,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 2.r,
              offset: Offset(2.0.r, 2.0.r),
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
                gradient: LinearGradient(
                  colors: [
                    Colors.deepOrangeAccent.withValues(alpha: 0.3),
                    Colors.deepOrangeAccent.withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16.r),
                  topRight: Radius.circular(16.r),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.deepOrangeAccent.withValues(alpha: 0.3),
                    width: 1.r,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning,
                    color: Colors.deepOrangeAccent,
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
                            color: Colors.white,
                            fontSize: 18.r,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2.r),
                        Text(
                          GameUtils.formatGameName(widget.game.name),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
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
            Padding(
              padding: EdgeInsets.all(16.r),
              child: Column(
                children: [
                  Text(
                    'This game has different save files on your device and in the cloud. Which version would you like to keep?',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14.r,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20.r),

                  // Option A: Authority assigned to local storage.
                  _buildVersionCard(
                    title: AppLocale.localSave.getString(context),
                    subtitle: AppLocale.localSaveSubtitle.getString(context),
                    date: localDate,
                    icon: Icons.phone_android,
                    color: Colors.blue,
                    onTap: _isResolving
                        ? null
                        : () {
                            SfxService().playNavSound();
                            _resolveConflict(false);
                          },
                  ),

                  SizedBox(height: 12.r),

                  // Option B: Authority assigned to cloud storage.
                  _buildVersionCard(
                    title: AppLocale.cloudSaveTitle.getString(context),
                    subtitle: AppLocale.cloudSaveSubtitle.getString(context),
                    date: cloudDate,
                    icon: Icons.cloud,
                    color: Colors.purple,
                    onTap: _isResolving
                        ? null
                        : () {
                            SfxService().playNavSound();
                            _resolveConflict(true);
                          },
                  ),

                  SizedBox(height: 16.r),

                  // Termination Actions.
                  if (!_isResolving)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        AppLocale.cancel.getString(context),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
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
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        SizedBox(height: 8.r),
                        Text(
                          'Resolving conflict...',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12.r,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a high-contrast card representing a candidate save-state for resolution.
  Widget _buildVersionCard({
    required String title,
    required String subtitle,
    required DateTime date,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
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
                color.withValues(alpha: 0.2),
                color.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 2.r),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.r),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(icon, color: color, size: 32.r),
              ),
              SizedBox(width: 12.r),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.r,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2.r),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12.r,
                      ),
                    ),
                    SizedBox(height: 4.r),
                    Text(
                      'Last modified: ${_formatDate(date)}',
                      style: TextStyle(
                        color: color,
                        fontSize: 12.r,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color, size: 24.r),
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
