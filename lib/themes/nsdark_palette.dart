import 'package:flutter/material.dart';

const Color _primaryColor = Color(0xFF7273AC);
const Color _onPrimaryColor = Color(0xFFEDF1FE);
const Color _secondaryColor = Color(0xFF30D1A1);
const Color _onSecondaryColor = Color(0xFF49495A);
const Color _tertiaryColor = Color(0xFFE0E5FF);
const Color _onTertiaryColor = Color(0xFF2E084D);
const Color _surfaceColor = Color(0xFF232030);
const Color _onSurfaceColor = Color(0xFF9B9BB4);
const Color _errorColor = Color(0xFFFF5252);
const Color _onErrorColor = Color(0xFFFFFFFF);
const Color _outlineColor = Color(0xFF50495A);
const Color _shadowColor = Color(0xFF000000);

const Color _backgroundColor = Color(0xFF1E1D24);

const Color _batteryFull = Color(0xFF66D9A7);
const Color _batteryMedium = Color(0xFFFFB84D);
const Color _batteryLow = Color(0xFFE53E3E);
const Color _batteryPower = Color(0xFF4A90B8);

final ThemeData nsdarkPalette = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.dark(
    primary: _primaryColor,
    secondary: _secondaryColor,
    tertiary: _tertiaryColor,
    surface: _surfaceColor,

    onPrimary: _onPrimaryColor,
    onSecondary: _onSecondaryColor,
    onTertiary: _onTertiaryColor,
    onSurface: _onSurfaceColor,

    error: _errorColor,
    onError: _onErrorColor,
    outline: _outlineColor,
    shadow: _shadowColor,
  ),

  cardColor: _backgroundColor,
  scaffoldBackgroundColor: _backgroundColor,

  textTheme: TextTheme(
    displayLarge: TextStyle(
      color: _onSurfaceColor,
      fontSize: 32,
      fontWeight: FontWeight.bold,
    ),
    titleLarge: TextStyle(
      color: _onSurfaceColor,
      fontSize: 24,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      color: _onSurfaceColor,
      fontSize: 18,
      fontWeight: FontWeight.w500,
    ),

    bodyLarge: TextStyle(color: _onSurfaceColor, fontSize: 16),
    bodyMedium: TextStyle(color: _onSurfaceColor, fontSize: 14),
    bodySmall: TextStyle(color: _onSurfaceColor, fontSize: 12),

    labelLarge: TextStyle(
      color: _onSurfaceColor,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
  ),
);

class NSdarkCustomColors {
  Color get batteryFull => _batteryFull;
  Color get batteryMedium => _batteryMedium;
  Color get batteryLow => _batteryLow;
  Color get batteryPower => _batteryPower;
}
