import 'package:flutter/material.dart';

/// Change these defaults after finding the desired framing on the phone.
class CameraFraming {
  const CameraFraming({
    this.topPercent = 30,
    this.bottomPercent = 30,
    this.opacityPercent = 60,
  }) : assert(topPercent >= 0),
        assert(bottomPercent >= 0),
        assert(topPercent + bottomPercent <= 90),
        assert(opacityPercent >= 0 && opacityPercent <= 100);

  final int topPercent;
  final int bottomPercent;
  final int opacityPercent;

  int get clearPercent => 100 - topPercent - bottomPercent;

  CameraFraming copyWith({int? top, int? bottom, int? opacity}) =>
      CameraFraming(
        topPercent: top ?? topPercent,
        bottomPercent: bottom ?? bottomPercent,
        opacityPercent: opacity ?? opacityPercent,
      );
}

class CameraFramingOverlay extends StatelessWidget {
  const CameraFramingOverlay({super.key, required this.framing});

  final CameraFraming framing;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final color = Colors.black.withValues(
            alpha: framing.opacityPercent / 100,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: constraints.maxHeight * framing.topPercent / 100,
                child: ColoredBox(
                  key: const ValueKey('topFramingShade'),
                  color: color,
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: constraints.maxHeight * framing.bottomPercent / 100,
                child: ColoredBox(
                  key: const ValueKey('bottomFramingShade'),
                  color: color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}