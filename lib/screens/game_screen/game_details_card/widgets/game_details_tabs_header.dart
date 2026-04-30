import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/sfx_service.dart';

/// Defines the navigable sections within the game details card.
enum DetailTab { general, gameInfo, achievements, settings }

/// A navigation header component that manages tab switching and global card actions.
///
/// Features hardware-mapped bumper iconography (LB/RB) for intuitive gamepad
/// navigation and uses fluid animations for tab transitions. Dynamically adjusts
/// its layout based on the availability of metadata and system features.
class GameDetailsTabsHeader extends StatelessWidget {
  final bool isGameInfoHidden;
  final bool hasRetroAchievements;
  final bool showSettings;
  final DetailTab currentTab;
  final VoidCallback? onBack;
  final VoidCallback? onShowRandomGame;
  final ValueChanged<DetailTab> onTabChanged;

  const GameDetailsTabsHeader({
    super.key,
    required this.isGameInfoHidden,
    required this.hasRetroAchievements,
    required this.showSettings,
    required this.currentTab,
    this.onBack,
    this.onShowRandomGame,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Dynamically calculate the active tab count for layout arbitration.
    int numTabs = 1; // General is always present.
    if (!isGameInfoHidden) numTabs++;
    if (hasRetroAchievements) numTabs++;
    if (showSettings) numTabs++;

    final double tabWidth = 42.r;
    final double totalTabsWidth = numTabs * tabWidth;

    // Resolve the visual index for the cursor animation, accounting for hidden tabs.
    int visualIndex = 0;
    if (currentTab == DetailTab.gameInfo) {
      visualIndex = 1;
    } else if (currentTab == DetailTab.achievements) {
      visualIndex = isGameInfoHidden ? 1 : 2;
    } else if (currentTab == DetailTab.settings) {
      visualIndex = numTabs - 1;
    }

    final theme = Theme.of(context);

    return ClipRRect(
      child: Container(
        height: 46.r,
        padding: EdgeInsets.symmetric(horizontal: 12.r),
        child: Row(
          children: [
            // Termination Action: Revert to previous screen.
            if (onBack != null)
              _HeaderActionButton(
                icon: Image.asset(
                  'assets/images/gamepad/Xbox_B_button.png',
                  width: 14.r,
                  height: 14.r,
                ),
                label: AppLocale.back.getString(context).toUpperCase(),
                onTap: onBack!,
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
            if (onBack != null) SizedBox(width: 8.r),

            // Discovery Action: Trigger random selection.
            if (onShowRandomGame != null)
              _HeaderActionButton(
                icon: Image.asset(
                  'assets/images/gamepad/Xbox_View_button.png',
                  width: 14.r,
                  height: 14.r,
                  color: theme.colorScheme.onSurface,
                ),
                label: AppLocale.random.getString(context).toUpperCase(),
                onTap: onShowRandomGame!,
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: theme.colorScheme.tertiary,
              ),
            const Spacer(),

            // Tab Navigation Group: Hardware-mapped navigation controls.
            Container(
              height: 32.r,
              padding: EdgeInsets.symmetric(horizontal: 8.r),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 2.r,
                    offset: Offset(2.0.r, 2.0.r),
                  ),
                ],
              ),
              child: ClipRRect(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/gamepad/Xbox_LB_bumper.png',
                      width: 22.r,
                      height: 22.r,
                      color: theme.colorScheme.tertiary,
                    ),
                    SizedBox(width: 4.r),
                    SizedBox(
                      width: totalTabsWidth,
                      height: 36.r,
                      child: Stack(
                        children: [
                          // Transition Cursor: Fluidly follows the active selection.
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeInOut,
                            left: visualIndex * tabWidth,
                            top: 4.r,
                            bottom: 4.r,
                            width: tabWidth,
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondary,
                                borderRadius: BorderRadius.circular(4.r),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              _TabItem(
                                iconPath:
                                    'assets/images/icons/gamepad-bulk.png',
                                tab: DetailTab.general,
                                width: tabWidth,
                                isSelected: currentTab == DetailTab.general,
                                onTap: onTabChanged,
                              ),
                              if (!isGameInfoHidden)
                                _TabItem(
                                  iconPath:
                                      'assets/images/icons/image-bulk.png',
                                  tab: DetailTab.gameInfo,
                                  width: tabWidth,
                                  isSelected: currentTab == DetailTab.gameInfo,
                                  onTap: onTabChanged,
                                ),
                              if (hasRetroAchievements)
                                _TabItem(
                                  iconPath:
                                      'assets/images/icons/trophy-bulk.png',
                                  tab: DetailTab.achievements,
                                  width: tabWidth,
                                  isSelected:
                                      currentTab == DetailTab.achievements,
                                  onTap: onTabChanged,
                                ),
                              if (showSettings)
                                _TabItem(
                                  iconPath: 'assets/images/icons/gear-bulk.png',
                                  tab: DetailTab.settings,
                                  width: tabWidth,
                                  isSelected: currentTab == DetailTab.settings,
                                  onTap: onTabChanged,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 4.r),
                    Image.asset(
                      'assets/images/gamepad/Xbox_RB_bumper.png',
                      width: 22.r,
                      height: 22.r,
                      color: theme.colorScheme.tertiary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A button styled for the header bar that includes a gamepad button icon.
class _HeaderActionButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const _HeaderActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Play specialized SFX based on the action's intent.
          if (backgroundColor == theme.colorScheme.error) {
            SfxService().playBackSound();
          } else {
            SfxService().playNavSound();
          }
          onTap();
        },
        borderRadius: BorderRadius.circular(6.r),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 6.r),
          decoration: BoxDecoration(
            color: backgroundColor ?? theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(6.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 2.r,
                offset: Offset(2.0.r, 2.0.r),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColorFiltered(
                colorFilter: ColorFilter.mode(
                  foregroundColor ?? theme.colorScheme.onPrimary,
                  BlendMode.srcIn,
                ),
                child: icon,
              ),
              SizedBox(width: 2.r),
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor ?? theme.colorScheme.onPrimary,
                  fontSize: 10.r,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              SizedBox(width: 2.r),
            ],
          ),
        ),
      ),
    );
  }
}

/// An individual tab selector icon with click/tap handling.
class _TabItem extends StatelessWidget {
  final String iconPath;
  final DetailTab tab;
  final double width;
  final bool isSelected;
  final ValueChanged<DetailTab> onTap;

  const _TabItem({
    required this.iconPath,
    required this.tab,
    required this.width,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          SfxService().playNavSound();
          onTap(tab);
        },
        canRequestFocus: false,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        child: Container(
          width: width,
          height: 36.r,
          alignment: Alignment.center,
          child: Image.asset(
            iconPath,
            width: 18.r,
            height: 18.r,
            color: isSelected ? Colors.white : theme.colorScheme.tertiary,
          ),
        ),
      ),
    );
  }
}
