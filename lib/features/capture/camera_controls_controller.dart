import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

abstract interface class CaptureCameraDriver {
  bool get ready;
  bool get focusPointSupported;
  Future<double> minZoom();
  Future<double> maxZoom();
  Future<void> zoom(double value);
  Future<void> flash(FlashMode mode);
  Future<void> focus(Offset? point);
}

class DeviceCaptureCameraDriver implements CaptureCameraDriver {
  DeviceCaptureCameraDriver(this.camera);
  final CameraController camera;

  @override
  bool get ready => camera.value.isInitialized;
  @override
  bool get focusPointSupported => camera.value.focusPointSupported;
  @override
  Future<double> minZoom() => camera.getMinZoomLevel();
  @override
  Future<double> maxZoom() => camera.getMaxZoomLevel();
  @override
  Future<void> zoom(double value) => camera.setZoomLevel(value);
  @override
  Future<void> flash(FlashMode mode) => camera.setFlashMode(mode);
  @override
  Future<void> focus(Offset? point) async {
    await camera.setFocusMode(FocusMode.auto);
    await camera.setFocusPoint(point);
  }
}

enum CameraControlError { zoom, flash, focus }

/// All hardware changes are serialized. A moving slider keeps just its latest
/// target, instead of queuing every intermediate gesture event.
class CameraControlsController extends ChangeNotifier {
  CameraControlsController(this.driver);
  final CaptureCameraDriver driver;

  Future<void> _tail = Future<void>.value();
  Future<void>? _zoomWork;
  Future<void>? _closeWork;
  double? _zoomTarget;
  double _appliedZoom = 1;
  int _pending = 0;
  bool _closed = false;
  bool _disposed = false;
  bool _initialized = false;
  bool _zoomAvailable = false;
  bool _flashAvailable = false;
  double _minZoom = 1;
  double _maxZoom = 1;
  FlashMode _flashMode = FlashMode.off;
  CameraControlError? _error;

  bool get initialized => _initialized && !_closed;
  bool get busy => _pending > 0;
  bool get zoomAvailable => initialized && _zoomAvailable;
  bool get flashAvailable => initialized && _flashAvailable;
  bool get focusAvailable => initialized && driver.focusPointSupported;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  double get zoom => _zoomTarget ?? _appliedZoom;
  FlashMode get flashMode => _flashMode;
  CameraControlError? get error => _error;

  void _changed() {
    if (!_disposed && !_closed) notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) {
    if (_closed) return Future<void>.value();
    _pending++;
    _changed();
    final work = _tail.then((_) async {
      try {
        if (!_closed && driver.ready) await action();
      } finally {
        _pending--;
        _changed();
      }
    });
    // Each public action handles hardware failures. This also keeps teardown
    // usable if a driver fails unexpectedly outside one of those actions.
    _tail = work.catchError((Object _) {});
    return _tail;
  }

  Future<void> initialize() => _run(() async {
    if (_initialized) return;
    try {
      final low = await driver.minZoom();
      final high = await driver.maxZoom();
      if (!low.isFinite || !high.isFinite || low <= 0 || high < low) {
        throw const FormatException('Invalid camera zoom range');
      }
      _minZoom = low;
      _maxZoom = high;
      _appliedZoom = 1.0.clamp(low, high).toDouble();
      await driver.zoom(_appliedZoom);
      _zoomAvailable = high > low;
    } catch (_) {
      _minZoom = _maxZoom = _appliedZoom = 1;
      _zoomAvailable = false;
    }
    if (_closed) return;
    try {
      await driver.flash(FlashMode.off);
      _flashAvailable = true;
    } catch (_) {
      _flashAvailable = false;
    }
    _initialized = true;
  });

  Future<void> setZoom(double requested) {
    if (!zoomAvailable || !requested.isFinite) {
      return Future<void>.value();
    }
    _zoomTarget = requested.clamp(_minZoom, _maxZoom).toDouble();
    _error = null;
    _changed();
    if (_zoomWork != null) return _zoomWork!;
    final work = _run(() async {
      while (!_closed && _zoomTarget != null) {
        final target = _zoomTarget!;
        try {
          await driver.zoom(target);
          _appliedZoom = target;
          if (_zoomTarget == target) _zoomTarget = null;
        } catch (_) {
          _zoomTarget = null;
          _error = CameraControlError.zoom;
          break;
        }
        _changed();
      }
    });
    _zoomWork = work.whenComplete(() {
      _zoomWork = null;
      _changed();
    });
    return _zoomWork!;
  }

  Future<void> setFlash(FlashMode mode) {
    if (!flashAvailable || busy) return Future<void>.value();
    _error = null;
    return _run(() async {
      try {
        await driver.flash(mode);
        _flashMode = mode;
      } catch (_) {
        // A phone can support normal flash while rejecting torch or auto.
        // Retain the last successfully applied mode and keep the other choices.
        _error = CameraControlError.flash;
      }
    });
  }

  Future<void> focus(Offset? point) {
    if (!focusAvailable || busy) return Future<void>.value();
    if (point != null &&
        (!point.dx.isFinite ||
            !point.dy.isFinite ||
            point.dx < 0 ||
            point.dx > 1 ||
            point.dy < 0 ||
            point.dy > 1)) {
      return Future<void>.value();
    }
    _error = null;
    return _run(() async {
      try {
        await driver.focus(point);
      } catch (_) {
        _error = CameraControlError.focus;
      }
    });
  }

  /// Call before releasing the CameraController. Pending changes finish first;
  /// no new request is accepted, and a torch is switched off before disposal.
  Future<void> shutdown() {
    if (_closeWork != null) return _closeWork!;
    _closed = true;
    _zoomTarget = null;
    _closeWork = _tail.then((_) async {
      try {
        if (driver.ready) await driver.flash(FlashMode.off);
      } catch (_) {
        // Camera disposal remains responsible for releasing the hardware.
      }
    });
    return _closeWork!;
  }

  @override
  void dispose() {
    _disposed = true;
    shutdown();
    super.dispose();
  }
}

/// Convert a tap on a centered BoxFit.cover preview to the full camera frame.
/// The aspect ratio must use the current display orientation, just like
/// FullscreenCameraPreview. The cropped-out margins are included in the result.
Offset? cameraFocusPoint(Offset tap, Size viewport, double aspectRatio) {
  if (!viewport.width.isFinite ||
      !viewport.height.isFinite ||
      viewport.width <= 0 ||
      viewport.height <= 0 ||
      !aspectRatio.isFinite ||
      aspectRatio <= 0 ||
      !tap.dx.isFinite ||
      !tap.dy.isFinite) {
    return null;
  }
  final width = math.max(viewport.width, viewport.height * aspectRatio);
  final height = width / aspectRatio;
  return Offset(
    ((tap.dx + (width - viewport.width) / 2) / width).clamp(0, 1).toDouble(),
    ((tap.dy + (height - viewport.height) / 2) / height).clamp(0, 1).toDouble(),
  );
}