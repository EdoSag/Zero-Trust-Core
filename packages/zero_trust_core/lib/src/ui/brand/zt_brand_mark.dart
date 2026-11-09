import 'package:flutter/material.dart';

import '../../config/zt_suite.dart';
import '../theme/zt_theme.dart';

/// The suite's app mark: a rounded square in the brand indigo blending into
/// the app's accent, with the app's symbol. Used on sign-in and unlock, in
/// onboarding, and for each app in "Other Zero-Trust apps", so every app
/// looks like part of one family.
class ZtBrandMark extends StatelessWidget {
  const ZtBrandMark({super.key, this.app, this.size = 64, this.icon});

  /// Null shows the suite's shield.
  final ZtSuiteApp? app;
  final double size;

  /// Overrides the app's symbol, for example a lock on the unlock screen.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final accent = app?.accent ?? ZtTheme.brandSeed;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ZtTheme.brandSeed,
              Color.lerp(ZtTheme.brandSeed, accent, 0.75)!
            ],
          ),
        ),
        child: Icon(icon ?? app?.icon ?? Icons.shield_outlined,
            size: size * 0.5, color: Colors.white),
      ),
    );
  }
}
