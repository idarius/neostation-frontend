import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';

/// Pure StatelessWidget rendering the splash logo shown after the
/// _showLoadingSplash 150 ms gate fires. The gating logic stays in the
/// parent — only the rendering moves here.
class GamesLoadingState extends StatelessWidget {
  const GamesLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        padding: EdgeInsets.all(32.w),
        decoration: BoxDecoration(
          color: theme.cardColor.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
            width: 1.r,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64.r,
              height: 64.r,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(32.r),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 16.r,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.onSurface,
                  ),
                  strokeWidth: 3.r,
                ),
              ),
            ),
            SizedBox(height: 24.r),
            Text(
              AppLocale.loadingGames.getString(context),
              style: TextStyle(
                fontSize: 20.r,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 8.r),
            Text(
              AppLocale.preparingLibrary.getString(context),
              style: TextStyle(
                fontSize: 14.r,
                fontWeight: FontWeight.w400,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
