import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/capture/camera_controls_controller.dart';

class FakeCaptureCamera implements CaptureCameraDriver {
  @override
  bool ready = true;
  @override
  bool focusPointSupported = true;
  double low = .5;
  double high = 8;
  bool rangeFails = false;
  bool zoomFails = false;
  bool focusFails = false;
  final rejectedFlashModes = <FlashMode>{};
  final zooms = <double>[];
  final flashes = <FlashMode>[];
  final focusPoints = <Offset?>[];
  final operations = <String>[];
  Completer<void>? zoomGate;
  int active = 0;
  int maxActive = 0;

  @override
  Future<double> minZoom() async {
    if (rangeFails) throw CameraException('unsupported', 'zoom');
    return low;
  }

  @override
  Future<double> maxZoom() async => high;
  @override
  Future<void> zoom(double value) async {
    active++;
    if (active > maxActive) maxActive = active;
    try {
      zooms.add(value);
      operations.add('zoom:$value');
      if (zoomGate != null) await zoomGate!.future;
      if (zoomFails) throw CameraException('zoom', 'failed');
    } finally {
      active--;
    }
  }

  @override
  Future<void> flash(FlashMode mode) async {
    flashes.add(mode);
    operations.add('flash:${mode.name}');
    if (rejectedFlashModes.contains(mode)) {
      throw CameraException('flash', 'unsupported');
    }
  }

  @override
  Future<void> focus(Offset? point) async {
    focusPoints.add(point);
    if (focusFails) throw CameraException('focus', 'failed');
  }
}

void main() {
  late FakeCaptureCamera driver;
  late CameraControlsController controls;
  setUp(() {
    driver = FakeCaptureCamera();
    controls = CameraControlsController(driver);
  });
  tearDown(() async {
    driver.zoomGate?.complete();
    driver.zoomGate = null;
    await controls.shutdown();
    controls.dispose();
  });

  test(
    'reads actual hardware limits and starts at 1x with flash off',
        () async {
      await controls.initialize();
      expect(controls.initialized, isTrue);
      expect(controls.minZoom, .5);
      expect(controls.maxZoom, 8);
      expect(controls.zoom, 1);
      expect(controls.zoomAvailable, isTrue);
      expect(controls.focusAvailable, isTrue);
      expect(driver.flashes, [FlashMode.off]);
      expect(controls.busy, isFalse);
    },
  );

  test('fixed zoom range keeps capture, flash and focus usable', () async {
    driver.low = driver.high = 1;
    await controls.initialize();
    expect(controls.initialized, isTrue);
    expect(controls.zoomAvailable, isFalse);
    expect(controls.flashAvailable, isTrue);
    expect(controls.focusAvailable, isTrue);
  });

  test('unsupported zoom does not prevent the other controls', () async {
    driver.rangeFails = true;
    await controls.initialize();
    expect(controls.initialized, isTrue);
    expect(controls.zoomAvailable, isFalse);
    expect(controls.error, isNull);
    expect(controls.flashAvailable, isTrue);
  });

  for (final range in [
    (0.0, 2.0),
    (2.0, 1.0),
    (double.nan, 8.0),
    (1.0, double.infinity),
  ]) {
    test('rejects invalid zoom range $range', () async {
      driver.low = range.$1;
      driver.high = range.$2;
      await controls.initialize();
      expect(controls.zoomAvailable, isFalse);
      expect(controls.minZoom, 1);
      expect(controls.maxZoom, 1);
    });
  }

  test('clamps zoom to minimum and maximum reported by camera', () async {
    await controls.initialize();
    await controls.setZoom(-20);
    expect(controls.zoom, .5);
    await controls.setZoom(200);
    expect(controls.zoom, 8);
    expect(driver.zooms, [1, .5, 8]);
  });

  test('ignores nonfinite zoom and invalid focus coordinates', () async {
    await controls.initialize();
    await controls.setZoom(double.nan);
    await controls.setZoom(double.infinity);
    for (final point in [
      const Offset(-.1, .5),
      const Offset(.5, 1.1),
      const Offset(double.nan, .5),
    ]) {
      await controls.focus(point);
    }
    expect(driver.zooms, [1]);
    expect(driver.focusPoints, isEmpty);
  });

  test('a fast pinch coalesces intermediate values and never overlaps hardware changes', () async {
    await controls.initialize();
    driver.zoomGate = Completer<void>();
    final first = controls.setZoom(2);
    await Future<void>.delayed(Duration.zero);
    expect(controls.busy, isTrue);
    final middle = controls.setZoom(3);
    final latest = controls.setZoom(4);
    await controls.setFlash(FlashMode.torch);
    expect(driver.flashes, [FlashMode.off]);
    driver.zoomGate!.complete();
    driver.zoomGate = null;
    await Future.wait([first, middle, latest]);
    expect(driver.zooms, [1, 2, 4]);
    expect(controls.zoom, 4);
    expect(controls.busy, isFalse);
    expect(driver.maxActive, 1);
  });

  for (final mode in FlashMode.values) {
    test('applies flash mode ${mode.name}', () async {
      await controls.initialize();
      await controls.setFlash(mode);
      expect(controls.flashMode, mode);
      expect(driver.flashes.last, mode);
    });
  }

  test('unsupported flash hardware leaves the camera usable', () async {
    driver.rejectedFlashModes.add(FlashMode.off);
    await controls.initialize();
    expect(controls.initialized, isTrue);
    expect(controls.flashAvailable, isFalse);
    expect(controls.zoomAvailable, isTrue);
    await controls.setFlash(FlashMode.always);
    expect(driver.flashes, [FlashMode.off]);
  });

  test(
    'failed flash mode retains the previous setting and allows another choice',
        () async {
      await controls.initialize();
      driver.rejectedFlashModes.add(FlashMode.torch);
      await controls.setFlash(FlashMode.torch);
      expect(controls.error, CameraControlError.flash);
      expect(controls.flashMode, FlashMode.off);
      expect(controls.flashAvailable, isTrue);
      await controls.setFlash(FlashMode.always);
      expect(controls.error, isNull);
      expect(controls.flashMode, FlashMode.always);
    },
  );

  test('tap focus and restoring automatic focus reach the driver', () async {
    await controls.initialize();
    await controls.focus(const Offset(.25, .75));
    await controls.focus(null);
    expect(driver.focusPoints, [const Offset(.25, .75), null]);
  });

  test('a device without point focus ignores focus requests', () async {
    driver.focusPointSupported = false;
    await controls.initialize();
    await controls.focus(const Offset(.5, .5));
    expect(controls.focusAvailable, isFalse);
    expect(driver.focusPoints, isEmpty);
  });

  test('focus errors do not change flash or zoom', () async {
    await controls.initialize();
    driver.focusFails = true;
    await controls.focus(const Offset(.5, .5));
    expect(controls.error, CameraControlError.focus);
    expect(controls.zoom, 1);
    expect(controls.flashMode, FlashMode.off);
    expect(controls.busy, isFalse);
  });

  test('failed zoom restores last successfully applied value', () async {
    await controls.initialize();
    await controls.setZoom(2);
    driver.zoomFails = true;
    await controls.setZoom(4);
    expect(controls.zoom, 2);
    expect(controls.error, CameraControlError.zoom);
    expect(controls.busy, isFalse);
  });

  test(
    'shutdown waits for hardware then turns torch off and rejects late input',
        () async {
      await controls.initialize();
      await controls.setFlash(FlashMode.torch);
      driver.zoomGate = Completer<void>();
      final zooming = controls.setZoom(3);
      await Future<void>.delayed(Duration.zero);
      final closing = controls.shutdown();
      await controls.setZoom(5);
      await controls.setFlash(FlashMode.torch);
      expect(driver.operations.last, 'zoom:3.0');
      driver.zoomGate!.complete();
      driver.zoomGate = null;
      await Future.wait([zooming, closing]);
      expect(driver.operations.last, 'flash:off');
      expect(driver.zooms, [1, 3]);
      expect(controls.initialized, isFalse);
    },
  );

  test('portrait cover mapping includes horizontally cropped margins', () {
    expect(
      cameraFocusPoint(const Offset(0, 400), const Size(400, 800), .75),
      const Offset(1 / 6, .5),
    );
    expect(
      cameraFocusPoint(const Offset(200, 400), const Size(400, 800), .75),
      const Offset(.5, .5),
    );
  });

  test('landscape cover mapping includes vertically cropped margins', () {
    expect(
      cameraFocusPoint(const Offset(400, 0), const Size(800, 400), 4 / 3),
      const Offset(.5, 1 / 6),
    );
  });

  test('equal aspect ratio maps visible edges directly', () {
    expect(
      cameraFocusPoint(Offset.zero, const Size(400, 800), .5),
      Offset.zero,
    );
    expect(
      cameraFocusPoint(const Offset(400, 800), const Size(400, 800), .5),
      const Offset(1, 1),
    );
  });

  test('focus mapping rejects empty and invalid preview geometry', () {
    expect(cameraFocusPoint(Offset.zero, Size.zero, .5), isNull);
    expect(cameraFocusPoint(Offset.zero, const Size(400, 800), 0), isNull);
    expect(
      cameraFocusPoint(Offset.zero, const Size(400, 800), double.nan),
      isNull,
    );
  });
}