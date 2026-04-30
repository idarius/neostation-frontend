import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:neostation/providers/theme_provider.dart';

// Import all individual themes
import 'nsdark_palette.dart' as nsdark;
import 'nslight_palette.dart' as nslight;
import 'oled_palette.dart' as oled;
import 'valentine_palette.dart' as valentine;
import 'rgc_palette.dart' as rgc;
import 'tw_dark_palette.dart' as tw_dark;

class AppPalettes {
  static String getLogoPath(ThemeData palette) {
    // Check for specific theme instances before general brightness detection.
    if (palette == nsdarkPalette) {
      return 'assets/images/app/logo-nsdark.webp';
    } else if (palette == nslightPalette) {
      return 'assets/images/app/logo-nslight.webp';
    } else if (palette == oledPalette) {
      return 'assets/images/app/logo-oled.webp';
    } else if (palette == valentinePalette) {
      return 'assets/images/app/logo-valentine.webp';
    } else if (palette == rgcPalette) {
      return 'assets/images/app/logo-monochrome.webp';
    } else if (palette == twDarkPalette) {
      return 'assets/images/app/logo-monochrome.webp';
    } else {
      return 'assets/images/logo_transparent.png';
    }
  }

  static String getLogoPathByName(String paletteName) {
    switch (paletteName) {
      case 'nsdark':
        return 'assets/images/logo_transparent.png';
      case 'nslight':
        return 'assets/images/logo_transparent.png';
      case 'oled':
        return 'assets/images/logo_transparent.png';
      case 'valentine':
        return 'assets/images/logo_transparent.png';
      case 'rgc':
        return 'assets/images/logo_transparent.png';
      case 'tw_dark':
        return 'assets/images/logo_transparent.png';
      default:
        return 'assets/images/logo_transparent.png';
    }
  }

  // References to individual themes
  static ThemeData get nsdarkPalette => nsdark.nsdarkPalette;
  static ThemeData get nslightPalette => nslight.nslightPalette;
  static ThemeData get oledPalette => oled.oledPalette;
  static ThemeData get valentinePalette => valentine.valentinePalette;
  static ThemeData get rgcPalette => rgc.rgcPalette;
  static ThemeData get twDarkPalette => tw_dark.twDarkPalette;

  // References to custom colors for each theme
  static dynamic get nsdarkCustomColors => nsdark.NSdarkCustomColors();
  static dynamic get nslightCustomColors => nslight.NSlightCustomColors();
  static dynamic get oledCustomColors => oled.OledCustomColors();
  static dynamic get valentineCustomColors => valentine.ValentineCustomColors();
  static dynamic get rgcCustomColors => rgc.RGCCustomColors();
  static dynamic get twDarkCustomColors => tw_dark.TWCustomColors();

  /// Retrieves header colors based on the current context's theme.
  static dynamic getCustomColors(BuildContext context) {
    // Prefer detection by theme name if a ThemeProvider is available (more reliable).
    try {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      final themeName = themeProvider.currentThemeName;
      String resolvedThemeName = themeName;

      if (themeName == 'system') {
        final brightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        resolvedThemeName = brightness == Brightness.dark
            ? 'nsdark'
            : 'nslight';
      }

      switch (resolvedThemeName) {
        case 'nslight':
          return nslight.NSlightCustomColors();
        case 'oled':
          return oled.OledCustomColors();
        case 'valentine':
          return valentine.ValentineCustomColors();
        case 'rgc':
          return rgc.RGCCustomColors();
        case 'tw_dark':
          return tw_dark.TWCustomColors();
        default:
          return nsdark.NSdarkCustomColors();
      }
    } catch (_) {
      // Fallback to color comparison if provider is not available.
    }

    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surface;
    final secondary = scheme.secondary;

    // Compare with surface or secondary colors of each theme.
    if (surface == nslightPalette.colorScheme.surface ||
        secondary == nslightPalette.colorScheme.secondary) {
      return nslight.NSlightCustomColors();
    } else if (surface == oledPalette.colorScheme.surface ||
        secondary == oledPalette.colorScheme.secondary) {
      return oled.OledCustomColors();
    } else if (surface == valentinePalette.colorScheme.surface ||
        secondary == valentinePalette.colorScheme.secondary) {
      return valentine.ValentineCustomColors();
    } else if (surface == rgcPalette.colorScheme.surface ||
        secondary == rgcPalette.colorScheme.secondary) {
      return rgc.RGCCustomColors();
    } else if (surface == twDarkPalette.colorScheme.surface ||
        secondary == twDarkPalette.colorScheme.secondary) {
      return tw_dark.TWCustomColors();
    } else {
      return nsdark.NSdarkCustomColors();
    }
  }

  static ThemeData getThemeDataByName(String paletteName) {
    switch (paletteName) {
      case 'nsdark':
        return nsdarkPalette;
      case 'nslight':
        return nslightPalette;
      case 'oled':
        return oledPalette;
      case 'valentine':
        return valentinePalette;
      case 'rgc':
        return rgcPalette;
      case 'tw_dark':
        return twDarkPalette;
      default:
        return nsdarkPalette;
    }
  }
}
