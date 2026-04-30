import 'package:flutter/material.dart';

const Color _primaryColor = Color(0xFF7273AC);
const Color _onPrimaryColor = Color(0xFF000000);
const Color _secondaryColor = Color(0xFF30D1A1);
const Color _onSecondaryColor = Color(0xFF000000);
const Color _tertiaryColor = Color(0xFFFFFFFF);
const Color _onTertiaryColor = Color(0xFF7E7E7E);
const Color _surfaceColor = Color(0xFF181818);
const Color _onSurfaceColor = Color(0xFFAFAFAF);
const Color _errorColor = Color(0xFFFF5861);
const Color _onErrorColor = Color(0xFF000000);
const Color _outlineColor = Color(0xFF3B3B3B);
const Color _shadowColor = Color(0xFF000000);

const Color _backgroundColor = Color(0xFF000000);

const Color _batteryFull = Color(0xFF10B981);
const Color _batteryMedium = Color(0xFFF59E0B);
const Color _batteryLow = Color(0xFFEF4444);
const Color _batteryPower = Color(0xFF3B82F6);

final ThemeData oledPalette = ThemeData(
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

class OledCustomColors {
  Color get batteryFull => _batteryFull;
  Color get batteryMedium => _batteryMedium;
  Color get batteryLow => _batteryLow;
  Color get batteryPower => _batteryPower;
}
