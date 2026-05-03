import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';

/// Pure StatelessWidget covering all 4 empty-state scenarios:
///
/// 1. Non-search system with zero ROMs → standard empty message + recursive
///    scan toggle + scan progress + back button.
/// 2. Search system, empty query → "type to search" message.
/// 3. Search system, query length < 2 → "minimum 2 characters" message.
/// 4. Search system, query length ≥ 2 with no matches → "no results" message.
///
/// Fork-private invariant: the 3 search-mode branches are gated on
/// system.folderName == 'search'.
class GamesEmptyState extends StatelessWidget {
  final SystemModel system;
  final String currentQuery;
  final VoidCallback onGoBack;
  final Future<void> Function(bool newValue) onToggleRecursiveScan;

  const GamesEmptyState({
    super.key,
    required this.system,
    required this.currentQuery,
    required this.onGoBack,
    required this.onToggleRecursiveScan,
  });

  @override
  Widget build(BuildContext context) {
    if (system.folderName == 'search') {
      return _buildSearchEmpty(context);
    }
    return _buildStandardEmpty(context);
  }

  Widget _buildSearchEmpty(BuildContext context) {
    final raw = currentQuery;
    final trimmed = raw.trim();
    final String message;
    if (trimmed.length < 2) {
      message = raw.isEmpty
          ? AppLocale.searchEmptyHint.getString(context)
          : AppLocale.searchMinLength.getString(context);
    } else {
      message = AppLocale.searchNoResults
          .getString(context)
          .replaceFirst('{query}', trimmed);
    }
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16.sp,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildStandardEmpty(BuildContext context) {
    bool currentScanValue = system.recursiveScan;
    final theme = Theme.of(context);

    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: 600.r),
        padding: EdgeInsets.symmetric(horizontal: 24.r, vertical: 16.r),
        margin: EdgeInsets.all(32.r),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.5),
              theme.colorScheme.secondary.withValues(alpha: 0.45),
            ],
          ),
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.3),
              blurRadius: 16.r,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.1),
              blurRadius: 32.r,
              offset: const Offset(0, 16),
            ),
          ],
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.15),
            width: 1.r,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocale.noGamesFoundFor
                  .getString(context)
                  .replaceFirst('{name}', system.shortName ?? system.realName),
              style: TextStyle(
                fontSize: 16.r,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4.r),
            Text(
              AppLocale.checkRomFiles.getString(context),
              style: TextStyle(
                fontSize: 11.r,
                fontWeight: FontWeight.w400,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.r),

            // Configuration Component: Recursive Library Scanning.
            StatefulBuilder(
              builder: (context, setStateBuilder) {
                return Column(
                  children: [
                    Container(
                      margin: EdgeInsets.only(bottom: 12.r),
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.r,
                        vertical: 8.r,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_shared_outlined,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 16.r,
                          ),
                          SizedBox(width: 8.r),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocale.recursiveScan.getString(context),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.r,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                AppLocale.recursiveScanSubtitle.getString(
                                  context,
                                ),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10.r,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(width: 16.r),
                          Switch(
                            value: currentScanValue,
                            activeThumbColor: theme.colorScheme.primary,
                            onChanged: (value) async {
                              setStateBuilder(() {
                                currentScanValue = value;
                              });
                              await onToggleRecursiveScan(value);
                            },
                          ),
                        ],
                      ),
                    ),

                    // Real-time Scan Progress Feedback.
                    Consumer<SqliteConfigProvider>(
                      builder: (context, provider, child) {
                        if (!provider.isScanning ||
                            provider.totalSystemsToScan <= 0) {
                          return const SizedBox.shrink();
                        }

                        return Container(
                          width: 320.r,
                          margin: EdgeInsets.only(bottom: 12.r),
                          padding: EdgeInsets.all(12.r),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.2,
                              ),
                              width: 1.r,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    provider.scanStatus,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10.r,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  Text(
                                    '${(provider.scanProgress * 100).toInt()}%',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10.r,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8.r),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4.r),
                                child: LinearProgressIndicator(
                                  value: provider.scanProgress,
                                  minHeight: 6.r,
                                  backgroundColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.1),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              SizedBox(height: 4.r),
                              Text(
                                AppLocale.scanningSystemOf
                                    .getString(context)
                                    .replaceFirst(
                                      '{current}',
                                      provider.scannedSystemsCount.toString(),
                                    )
                                    .replaceFirst(
                                      '{total}',
                                      provider.totalSystemsToScan.toString(),
                                    ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 9.r,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),

            // Navigation Component: Exit Action.
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onGoBack,
                borderRadius: BorderRadius.circular(8.r),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: EdgeInsets.only(
                      top: 4.r,
                      bottom: 4.r,
                      left: 8.r,
                      right: 12.r,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8.r),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.3,
                          ),
                          blurRadius: 8.r,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            'assets/images/gamepad/Xbox_B_button.png',
                            width: 18.r,
                            height: 18.r,
                          ),
                        ),
                        SizedBox(width: 6.r),
                        Text(
                          AppLocale.back.getString(context),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.r,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
