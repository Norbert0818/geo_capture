import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/capture/camera_preview_cover.dart';

const camera = CameraDescription(
  name: 'test-camera',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

CameraValue value({
  Size size = const Size(1920, 1080),
  DeviceOrientation orientation = DeviceOrientation.portraitUp,
  DeviceOrientation? locked,
  DeviceOrientation? paused,
}) => CameraValue(
  isInitialized: true,
  previewSize: size,
  isRecordingVideo: false,
  isTakingPicture: false,
  isStreamingImages: false,
  isRecordingPaused: false,
  flashMode: FlashMode.off,
  exposureMode: ExposureMode.auto,
  focusMode: FocusMode.auto,
  exposurePointSupported: false,
  focusPointSupported: false,
  deviceOrientation: orientation,
  lockedCaptureOrientation: locked,
  previewPauseOrientation: paused,
  description: camera,
);

void main() {
  for (final orientation in DeviceOrientation.values) {
    test('preview ratio follows $orientation', () {
      final landscape =
          orientation == DeviceOrientation.landscapeLeft ||
              orientation == DeviceOrientation.landscapeRight;
      expect(
        cameraPreviewAspectRatio(value(orientation: orientation)),
        closeTo(landscape ? 16 / 9 : 9 / 16, .00001),
      );
    });
  }

  test('uninitialized preview has no usable ratio', () {
    expect(
      cameraPreviewAspectRatio(const CameraValue.uninitialized(camera)),
      isNull,
    );
  });

  test('a zero-sized camera frame is not used for layout', () {
    expect(cameraPreviewAspectRatio(value(size: Size.zero)), isNull);
  });

  test('locked capture orientation keeps the preview aligned', () {
    expect(
      cameraPreviewAspectRatio(value(locked: DeviceOrientation.landscapeLeft)),
      closeTo(16 / 9, .00001),
    );
  });

  test('paused preview uses its saved orientation before the capture lock', () {
    expect(
      cameraPreviewAspectRatio(
        value(
          locked: DeviceOrientation.landscapeLeft,
          paused: DeviceOrientation.portraitUp,
        ),
      ),
      closeTo(9 / 16, .00001),
    );
  });

  for (final entry in <Size, double>{
    const Size(390, 844): 9 / 16,
    const Size(844, 390): 4 / 3,
  }.entries) {
    testWidgets('preview covers ${entry.key} without stretching', (
        tester,
        ) async {
      tester.view.physicalSize = entry.key;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const childKey = ValueKey('cameraTexture');
      await tester.pumpWidget(
        MaterialApp(
          home: CameraPreviewCover(
            aspectRatio: entry.value,
            child: const ColoredBox(key: childKey, color: Colors.teal),
          ),
        ),
      );
      final frame = tester.getRect(find.byKey(childKey));
      expect(frame.left, lessThanOrEqualTo(.01));
      expect(frame.top, lessThanOrEqualTo(.01));
      expect(frame.right, greaterThanOrEqualTo(entry.key.width - .01));
      expect(frame.bottom, greaterThanOrEqualTo(entry.key.height - .01));
      expect(frame.width / frame.height, closeTo(entry.value, .00001));
      expect(frame.center.dx, closeTo(entry.key.width / 2, .01));
      expect(frame.center.dy, closeTo(entry.key.height / 2, .01));
      expect(tester.takeException(), isNull);
    });
  }
}