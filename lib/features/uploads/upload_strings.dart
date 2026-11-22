import 'package:flutter/widgets.dart';

class UploadStrings {
  const UploadStrings(this.romanian);

  factory UploadStrings.of(BuildContext context) =>
      UploadStrings(Localizations.localeOf(context).languageCode == 'ro');

  final bool romanian;

  String _text(String en, String ro) => romanian ? ro : en;
  String get upload => _text('Upload photos', 'Încarcă fotografiile');
  String get serial => _text('Serial number', 'Număr de serie');
  String get cancel => _text('Cancel', 'Anulează');
  String get retry => _text('Retry upload', 'Reîncearcă încărcarea');
  String get loading =>
      _text('Checking upload limits...', 'Se verifică limitele...');
  String get uploading => _text('Uploading...', 'Se încarcă...');
  String get saving =>
      _text('Waiting for confirmation...', 'Se așteaptă confirmarea...');
  String get success => _text('Upload saved', 'Încărcare salvată');
  String get retryNotice => _text(
    'The upload was not confirmed. Retry the same photos and serial number.',
    'Încărcarea nu a fost confirmată. Reîncearcă aceleași fotografii și același număr de serie.',
  );
  String get notice => _text(
    'Photos stay on this device until the server confirms the upload. '
        'Pending photos are lost if you reload or sign out.',
    'Fotografiile rămân pe acest dispozitiv până la confirmarea serverului. '
        'Fotografiile în așteptare se pierd la reîncărcare sau deconectare.',
  );
  String photoLimit(int count) => _text(
    'Maximum $count photos per upload.',
    'Maximum $count fotografii per încărcare.',
  );
  String saved(int count, String serial) => _text(
    '$count photos saved. Serial number: $serial',
    '$count fotografii salvate. Număr de serie: $serial',
  );

  String error(String code) => switch (code) {
    'invalid_serial_number' => _text(
      'Enter a valid serial number within the allowed length.',
      'Introdu un număr de serie valid, în limita de lungime.',
    ),
    'no_photos' => _text(
      'Take a photo first.',
      'Realizează mai întâi o fotografie.',
    ),
    'too_many_photos' => _text(
      'Too many photos. Remove some before uploading.',
      'Prea multe fotografii. Elimină câteva înainte de încărcare.',
    ),
    'upload_too_large' => _text(
      'The photos exceed the upload size limit. Remove some or use smaller photos.',
      'Fotografiile depășesc limita de încărcare. Elimină câteva sau folosește fotografii mai mici.',
    ),
    'session_expired' => _text(
      'Your session has expired. Sign in again.',
      'Sesiunea a expirat. Autentifică-te din nou.',
    ),
    'forbidden' => _text(
      'You do not have permission to upload. Complete your password change first.',
      'Nu ai permisiunea de încărcare. Finalizează mai întâi schimbarea parolei.',
    ),
    'csrf_invalid' => _text(
      'The request has expired. Try again.',
      'Cererea a expirat. Încearcă din nou.',
    ),
    'invalid_photo_time' => _text(
      'A photo has invalid capture or GPS timestamps. Remove it and take it again.',
      'O fotografie are ore de captură sau GPS nevalide. Elimin-o și realizeaz-o din nou.',
    ),
    'photo_not_ready' ||
    'invalid_photo' ||
    'invalid_photo_dimensions' ||
    'unsupported_photo_type' ||
    'stamped_jpeg_required' ||
    'photo_pair_required' => _text(
      'A photo is incomplete or invalid. Remove it and take it again.',
      'O fotografie este incompletă sau nevalidă. Elimin-o și realizeaz-o din nou.',
    ),
    'upload_id_conflict' => _text(
      'This upload ID already has different data. The photos were kept; contact your administrator.',
      'Acest ID de încărcare conține deja alte date. Fotografiile au fost păstrate; contactează administratorul.',
    ),
    _ => _text(
      'The upload could not be completed. Your photos have been kept. Try again.',
      'Încărcarea nu a putut fi finalizată. Fotografiile au fost păstrate. Încearcă din nou.',
    ),
  };
}
