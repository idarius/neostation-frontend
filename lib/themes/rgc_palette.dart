import 'package:flutter/material.dart';

const Color _primaryColor = Color(0xE10083A4);
const Color _onPrimaryColor = Color(0xFFE9E9E9);
const Color _secondaryColor = Color(0xFF00ADD8); //0xFF00ADD8
const Color _onSecondaryColor = Color(0xFFE9E9E9);
const Color _tertiaryColor = Color(0xFF3B536B);
const Color _onTertiaryColor = Color(0xFFBDC3C7);
const Color _surfaceColor = Color(0xFFEBE2CA);
const Color _onSurfaceColor = Color(0xFF3B536B);
const Color _errorColor = Color(0xFFE74C3C);
const Color _onErrorColor = Color(0xFFE9E9E9);
const Color _outlineColor = Color(0xFFD1D1D1);
const Color _shadowColor = Color(0x1F000000);

const Color _backgroundColor = Color(0xFFDFD5B7);

const Color _batteryFull = Color(0xFF2D8C3C);
const Color _batteryMedium = Color(0xFFD16003);
const Color _batteryLow = Color(0xFFDC2626);
const Color _batteryPower = Color(0xFF0284C7);

final ThemeData rgcPalette = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.light(
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

class RGCCustomColors {
  Color get batteryFull => _batteryFull;
  Color get batteryMedium => _batteryMedium;
  Color get batteryLow => _batteryLow;
  Color get batteryPower => _batteryPower;
}
