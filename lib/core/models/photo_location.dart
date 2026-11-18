class PhotoLocation {
  PhotoLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required DateTime measuredAt,
  }) : measuredAtUtc = measuredAt.toUtc() {
    _validateCoordinate(latitude, 'latitude', 90);
    _validateCoordinate(longitude, 'longitude', 180);

    if (!accuracyMeters.isFinite || accuracyMeters < 0) {
      throw ArgumentError.value(
        accuracyMeters,
        'accuracyMeters',
        'Must be a finite, non-negative number.',
      );
    }
  }

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime measuredAtUtc;

  String get overlayText => '${_format(latitude)}, ${_format(longitude)}';

  static void _validateCoordinate(double value, String name, double limit) {
    if (!value.isFinite || value < -limit || value > limit) {
      throw ArgumentError.value(
        value,
        name,
        'Must be finite and between ${-limit} and $limit.',
      );
    }
  }

  static String _format(double value) {
    final formatted = value.toStringAsFixed(6);

    return formatted == '-0.000000' ? '0.000000' : formatted;
  }
}
