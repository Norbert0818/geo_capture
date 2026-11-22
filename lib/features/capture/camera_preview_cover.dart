import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

double? cameraPreviewAspectRatio(CameraValue value) {
  final size = value.previewSize;
  if (!value.isInitialized ||
      size == null ||
      !size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    return null;
  }

  final orientation =
      (value.isRecordingVideo ? value.recordingOrientation : null) ??
          value.previewPauseOrientation ??
          value.lockedCaptureOrientation ??
          value.deviceOrientation;
  final landscape = switch (orientation) {
    DeviceOrientation.landscapeLeft || DeviceOrientation.landscapeRight => true,
    _ => false,
  };
  return landscape ? size.width / size.height : size.height / size.width;
}

class FullscreenCameraPreview extends StatelessWidget {
  const FullscreenCameraPreview({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final ratio = cameraPreviewAspectRatio(value);
        if (ratio == null) return const ColoredBox(color: Colors.black);
        return CameraPreviewCover(
          aspectRatio: ratio,
          child: CameraPreview(controller),
        );
      },
    );
  }
}

class CameraPreviewCover extends StatelessWidget {
  const CameraPreviewCover({
    super.key,
    required this.aspectRatio,
    required this.child,
  }) : assert(aspectRatio > 0 && aspectRatio < double.infinity);

  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight <= 0 || constraints.maxWidth <= 0) {
          return const SizedBox.shrink();
        }
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: constraints.maxHeight * aspectRatio,
              height: constraints.maxHeight,
              child: child,
            ),
          ),
        );
      },
    );
  }
}