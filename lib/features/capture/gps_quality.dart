import '../../core/models/photo_location.dart';

// Developer settings: users do not change these on the camera screen.
const captureGpsPolicy = GpsQualityPolicy(
  targetAccuracyMeters: 5,
  requiredGoodFixes: 3,
  maxFixAgeSeconds: 3,
  firstFixTimeoutSeconds: 30,
);

class GpsQualityPolicy {
  const GpsQualityPolicy({
    this.targetAccuracyMeters = 5,
    this.requiredGoodFixes = 3,
    this.maxFixAgeSeconds = 3,
    this.firstFixTimeoutSeconds = 30,
    this.futureToleranceSeconds = 1,
  }) : assert(
  targetAccuracyMeters > 0 && targetAccuracyMeters < double.infinity,
  ),
        assert(requiredGoodFixes > 0),
        assert(maxFixAgeSeconds > 0),
        assert(firstFixTimeoutSeconds > 0),
        assert(futureToleranceSeconds >= 0);

  final double targetAccuracyMeters;
  final int requiredGoodFixes;
  final int maxFixAgeSeconds;
  final int firstFixTimeoutSeconds;
  final int futureToleranceSeconds;

  Duration get maxAge => Duration(seconds: maxFixAgeSeconds);

  bool isFresh(PhotoLocation location, DateTime now) =>
      now.toUtc().difference(location.measuredAtUtc) <= maxAge &&
          location.measuredAtUtc.difference(now.toUtc()) <=
              Duration(seconds: futureToleranceSeconds);

  bool accepts(PhotoLocation location, DateTime now) =>
      isFresh(location, now) &&
          location.accuracyMeters > 0 &&
          location.accuracyMeters <= targetAccuracyMeters;
}

enum GpsStatus {
  stopped,
  searching,
  stabilizing,
  ready,
  weak,
  stale,
  approximate,
  denied,
  disabled,
  unavailable,
}