import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/models/photo_location.dart';

PhotoLocation makeLocation({
  double latitude = 47.1819234,
  double longitude = 23.1658476,
  double accuracyMeters = 5,
  DateTime? measuredAt,
}) {
  return PhotoLocation(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    measuredAt: measuredAt ?? DateTime.utc(2026, 11, 18, 10),
  );
}

void main() {
  group('PhotoLocation', () {
    test('formats both coordinates with six decimal places', () {
      expect(makeLocation().overlayText, '47.181923, 23.165848');
    });

    test('preserves trailing zeroes', () {
      expect(
        makeLocation(latitude: 47.1, longitude: 23).overlayText,
        '47.100000, 23.000000',
      );
    });

    test('preserves negative coordinates', () {
      expect(
        makeLocation(latitude: -33.865143, longitude: -70.5).overlayText,
        '-33.865143, -70.500000',
      );
    });

    test('does not display negative zero after rounding', () {
      expect(
        makeLocation(latitude: -0.0000001, longitude: 0).overlayText,
        '0.000000, 0.000000',
      );
    });

    test('accepts valid coordinate boundaries', () {
      expect(
        makeLocation(latitude: -90, longitude: -180).overlayText,
        '-90.000000, -180.000000',
      );

      expect(
        makeLocation(latitude: 90, longitude: 180).overlayText,
        '90.000000, 180.000000',
      );
    });

    test('rejects invalid latitudes', () {
      for (final value in [
        -90.000001,
        90.000001,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(() => makeLocation(latitude: value), throwsArgumentError);
      }
    });

    test('rejects invalid longitudes', () {
      for (final value in [
        -180.000001,
        180.000001,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(() => makeLocation(longitude: value), throwsArgumentError);
      }
    });

    test('rejects invalid GPS accuracy', () {
      for (final value in [
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(() => makeLocation(accuracyMeters: value), throwsArgumentError);
      }
    });

    test('stores the measurement time in UTC', () {
      final location = makeLocation(
        measuredAt: DateTime.parse('2026-11-18T20:15:00+02:00'),
      );

      expect(location.measuredAtUtc.isUtc, isTrue);

      expect(location.measuredAtUtc, DateTime.utc(2026, 11, 18, 18, 15));
    });
  });
}
