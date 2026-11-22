import 'package:flutter/widgets.dart';

class CaptureStrings {
  const CaptureStrings(this.romanian);

  final bool romanian;

  static CaptureStrings of(BuildContext context) =>
      CaptureStrings(Localizations.localeOf(context).languageCode == 'ro');

  String get photos => romanian ? 'Fotografii' : 'Photos';
  String get upload => romanian ? 'Încarcă' : 'Upload';
  String get close => romanian ? 'Închide' : 'Close';
  String photosCount(int count) => '$photos ($count)';
}