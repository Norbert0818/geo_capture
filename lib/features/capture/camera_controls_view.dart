import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_controls_controller.dart';
import 'camera_controls_strings.dart';

class CameraGesturePreview extends StatefulWidget {
  const CameraGesturePreview({
    super.key,
    required this.controls,
    required this.aspectRatio,
    required this.child,
    this.enabled = true,
  });
  final CameraControlsController controls;
  final double aspectRatio;
  final Widget child;
  final bool enabled;
  @override
  State<CameraGesturePreview> createState() => _CameraGesturePreviewState();
}

class _CameraGesturePreviewState extends State<CameraGesturePreview> {
  double _baseZoom = 1;
  Offset? _marker;
  Timer? _markerTimer;

  void _focus(TapUpDetails details, Size size) {
    final controls = widget.controls;
    if (!widget.enabled || !controls.focusAvailable || controls.busy) return;
    final point = cameraFocusPoint(
      details.localPosition,
      size,
      widget.aspectRatio,
    );
    if (point == null) return;
    _markerTimer?.cancel();
    setState(() => _marker = details.localPosition);
    _markerTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _marker = null);
    });
    unawaited(controls.focus(point));
  }

  @override
  void dispose() {
    _markerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      key: const ValueKey('cameraGestureArea'),
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => _focus(details, constraints.biggest),
      onScaleStart: (_) => _baseZoom = widget.controls.zoom,
      onScaleUpdate: (details) {
        if (widget.enabled && details.pointerCount >= 2) {
          unawaited(widget.controls.setZoom(_baseZoom * details.scale));
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_marker != null && widget.enabled)
            Positioned(
              left: (_marker!.dx - 28)
                  .clamp(
                0,
                (constraints.maxWidth - 56).clamp(0, double.infinity),
              )
                  .toDouble(),
              top: (_marker!.dy - 28)
                  .clamp(
                0,
                (constraints.maxHeight - 56).clamp(0, double.infinity),
              )
                  .toDouble(),
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('cameraFocusMarker'),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.amber, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class CameraControlPanel extends StatelessWidget {
  const CameraControlPanel({
    super.key,
    required this.controls,
    this.enabled = true,
  });
  final CameraControlsController controls;
  final bool enabled;

  IconData _flashIcon(FlashMode mode) => switch (mode) {
    FlashMode.off => Icons.flash_off,
    FlashMode.auto => Icons.flash_auto,
    FlashMode.always => Icons.flash_on,
    FlashMode.torch => Icons.flashlight_on,
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controls,
    builder: (context, _) {
      final s = CameraControlsStrings.of(context);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .68),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  PopupMenuButton<FlashMode>(
                    key: const ValueKey('cameraFlashMenu'),
                    tooltip: controls.flashAvailable
                        ? s.flash(controls.flashMode)
                        : s.noFlash,
                    enabled:
                    enabled && controls.flashAvailable && !controls.busy,
                    initialValue: controls.flashMode,
                    iconColor: Colors.white,
                    icon: Icon(_flashIcon(controls.flashMode)),
                    onSelected: (mode) => unawaited(controls.setFlash(mode)),
                    itemBuilder: (_) => [
                      for (final mode in FlashMode.values)
                        CheckedPopupMenuItem(
                          key: ValueKey('cameraFlash:${mode.name}'),
                          value: mode,
                          checked: controls.flashMode == mode,
                          child: Text(s.flash(mode)),
                        ),
                    ],
                  ),
                  Expanded(
                    child: Tooltip(
                      message: controls.zoomAvailable ? s.zoom : s.noZoom,
                      child: Slider(
                        key: const ValueKey('cameraZoomSlider'),
                        min: controls.minZoom,
                        max: controls.maxZoom,
                        value: controls.zoom,
                        label: '${controls.zoom.toStringAsFixed(1)}×',
                        semanticFormatterCallback: (value) =>
                        '${value.toStringAsFixed(1)}×',
                        onChanged: enabled && controls.zoomAvailable
                            ? (value) => unawaited(controls.setZoom(value))
                            : null,
                      ),
                    ),
                  ),
                  Semantics(
                    liveRegion: true,
                    label: s.zoom,
                    child: Text(
                      '${controls.zoom.toStringAsFixed(1)}×',
                      key: const ValueKey('cameraZoomValue'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('cameraAutoFocus'),
                    tooltip: controls.focusAvailable ? s.autoFocus : s.noFocus,
                    onPressed:
                    enabled && controls.focusAvailable && !controls.busy
                        ? () => unawaited(controls.focus(null))
                        : null,
                    color: Colors.white,
                    disabledColor: Colors.white38,
                    icon: const Icon(Icons.center_focus_strong),
                  ),
                ],
              ),
              if (controls.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    s.error(controls.error!),
                    key: const ValueKey('cameraControlError'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}