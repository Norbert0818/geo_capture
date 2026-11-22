import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Keeps interactive content outside system UI, with additional usable space.
class ControlSafeArea extends StatelessWidget {
  const ControlSafeArea({
    super.key,
    required this.child,
    this.spacing = const EdgeInsets.fromLTRB(16, 12, 16, 24),
    this.top = true,
    this.bottom = true,
    this.left = true,
    this.right = true,
  });

  final Widget child;
  final EdgeInsets spacing;
  final bool top;
  final bool bottom;
  final bool left;
  final bool right;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final gestures = data.systemGestureInsets;
    final padding = data.padding;
    final stable = data.viewPadding;
    final safe = EdgeInsets.fromLTRB(
      left ? math.max(gestures.left, math.max(padding.left, stable.left)) : 0,
      top ? math.max(gestures.top, math.max(padding.top, stable.top)) : 0,
      right
          ? math.max(gestures.right, math.max(padding.right, stable.right))
          : 0,
      bottom
          ? math.max(gestures.bottom, math.max(padding.bottom, stable.bottom))
          : 0,
    );

    EdgeInsets consumed(EdgeInsets value) => EdgeInsets.fromLTRB(
      left ? 0 : value.left,
      top ? 0 : value.top,
      right ? 0 : value.right,
      bottom ? 0 : value.bottom,
    );

    return Padding(
      padding: safe + spacing,
      child: MediaQuery(
        data: data.copyWith(
          padding: consumed(padding),
          viewPadding: consumed(stable),
          systemGestureInsets: consumed(gestures),
        ),
        child: child,
      ),
    );
  }
}