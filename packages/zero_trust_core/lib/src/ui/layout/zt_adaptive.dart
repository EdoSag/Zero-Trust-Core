import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/material.dart';

/// Window size classes (Material 3), for phone, foldable and tablet
/// layouts (S-11): compact below 600 dp, medium below 840 dp, expanded
/// from 840 dp.
enum ZtWindowClass {
  compact,
  medium,
  expanded;

  static ZtWindowClass forWidth(double width) => width < 600
      ? compact
      : width < 840
          ? medium
          : expanded;

  /// The class of the app's window.
  static ZtWindowClass of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);
}

/// Shared layout sizes.
abstract final class ZtLayout {
  /// The widest a column of text, a form or a settings list gets. Wider
  /// windows centre it, so lines stay readable on tablets and unfolded
  /// phones.
  static const double readableWidth = 720;

  /// Forms and single cards (sign-in, change email) are narrower still.
  static const double formWidth = 560;

  /// The list pane of a two-pane layout on a tablet without a hinge.
  static const double listPaneWidth = 360;

  /// [base] plus side padding that keeps content [maxWidth] wide and
  /// centred in [constraints].
  static EdgeInsets readablePadding(
    BoxConstraints constraints, {
    double maxWidth = readableWidth,
    EdgeInsets base = EdgeInsets.zero,
  }) {
    final inner = constraints.maxWidth - base.horizontal;
    final side =
        inner.isFinite && inner > maxWidth ? (inner - maxWidth) / 2 : 0.0;
    return base.copyWith(left: base.left + side, right: base.right + side);
  }

  /// A hinge or fold that splits the window into left and right halves
  /// (a book-style foldable, open), in window coordinates. Null on other
  /// devices, when folded flat into one screen, or for a horizontal fold.
  static Rect? verticalHinge(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    for (final f in MediaQuery.displayFeaturesOf(context)) {
      if (f.type == DisplayFeatureType.cutout ||
          f.type == DisplayFeatureType.unknown) {
        continue;
      }
      final b = f.bounds;
      if (b.height >= size.height * 0.9 &&
          b.width < size.width / 4 &&
          b.left > 0 &&
          b.right < size.width) {
        return b;
      }
    }
    return null;
  }
}

/// A [ListView] whose content stays [maxWidth] wide and centred on wide
/// windows, while scrolling still works across the whole width. Use it for
/// settings lists and forms instead of a plain [ListView].
class ZtReadableListView extends StatelessWidget {
  const ZtReadableListView({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.maxWidth = ZtLayout.readableWidth,
    this.controller,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final double maxWidth;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => ListView(
          controller: controller,
          padding: ZtLayout.readablePadding(constraints,
              maxWidth: maxWidth, base: padding),
          children: children,
        ),
      );
}

/// List and detail side by side where there is room (S-11):
/// - on a book-style foldable, open: one pane each side of the hinge, so
///   nothing sits under it;
/// - on an expanded window (tablet, desktop): the list [ZtLayout.listPaneWidth]
///   wide, the detail filling the rest;
/// - otherwise only [list]: the app opens the detail as its own page.
///   Check [showsBoth] to choose.
///
/// Follows the reading direction: in Hebrew the list is on the right.
class ZtTwoPane extends StatelessWidget {
  const ZtTwoPane({
    super.key,
    required this.list,
    required this.detail,
    this.listWidth = ZtLayout.listPaneWidth,
  });

  final Widget list;

  /// The selected item, or a placeholder ("Pick a note") when none is.
  final Widget detail;
  final double listWidth;

  /// Whether this window shows list and detail together.
  static bool showsBoth(BuildContext context) =>
      ZtLayout.verticalHinge(context) != null ||
      ZtWindowClass.of(context) == ZtWindowClass.expanded;

  @override
  Widget build(BuildContext context) {
    final hinge = ZtLayout.verticalHinge(context);
    final width = MediaQuery.sizeOf(context).width;
    return LayoutBuilder(builder: (context, constraints) {
      // The hinge is in window coordinates: only line up with it when this
      // layout fills the window's width.
      final fillsWindow = (constraints.maxWidth - width).abs() < 1;
      if (hinge != null && fillsWindow) {
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final startWidth = rtl ? width - hinge.right : hinge.left;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: startWidth, child: list),
            SizedBox(width: hinge.width),
            Expanded(child: detail),
          ],
        );
      }
      if (ZtWindowClass.forWidth(constraints.maxWidth) !=
          ZtWindowClass.expanded) {
        return list;
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
              width: math.min(listWidth, constraints.maxWidth / 2),
              child: list),
          const VerticalDivider(width: 1),
          Expanded(child: detail),
        ],
      );
    });
  }
}
