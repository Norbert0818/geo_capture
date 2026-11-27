import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/models/photo_location.dart';
import 'gps_quality.dart';
import 'photo_capture_service.dart';
import 'photo_draft.dart';

abstract interface class GpsSource {
  Future<void> prepare();
  Future<bool?> hasPrecisePermission();
  Stream<PhotoLocation> watch();
}

class GeolocatorGpsSource implements GpsSource {
  @override
  Future<void> prepare() => PhotoCaptureService.prepareLocation();

  @override
  Future<bool?> hasPrecisePermission() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return null;
    }
    try {
      return await Geolocator.getLocationAccuracy() ==
          LocationAccuracyStatus.precise;
    } catch (_) {
      return null;
    }
  }

  static LocationSettings get settings {
    if (kIsWeb) {
      return WebSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        maximumAge: Duration.zero,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        maxUpdateAge: Duration.zero,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }

  @override
  Stream<PhotoLocation> watch() =>
      Geolocator.getPositionStream(locationSettings: settings).map(
            (position) => PhotoLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
          measuredAt: position.timestamp,
        ),
      );

  static Future<bool> openSettings(GpsStatus status) async {
    if (kIsWeb) return false;
    try {
      return status == GpsStatus.disabled
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }
}

class GpsController extends ChangeNotifier {
  GpsController(
      this.source, {
        this.policy = captureGpsPolicy,
        DateTime Function()? clock,
        this.tickInterval = const Duration(seconds: 1),
      }) : _clock = clock ?? DateTime.now;

  final GpsSource source;
  final GpsQualityPolicy policy;
  final DateTime Function() _clock;
  final Duration? tickInterval;
  Future<void> _lifecycle = Future<void>.value();
  StreamSubscription<PhotoLocation>? _subscription;
  Timer? _ticker;
  int _generation = 0;
  bool _running = false;
  bool _starting = false;
  bool _disposed = false;
  bool? _precisePermission;
  PhotoLocation? _latest;
  DateTime? _sessionStartedAt;
  String? _errorCode;
  int _goodFixes = 0;

  bool get running => _running;
  bool get starting => _starting;
  PhotoLocation? get latest => _latest;
  int get goodFixes => _goodFixes;
  bool get needsSettings => switch (status) {
    GpsStatus.approximate || GpsStatus.denied || GpsStatus.disabled => true,
    _ => false,
  };

  GpsStatus get status {
    if (!_running) return GpsStatus.stopped;
    if (_errorCode == 'location_denied') return GpsStatus.denied;
    if (_errorCode == 'location_disabled') return GpsStatus.disabled;
    if (_precisePermission == false) return GpsStatus.approximate;
    if (_errorCode != null) return GpsStatus.unavailable;
    final fix = _latest;
    if (fix == null) return GpsStatus.searching;
    if (!policy.isFresh(fix, _clock())) return GpsStatus.stale;
    if (!policy.accepts(fix, _clock())) return GpsStatus.weak;
    return _goodFixes >= policy.requiredGoodFixes
        ? GpsStatus.ready
        : GpsStatus.stabilizing;
  }

  bool get canCapture => status == GpsStatus.ready;

  PhotoLocation captureLocation() {
    // Recheck time at the shutter, even between the periodic UI refreshes.
    if (!canCapture) throw const CaptureException('gps_not_ready');
    return _latest!;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) =>
      !_disposed && _running && generation == _generation;

  void _clear() {
    _latest = null;
    _goodFixes = 0;
    _precisePermission = null;
    _sessionStartedAt = null;
    _errorCode = null;
  }

  Future<void> start() {
    if (_disposed) return Future<void>.value();
    final generation = ++_generation;
    final previous = _subscription;
    _subscription = null;
    _ticker?.cancel();
    _clear();
    _running = true;
    _starting = true;
    _changed();
    _lifecycle = _lifecycle.then((_) async {
      try {
        await previous?.cancel();
        if (!_current(generation)) return;
        await source.prepare();
        if (!_current(generation)) return;
        _precisePermission = await source.hasPrecisePermission();
        if (!_current(generation)) return;
        _sessionStartedAt = _clock().toUtc();
        _subscription = source.watch().listen(
              (fix) => _receive(fix, generation),
          onError: (Object failure) => _failed(failure, generation),
          onDone: () {
            if (_current(generation)) {
              _errorCode = 'location_unavailable';
              _goodFixes = 0;
              _changed();
            }
          },
        );
        if (tickInterval != null) {
          _ticker = Timer.periodic(tickInterval!, (_) => refresh());
        }
      } catch (failure) {
        _failed(failure, generation);
      } finally {
        if (_current(generation)) {
          _starting = false;
          _changed();
        }
      }
    });
    return _lifecycle;
  }

  void _receive(PhotoLocation fix, int generation) {
    if (!_current(generation)) return;
    if (fix.measuredAtUtc.difference(_clock().toUtc()) >
        Duration(seconds: policy.futureToleranceSeconds)) {
      _failed(const CaptureException('location_unavailable'), generation);
      return;
    }
    final previous = _latest;
    if (_sessionStartedAt == null ||
        fix.measuredAtUtc.isBefore(_sessionStartedAt!) ||
        (previous != null &&
            !fix.measuredAtUtc.isAfter(previous.measuredAtUtc))) {
      return;
    }
    final now = _clock().toUtc();
    final continuous =
        previous != null &&
            policy.accepts(previous, now) &&
            fix.measuredAtUtc.difference(previous.measuredAtUtc) <= policy.maxAge;
    _latest = fix;
    _errorCode = null;
    if (_precisePermission != false && policy.accepts(fix, now)) {
      _goodFixes = continuous ? _goodFixes + 1 : 1;
      if (_goodFixes > policy.requiredGoodFixes) {
        _goodFixes = policy.requiredGoodFixes;
      }
    } else {
      _goodFixes = 0;
    }
    _changed();
  }

  void _failed(Object failure, int generation) {
    if (!_current(generation)) return;
    _latest = null;
    _goodFixes = 0;
    _errorCode = switch (failure) {
      CaptureException(:final code) => code,
      PermissionDeniedException() => 'location_denied',
      LocationServiceDisabledException() => 'location_disabled',
      _ => 'location_unavailable',
    };
    _changed();
  }

  void refresh() {
    if (!_running || _disposed) return;
    if (_latest != null && !policy.isFresh(_latest!, _clock())) _goodFixes = 0;
    if (_latest == null &&
        _sessionStartedAt != null &&
        _clock().toUtc().difference(_sessionStartedAt!) >
            Duration(seconds: policy.firstFixTimeoutSeconds)) {
      _errorCode ??= 'location_timeout';
    }
    _changed();
  }

  Future<void> stop() {
    ++_generation;
    _running = false;
    _starting = false;
    _ticker?.cancel();
    _ticker = null;
    final previous = _subscription;
    _subscription = null;
    _clear();
    _changed();
    _lifecycle = _lifecycle.then((_) async {
      try {
        await previous?.cancel();
      } catch (_) {
        /* Already disconnected. */
      }
    });
    return _lifecycle;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}