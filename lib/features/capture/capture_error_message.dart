import '../../l10n/app_localizations.dart';

String captureErrorMessage(AppLocalizations t, String code) {
  return switch (code) {
    'camera_denied' => t.cameraPermissionDenied,
    'camera_unavailable' => t.cameraUnavailable,
    'location_disabled' => t.locationServicesDisabled,
    'location_denied' => t.locationPermissionDenied,
    'location_timeout' => t.locationTimeout,
    'location_unavailable' => t.locationUnavailable,
    _ => t.captureFailed,
  };
}