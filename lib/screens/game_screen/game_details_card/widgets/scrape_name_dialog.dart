import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../l10n/app_locale.dart';
import '../../../../services/game_service.dart' show GamepadNavigationManager;
import '../../../../utils/gamepad_nav.dart';

/// Shows a modal dialog that lets the user edit the search name before a
/// ScreenScraper request. Returns the trimmed string on submit, or `null` if
/// the user cancels or dismisses the dialog.
///
/// [initialName] is what the field starts with (typically `_game.name`).
/// [resetName] is what the Reset button restores the field to (typically the
/// raw ROM filename ScreenScraper would search by default).
///
/// Pushes a dedicated gamepad layer for the lifetime of the dialog so that B
/// (or any "back" gesture from the gamepad) only closes the dialog, instead of
/// invoking the parent screen's onBack — which used to popLayer + Navigator.pop
/// in sequence and left the parent visible but with no active gamepad layer.
Future<String?> showScrapeNameDialog(
  BuildContext context, {
  required String initialName,
  required String resetName,
}) async {
  final navigatorState = Navigator.of(context);

  final dialogNav = GamepadNavigation(
    onBack: () {
      if (navigatorState.canPop()) navigatorState.pop();
    },
  );
  dialogNav.initialize();
  GamepadNavigationManager.pushLayer(
    'scrape_name_dialog',
    onActivate: dialogNav.activate,
    onDeactivate: dialogNav.deactivate,
  );

  try {
    return await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) =>
          _ScrapeNameDialog(initialName: initialName, resetName: resetName),
    );
  } finally {
    GamepadNavigationManager.popLayer('scrape_name_dialog');
    dialogNav.dispose();
  }
}

class _ScrapeNameDialog extends StatefulWidget {
  final String initialName;
  final String resetName;
  const _ScrapeNameDialog({required this.initialName, required this.resetName});

  @override
  State<_ScrapeNameDialog> createState() => _ScrapeNameDialogState();
}

class _ScrapeNameDialogState extends State<_ScrapeNameDialog> {
  late final TextEditingController _controller;
  bool _canSubmit = false;
  bool _canReset = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _canSubmit = widget.initialName.trim().isNotEmpty;
    _canReset = widget.initialName != widget.resetName;
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    final canSubmitNow = _controller.text.trim().isNotEmpty;
    final canResetNow = _controller.text != widget.resetName;
    if (canSubmitNow != _canSubmit || canResetNow != _canReset) {
      setState(() {
        _canSubmit = canSubmitNow;
        _canReset = canResetNow;
      });
    }
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  void _cancel() => Navigator.of(context).pop();

  void _reset() {
    _controller.text = widget.resetName;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: widget.resetName.length),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        AppLocale.scrapeDialogTitle.getString(context),
        style: TextStyle(fontSize: 16.sp),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 360.w),
        child: TextFormField(
          controller: _controller,
          maxLines: 1,
          textInputAction: TextInputAction.search,
          onFieldSubmitted: (_) {
            if (_canSubmit) _submit();
          },
          style: TextStyle(fontSize: 14.sp),
          decoration: InputDecoration(
            helperText: AppLocale.scrapeDialogHelper.getString(context),
            helperMaxLines: 2,
            helperStyle: TextStyle(fontSize: 11.sp),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12.w,
              vertical: 10.h,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancel,
          child: Text(AppLocale.cancel.getString(context)),
        ),
        TextButton(
          onPressed: _canReset ? _reset : null,
          child: Text(AppLocale.scrapeDialogReset.getString(context)),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(AppLocale.scrapeDialogSubmit.getString(context)),
        ),
      ],
    );
  }
}
