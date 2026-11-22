import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

class HistoryStrings {
  const HistoryStrings(this.romanian);

  factory HistoryStrings.of(BuildContext context) =>
      HistoryStrings(Localizations.localeOf(context).languageCode == 'ro');

  final bool romanian;
  String _text(String en, String ro) => romanian ? ro : en;

  String get myUploads => _text('My uploads', 'Încărcările mele');
  String get allUploads => _text('All uploads', 'Toate încărcările');
  String get details => _text('Upload details', 'Detaliile încărcării');
  String get empty => _text('No uploads yet.', 'Nu există încărcări încă.');
  String get loading => _text('Loading...', 'Se încarcă...');
  String get retry => _text('Try again', 'Încearcă din nou');
  String get refresh => _text('Refresh', 'Reîmprospătează');
  String get previous => _text('Previous page', 'Pagina anterioară');
  String get next => _text('Next page', 'Pagina următoare');
  String get serial => _text('Serial number', 'Număr de serie');
  String get uploadedBy => _text('Uploaded by', 'Încărcat de');
  String get uploadedAt => _text('Uploaded at', 'Încărcat la');
  String get capturedAt => _text('Captured at', 'Fotografiat la');
  String get measuredAt => _text('GPS measured at', 'GPS măsurat la');
  String get accuracy => _text('GPS accuracy', 'Precizie GPS');
  String get original => _text('Original', 'Originală');
  String get stamped => _text('With coordinates', 'Cu coordonate');
  String get localTimes => _text(
    'Times are shown in your device’s local time.',
    'Orele sunt afișate în fusul orar al dispozitivului.',
  );
  String get readOnly => _text(
    'Saved uploads are read-only.',
    'Încărcările salvate pot fi doar vizualizate.',
  );
  String photos(int count) => _text('$count photos', '$count fotografii');
  String uploads(int count) => _text('$count uploads', '$count încărcări');
  String photo(int number) => _text('Photo $number', 'Fotografia $number');
  String page(int number, int total) =>
      _text('Page $number of $total', 'Pagina $number din $total');
  String date(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());
  String size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';

  String error(String code) => switch (code) {
    'session_expired' => _text(
      'Your session has expired. Sign in again.',
      'Sesiunea a expirat. Autentifică-te din nou.',
    ),
    'forbidden' => _text(
      'You do not have permission to view these uploads.',
      'Nu ai permisiunea de a vedea aceste încărcări.',
    ),
    'not_found' => _text(
      'This upload or photo is unavailable.',
      'Această încărcare sau fotografie nu este disponibilă.',
    ),
    _ => _text(
      'Could not load the data. Try again.',
      'Datele nu au putut fi încărcate. Încearcă din nou.',
    ),
  };
}
