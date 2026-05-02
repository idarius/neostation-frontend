import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'core_footer.dart';

/// Specific footer for the systems screen
/// Inherits from CoreFooter to reuse common code
class GamepadFooter extends CoreFooter {
  const GamepadFooter({super.key});

  @override
  List<Widget> buildControls(BuildContext context) {
    final theme = Theme.of(context);

    return [
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_D-pad_ALL.png',
        label: AppLocale.hintNavigate.getString(context),
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_A_button.png',
        label: AppLocale.hintSelect.getString(context),
        textColor: Colors.white,
        backgroundColor: const Color(0xFF2ECC71),
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_Menu_button.png',
        label: AppLocale.hintSettings.getString(context),
        backgroundColor: theme.colorScheme.tertiary,
        textColor: theme.colorScheme.onTertiary,
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_B_button.png',
        label: AppLocale.hintBack.getString(context),
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.3,
        ),
        textColor: theme.colorScheme.onSurface,
      ),
    ];
  }
}
