import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Pure StatelessWidget rendering the rapid-scroll letter overlay.
///
/// Theme colors are passed in by the parent (which caches them in
/// didChangeDependencies for perf). Visibility is controlled by [isVisible]
/// and animated via AnimatedOpacity.
class LetterIndicator extends StatelessWidget {
  final String letter;
  final bool isVisible;
  final Color background;
  final Color border;
  final Color shadow;
  final Color textShadow;

  const LetterIndicator({
    super.key,
    required this.letter,
    required this.isVisible,
    required this.background,
    required this.border,
    required this.shadow,
    required this.textShadow,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: isVisible ? 1.0 : 0.0,
      child: RepaintBoundary(
        child: Center(
          child: Container(
            width: 120.r,
            height: 120.r,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(24.r),
              border: Border.all(color: border, width: 2.r),
              boxShadow: [
                BoxShadow(
                  color: shadow,
                  blurRadius: 30.r,
                  spreadRadius: 5.r,
                ),
              ],
            ),
            child: Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 72.r,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  shadows: [
                    Shadow(color: textShadow, blurRadius: 10.r),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
