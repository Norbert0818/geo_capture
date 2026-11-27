import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'camera_controls_controller.dart';

class CameraControlsStrings {
  const CameraControlsStrings(this.romanian);
  final bool romanian;
  static CameraControlsStrings of(BuildContext context) =>
      CameraControlsStrings(
        Localizations.localeOf(context).languageCode == 'ro',
      );

  String get zoom => romanian ? 'Zoom cameră' : 'Camera zoom';
  String get noZoom => romanian ? 'Zoom indisponibil' : 'Zoom unavailable';
  String get autoFocus => romanian ? 'Focalizare automată' : 'Auto focus';
  String get noFocus => romanian
      ? 'Focalizarea la atingere nu este disponibilă'
      : 'Tap focus unavailable';
  String get focusHint => romanian
      ? 'Atinge imaginea pentru focalizare; folosește două degete pentru zoom.'
      : 'Tap to focus; pinch with two fingers to zoom.';
  String get noFlash => romanian ? 'Bliț indisponibil' : 'Flash unavailable';
  String flash(FlashMode mode) => switch (mode) {
    FlashMode.off => romanian ? 'Bliț oprit' : 'Flash off',
    FlashMode.auto => romanian ? 'Bliț automat' : 'Auto flash',
    FlashMode.always => romanian ? 'Bliț la fotografiere' : 'Flash on capture',
    FlashMode.torch => romanian ? 'Lumină continuă' : 'Torch',
  };
  String error(CameraControlError value) => switch (value) {
    CameraControlError.zoom =>
    romanian
        ? 'Zoomul nu a putut fi schimbat. Încearcă din nou.'
        : 'Could not change zoom. Try again.',
    CameraControlError.flash =>
    romanian
        ? 'Acest mod de bliț nu este disponibil. Alege alt mod.'
        : 'This flash mode is unavailable. Choose another mode.',
    CameraControlError.focus =>
    romanian
        ? 'Focalizarea nu a putut fi aplicată. Încearcă din nou.'
        : 'Could not apply focus. Try again.',
  };
}