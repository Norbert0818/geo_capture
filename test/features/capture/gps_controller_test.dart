import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geo_capture/core/models/photo_location.dart';
import 'package:geo_capture/features/capture/gps_controller.dart';
import 'package:geo_capture/features/capture/gps_quality.dart';
import 'package:geo_capture/features/capture/photo_capture_service.dart';
import 'package:geo_capture/features/capture/photo_draft.dart';

import 'gps_quality_test.dart' show gpsNow, gpsFix;

class FakeGpsSource implements GpsSource {
  bool? precise = true;
  Object? prepareError;
  Completer<void>? prepareGate;
  int preparations = 0;
  int cancellations = 0;
  final streams = <StreamController<PhotoLocation>>[];
  @override
  Future<void> prepare() async {
    preparations++;
    if (prepareGate != null) await prepareGate!.future;
    if (prepareError != null) throw prepareError!;
  }

  @override
  Future<bool?> hasPrecisePermission() async => precise;
  @override
  Stream<PhotoLocation> watch() {
    final stream = StreamController<PhotoLocation>(
      sync: true,
      onCancel: () {
        cancellations++;
      },
    );
    streams.add(stream);
    return stream.stream;
  }

  void emit(PhotoLocation fix) => streams.last.add(fix);
}

void main() {
  late FakeGpsSource source;
  late GpsController gps;
  late DateTime now;
  setUp(() {
    now = gpsNow;
    source = FakeGpsSource();
    gps = GpsController(source, clock: () => now, tickInterval: null);
  });
  tearDown(() async {
    if (source.prepareGate?.isCompleted == false) {
      source.prepareGate!.complete();
    }
    await gps.stop();
    gps.dispose();
    for (final stream in source.streams) {
      await stream.close();
    }
  });

  void fix({double accuracy = 4, double latitude = 47.181912}) {
    source.emit(gpsFix(at: now, accuracy: accuracy, latitude: latitude));
    now = now.add(const Duration(seconds: 1));
  }

  Future<void> ready() async {
    await gps.start();
    fix();
    fix();
    fix();
    expect(gps.canCapture, isTrue);
  }

  test('starts searching without reusing a stored location', () async {
    await gps.start();
    expect(gps.status, GpsStatus.searching);
    expect(gps.latest, isNull);
    expect(gps.canCapture, isFalse);
  });
  test('requires three distinct consecutive fresh good fixes', () async {
    await gps.start();
    fix();
    expect(gps.status, GpsStatus.stabilizing);
    fix();
    expect(gps.goodFixes, 2);
    fix();
    expect(gps.status, GpsStatus.ready);
    expect(
      gps.captureLocation().measuredAtUtc,
      gpsNow.add(const Duration(seconds: 2)),
    );
  });
  test(
    'an inaccurate new fix replaces an older good fix and resets readiness',
        () async {
      await ready();
      fix(accuracy: 12, latitude: 47.182);
      expect(gps.status, GpsStatus.weak);
      expect(gps.goodFixes, 0);
      expect(gps.latest!.latitude, 47.182);
      expect(gps.captureLocation, throwsA(isA<CaptureException>()));
    },
  );
  test('duplicate timestamps never increase the good-fix count', () async {
    await gps.start();
    source.emit(gpsFix());
    source.emit(gpsFix());
    source.emit(gpsFix());
    expect(gps.goodFixes, 1);
    expect(gps.canCapture, isFalse);
  });
  test('out of order locations cannot replace a newer measurement', () async {
    await gps.start();
    fix(latitude: 47.181);
    fix(latitude: 47.182);
    source.emit(gpsFix(latitude: 47.18));
    expect(gps.latest!.latitude, 47.182);
    expect(gps.goodFixes, 2);
  });
  test(
    'pre-session historical locations are ignored even within the age limit',
        () async {
      await gps.start();
      source.emit(gpsFix(at: now.subtract(const Duration(seconds: 1))));
      expect(gps.latest, isNull);
      expect(gps.status, GpsStatus.searching);
    },
  );
  test('capture rechecks age even before the UI ticker fires', () async {
    await ready();
    now = now.add(const Duration(seconds: 3));
    expect(gps.status, GpsStatus.stale);
    expect(
      gps.captureLocation,
      throwsA(
        isA<CaptureException>().having((e) => e.code, 'code', 'gps_not_ready'),
      ),
    );
  });
  test('a measurement gap requires three good fixes again', () async {
    await ready();
    now = now.add(const Duration(seconds: 5));
    fix();
    expect(gps.goodFixes, 1);
    expect(gps.canCapture, isFalse);
    fix();
    fix();
    expect(gps.canCapture, isTrue);
  });
  test(
    'periodic refresh exposes staleness and clears accumulated fixes',
        () async {
      await ready();
      now = now.add(const Duration(seconds: 4));
      gps.refresh();
      expect(gps.goodFixes, 0);
      expect(gps.status, GpsStatus.stale);
    },
  );
  test('a future-dated fix cannot poison later valid measurements', () async {
    await gps.start();
    source.emit(gpsFix(at: now.add(const Duration(minutes: 1))));
    expect(gps.canCapture, isFalse);
    expect(gps.latest, isNull);
    fix();
    fix();
    fix();
    expect(gps.canCapture, isTrue);
  });
  test('zero accuracy is treated as unusable rather than perfect', () async {
    await gps.start();
    fix(accuracy: 0);
    expect(gps.status, GpsStatus.weak);
    expect(gps.canCapture, isFalse);
  });
  test(
    'approximate permission blocks capture despite a small numerical estimate',
        () async {
      source.precise = false;
      await gps.start();
      fix(accuracy: 1);
      fix(accuracy: 1);
      fix(accuracy: 1);
      expect(gps.status, GpsStatus.approximate);
      expect(gps.needsSettings, isTrue);
      expect(gps.canCapture, isFalse);
    },
  );
  test(
    'platforms without a precision-permission API use reported quality',
        () async {
      source.precise = null;
      await ready();
      expect(gps.status, GpsStatus.ready);
    },
  );
  for (final entry in {
    'location_denied': GpsStatus.denied,
    'location_disabled': GpsStatus.disabled,
    'location_timeout': GpsStatus.unavailable,
  }.entries) {
    test(
      'preparation error ${entry.key} is actionable and blocks capture',
          () async {
        source.prepareError = CaptureException(entry.key);
        await gps.start();
        expect(gps.status, entry.value);
        expect(gps.starting, isFalse);
        expect(gps.canCapture, isFalse);
        expect(source.streams, isEmpty);
      },
    );
  }
  test(
    'no first fix times out visibly but a late valid stream can recover',
        () async {
      await gps.start();
      now = now.add(const Duration(seconds: 31));
      gps.refresh();
      expect(gps.status, GpsStatus.unavailable);
      fix();
      fix();
      fix();
      expect(gps.status, GpsStatus.ready);
    },
  );
  test(
    'stream errors invalidate an accepted location until fresh fixes arrive',
        () async {
      await ready();
      source.streams.last.addError(const LocationServiceDisabledException());
      expect(gps.status, GpsStatus.disabled);
      expect(gps.latest, isNull);
      fix();
      fix();
      fix();
      expect(gps.canCapture, isTrue);
    },
  );
  test('closing the position stream prevents further capture', () async {
    await ready();
    await source.streams.last.close();
    expect(gps.status, GpsStatus.unavailable);
    expect(gps.canCapture, isFalse);
  });
  test(
    'manual remeasurement cancels old stream and discards the old fix',
        () async {
      await ready();
      final old = source.streams.last;
      await gps.start();
      expect(source.cancellations, 1);
      expect(gps.latest, isNull);
      old.add(gpsFix(at: now));
      expect(gps.goodFixes, 0);
      fix();
      fix();
      fix();
      expect(gps.canCapture, isTrue);
    },
  );
  test(
    'background stop clears the fix and resume requires fresh stabilization',
        () async {
      await ready();
      await gps.stop();
      expect(gps.status, GpsStatus.stopped);
      expect(gps.latest, isNull);
      await gps.start();
      expect(gps.canCapture, isFalse);
      fix();
      fix();
      fix();
      expect(gps.canCapture, isTrue);
    },
  );
  test(
    'stopping while permission is pending cannot attach a late position stream',
        () async {
      source.prepareGate = Completer<void>();
      final starting = gps.start();
      await Future<void>.delayed(Duration.zero);
      final stopping = gps.stop();
      source.prepareGate!.complete();
      await Future.wait([starting, stopping]);
      expect(source.streams, isEmpty);
      expect(gps.status, GpsStatus.stopped);
    },
  );
  test('a custom target and sample count actually gate capture', () async {
    await gps.stop();
    gps.dispose();
    gps = GpsController(
      source,
      policy: const GpsQualityPolicy(
        targetAccuracyMeters: 2,
        requiredGoodFixes: 2,
      ),
      clock: () => now,
      tickInterval: null,
    );
    await gps.start();
    fix(accuracy: 3);
    expect(gps.canCapture, isFalse);
    fix(accuracy: 1);
    expect(gps.canCapture, isFalse);
    fix(accuracy: 1);
    expect(gps.canCapture, isTrue);
  });
  test(
    'the photo stores the exact approved location and accuracy snapshot',
        () async {
      await ready();
      final approved = gps.captureLocation();
      final capture = PhotoCaptureService(
        readLocation: () async => gps.captureLocation(),
        clock: () => now,
        newId: () => 'gps-photo',
      );
      final photo = await capture.capture(() async {
        fix(accuracy: 1, latitude: 47.183);
        return Uint8List.fromList([0xff, 0xd8, 0xff, 0x01]);
      });
      expect(identical(photo.location, approved), isTrue);
      expect(photo.location.accuracyMeters, 4);
      expect(gps.latest!.latitude, 47.183);
    },
  );
  test('an unapproved location never calls the camera shutter', () async {
    await gps.start();
    fix(accuracy: 20);
    var shutterCalls = 0;
    final capture = PhotoCaptureService(
      readLocation: () async => gps.captureLocation(),
      clock: () => now,
    );
    await expectLater(
      capture.capture(() async {
        shutterCalls++;
        return Uint8List(0);
      }),
      throwsA(isA<CaptureException>()),
    );
    expect(shutterCalls, 0);
  });
  test('Android requests high accuracy, frequent updates and no historical first fix', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final settings = GeolocatorGpsSource.settings as AndroidSettings;
    expect(settings.accuracy, LocationAccuracy.bestForNavigation);
    expect(settings.distanceFilter, 0);
    expect(settings.intervalDuration, const Duration(seconds: 1));
    expect(settings.maxUpdateAge, Duration.zero);
  });
}