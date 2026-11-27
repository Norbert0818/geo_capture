import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/models/photo_location.dart';
import 'package:geo_capture/features/capture/gps_quality.dart';

final gpsNow = DateTime.utc(2026, 11, 27, 12);
PhotoLocation gpsFix({
  DateTime? at,
  double accuracy = 4,
  double latitude = 47.181912,
}) => PhotoLocation(
  latitude: latitude,
  longitude: 23.165123,
  accuracyMeters: accuracy,
  measuredAt: at ?? gpsNow,
);

void main() {
  const policy = captureGpsPolicy;
  test(
    'default requires 5m, three fixes and a maximum age of three seconds',
        () {
      expect(policy.targetAccuracyMeters, 5);
      expect(policy.requiredGoodFixes, 3);
      expect(policy.maxAge, const Duration(seconds: 3));
    },
  );
  for (final value in [.4, 3.8, 5.0]) {
    test('accepts a fresh $value metre estimate', () {
      expect(policy.accepts(gpsFix(accuracy: value), gpsNow), isTrue);
    });
  }
  test('rejects weak and unknown zero accuracy', () {
    expect(policy.accepts(gpsFix(accuracy: 5.01), gpsNow), isFalse);
    expect(policy.accepts(gpsFix(accuracy: 0), gpsNow), isFalse);
  });
  test('accepts the age boundary but rejects an older sample', () {
    expect(
      policy.accepts(
        gpsFix(at: gpsNow.subtract(const Duration(seconds: 3))),
        gpsNow,
      ),
      isTrue,
    );
    expect(
      policy.accepts(
        gpsFix(at: gpsNow.subtract(const Duration(milliseconds: 3001))),
        gpsNow,
      ),
      isFalse,
    );
  });
  test('allows a small clock skew but rejects a far-future measurement', () {
    expect(
      policy.isFresh(
        gpsFix(at: gpsNow.add(const Duration(seconds: 1))),
        gpsNow,
      ),
      isTrue,
    );
    expect(
      policy.isFresh(
        gpsFix(at: gpsNow.add(const Duration(seconds: 2))),
        gpsNow,
      ),
      isFalse,
    );
  });
  test('a stricter developer policy changes the actual admission rule', () {
    const custom = GpsQualityPolicy(
      targetAccuracyMeters: 2,
      maxFixAgeSeconds: 1,
    );
    expect(custom.accepts(gpsFix(accuracy: 3), gpsNow), isFalse);
    expect(
      custom.accepts(
        gpsFix(accuracy: 1),
        gpsNow.add(const Duration(seconds: 2)),
      ),
      isFalse,
    );
    expect(custom.accepts(gpsFix(accuracy: 1), gpsNow), isTrue);
  });
}