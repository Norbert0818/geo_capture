import 'package:flutter/widgets.dart';

class UploadStrings {
  const UploadStrings(this.romanian);

  factory UploadStrings.of(BuildContext context) =>
      UploadStrings(Localizations.localeOf(context).languageCode == 'ro');

  final bool romanian;

  String _text(String en, String ro) => romanian ? ro : en;
  String get upload => _text('Upload photos', 'Încarcă fotografiile');
  String get serial => _text('Serial numbers', 'Numere de serie');
  String get oldSerial => _text('Old serial number', 'Număr de serie vechi');
  String get newSerial => _text('New serial number', 'Număr de serie nou');
  String get cancel => _text('Cancel', 'Anulează');
  String get retry => _text('Retry upload', 'Reîncearcă încărcarea');
  String get loading =>
      _text('Checking upload limits...', 'Se verifică limitele...');
  String get uploading => _text('Uploading...', 'Se încarcă...');
  String get saving =>
      _text('Waiting for confirmation...', 'Se așteaptă confirmarea...');
  String get success => _text('Upload saved', 'Încărcare salvată');
  String get retryNotice => _text(
    'The upload was not confirmed. Retry the same photos and both serial numbers.',
    'Încărcarea nu a fost confirmată. Reîncearcă aceleași fotografii și ambele numere de serie.',
  );
  String get notice => _text(
    'Photos are saved on this device until the server confirms the upload. '
        'Sign in with the same account to resume after restarting.',
    'Fotografiile sunt salvate pe acest dispozitiv până la confirmarea serverului. '
        'Autentifică-te cu același cont pentru a continua după repornire.',
  );
  String photoLimit(int count) => _text(
    'Maximum $count photos per upload.',
    'Maximum $count fotografii per încărcare.',
  );
  String saved(int count, String oldSerial, String newSerial) => _text(
    '$count photos saved. Old: $oldSerial. New: $newSerial',
    '$count fotografii salvate. Vechi: $oldSerial. Nou: $newSerial',
  );

  String error(String code) => switch (code) {
    'local_drafts_conflict' => _text(
      'Drafts changed in another window. Reload the saved drafts to continue.',
      'Ciornele au fost schimbate în altă fereastră. Reîncarcă ciornele salvate pentru a continua.',
    ),
    'local_drafts_invalid' ||
    'local_drafts_read_failed' ||
    'local_drafts_write_failed' => _text(
      'Local storage is unavailable. Keep the app open and use the local save controls.',
      'Stocarea locală nu este disponibilă. Păstrează aplicația deschisă și folosește opțiunile de salvare locală.',
    ),
    'invalid_old_serial_number' => _text(
      'Enter a valid old serial number within the allowed length.',
      'Introdu un număr de serie vechi valid, în limita de lungime.',
    ),
    'invalid_new_serial_number' => _text(
      'Enter a valid new serial number within the allowed length.',
      'Introdu un număr de serie nou valid, în limita de lungime.',
    ),
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