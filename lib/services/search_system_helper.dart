import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_localization/flutter_localization.dart';

import '../l10n/app_locale.dart';
import '../models/system_model.dart';

/// Single source of truth for the synthetic 'search' SystemModel.
///
/// The 'search' system is not registered in `configProvider.detectedSystems`
/// (no card on the Console grid — invoked via the Y button). This helper
/// builds a SystemModel from `assets/systems/search.json` so the navigation
/// and the SystemGamesList share identical metadata.
class SearchSystemHelper {
  static SystemModel? _cached;

  /// Returns a SystemModel for the 'search' virtual system. Loads
  /// `assets/systems/search.json` once and caches the result.
  ///
  /// [context] is used to resolve the localized display name. If null,
  /// the JSON-provided English `name` is used as a fallback.
  static Future<SystemModel> getSearchSystemModel([
    BuildContext? context,
  ]) async {
    // Capture the localized name synchronously before any await so we don't
    // use BuildContext across an async gap (use_build_context_synchronously).
    final localizedName = context != null
        ? AppLocale.searchSystem.getString(context)
        : null;

    if (_cached != null) {
      return localizedName != null
          ? _cached!.copyWith(realName: localizedName)
          : _cached!;
    }

    final raw = await rootBundle.loadString('assets/systems/search.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final sys = json['system'] as Map<String, dynamic>;
    final colors = (sys['colors'] as List).cast<String>();

    _cached = SystemModel(
      id: sys['id'] as String,
      folderName: 'search',
      realName: sys['name'] as String,
      iconImage: '/images/icons/search-bulk.png',
      color: colors.isNotEmpty ? colors.first : '#5C6BC0',
      color1: colors.isNotEmpty ? colors[0] : '#5C6BC0',
      color2: colors.length > 1 ? colors[1] : '#9FA8DA',
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
