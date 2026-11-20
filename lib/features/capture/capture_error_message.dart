import '../../l10n/app_localizations.dart';

String captureErrorMessage(AppLocalizations t, String code) {
  final isRomanian = t.localeName.toLowerCase().startsWith('ro');

  return switch (code) {
    'camera_denied' =>
      isRomanian
          ? 'Permite accesul la cameră în setările dispozitivului sau ale browserului.'
          : 'Allow camera access in your device or browser settings.',
    'camera_unavailable' =>
      isRomanian
          ? 'Camera nu este disponibilă. Verifică dacă este folosită de altă aplicație.'
          : 'No camera is available. Check that another app is not using it.',
    'location_disabled' =>
      isRomanian
          ? 'Activează serviciile de localizare și încearcă din nou.'
          : 'Turn on location services and try again.',
    'location_denied' =>
      isRomanian
          ? 'Permite accesul la locație pentru a atașa coordonate fotografiilor.'
          : 'Allow location access to attach coordinates to your photos.',
    'location_timeout' =>
      isRomanian
          ? 'Locația nu a putut fi determinată la timp. Încearcă din nou.'
          : 'Location could not be determined in time. Try again.',
    'location_unavailable' =>
      isRomanian
          ? 'O locație recentă nu este disponibilă. Verifică accesul la locație și încearcă din nou.'
          : 'A recent location is unavailable. Check location access and try again.',
    'photo_processing_failed' =>
      isRomanian
          ? 'Coordonatele nu au putut fi adăugate pe fotografie. Încearcă să faci o nouă fotografie.'
          : 'Coordinates could not be added to the photo. Please take a new photo.',
    _ =>
      isRomanian
          ? 'Fotografia nu a putut fi realizată. Încearcă din nou.'
          : 'The photo could not be taken. Please try again.',
  };
}
