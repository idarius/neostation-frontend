import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_localization/flutter_localization.dart';

import '../l10n/app_locale.dart';
import '../models/system_model.dart';

/// Single source of truth for the synthetic 'recent' SystemModel.
///
/// The 'recent' system is not registered in `configProvider.detectedSystems`
/// (it's injected ad-hoc into the Console grid). This helper builds a
/// SystemModel from `assets/systems/recent.json` so the grid card and the
/// `MyGamesList` navigation share identical metadata.
class RecentSystemHelper {
  static SystemModel? _cached;

  /// Returns a SystemModel for the 'recent' virtual system. Loads
  /// `assets/systems/recent.json` once and caches the result.
  ///
  /// [context] is used to resolve the localized display name. If null,
  /// the JSON-provided English `name` is used as a fallback.
  static Future<SystemModel> getRecentSystemModel([
    BuildContext? context,
  ]) async {
    // Capture the localized name synchronously before any await so we don't
    // use BuildContext across an async gap (use_build_context_synchronously).
    final localizedName = context != null
        ? AppLocale.recentSystem.getString(context)
        : null;

    if (_cached != null) {
      return localizedName != null
          ? _cached!.copyWith(realName: localizedName)
          : _cached!;
    }

    final raw = await rootBundle.loadString('assets/systems/recent.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final sys = json['system'] as Map<String, dynamic>;
    final colors = (sys['colors'] as List).cast<String>();

    _cached = SystemModel(
      id: sys['id'] as String,
      folderName: 'recent',
      realName: sys['name'] as String,
      iconImage: '/images/icons/clock-bulk.png',
      color: colors.isNotEmpty ? colors.first : '#26A69A',
      color1: colors.isNotEmpty ? colors[0] : '#26A69A',
      color2: colors.length > 1 ? colors[1] : '#80CBC4',
      hideLogo: false,
      imageVersion: 0,
      romCount: 0,
      detected: true,
      shortName: sys['short_name'] as String?,
    );

    return localizedName != null
        ? _cached!.copyWith(realName: localizedName)
        : _cached!;
  }
}
