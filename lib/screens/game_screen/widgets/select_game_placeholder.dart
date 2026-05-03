import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';

/// Pure StatelessWidget rendering the right-panel placeholder shown when no
/// game is selected ("Select a game" / "Choose game from list" copy with a
/// muted controller icon).
class SelectGamePlaceholder extends StatelessWidget {
  const SelectGamePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64.r,
            height: 64.r,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.2),
                  Colors.white.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(32.r),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1.r,
              ),
            ),
            child: Icon(
              Icons.videogame_asset_outlined,
              size: 32.r,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          SizedBox(height: 16.r),
          Text(
            AppLocale.selectAGame.getString(context),
            style: TextStyle(
              fontSize: 18.r,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.7),
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 8.r),
          Text(
            AppLocale.chooseGameFromList.getString(context),
            style: TextStyle(
              fontSize: 14.r,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.5),
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
