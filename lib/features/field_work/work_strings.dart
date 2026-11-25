import 'package:flutter/widgets.dart';
import 'work_models.dart';

class WorkStrings {
  WorkStrings(this.ro);
  final bool ro;
  factory WorkStrings.of(BuildContext context) =>
      WorkStrings(Localizations.localeOf(context).languageCode == 'ro');
  String text(String en, String romanian) => ro ? romanian : en;
  String get title => text('Field work', 'Lucrări pe teren');
  String kind(WorkKind value) => switch (value) {
    WorkKind.replacement => text('Replacement', 'Înlocuire'),
    WorkKind.repair => text('Repair', 'Remediere'),
    WorkKind.removal => text('Removal', 'Desființare'),
    WorkKind.pit => text('Pit', 'Groapă'),
  };
  String role(String value) => switch (value) {
    'old' => text('Old pole photo', 'Poză stâlp vechi'),
    'new' => text('New pole photo', 'Poză stâlp nou'),
    'before' => text('Before repair', 'Înainte de remediere'),
    'after' => text('After repair', 'După remediere'),
    'pole' => text('Pole photo', 'Poză stâlp'),
    _ => text('Pit photo', 'Poză groapă'),
  };
  String error(String? code) {
    if (code == null) return '';
    if (code.contains('work_conflict') ||
        code.contains('work_local_conflict')) {
      return text(
        'This work was changed elsewhere. Your local draft is preserved. Open the latest version from the work list before resolving the conflict.',
        'Lucrarea a fost modificată în altă parte. Ciorna locală este păstrată. Deschide ultima versiune din listă înainte de rezolvarea conflictului.',
      );
    }
    if (code.contains('work_local')) {
      return text(
        'The local draft could not be saved. Keep this page open and retry local saving.',
        'Ciorna locală nu a putut fi salvată. Păstrează pagina deschisă și reîncearcă salvarea locală.',
      );
    }
    if (code.contains('work_qr_generation_disabled')) {
      return text(
        'The administrator disabled QR generation. Scan an existing QR or enter the pole details again.',
        'Administratorul a dezactivat generarea QR. Scanează un cod existent sau introdu din nou datele stâlpului.',
      );
    }
    if (code.contains('too_large')) {
      return text(
        'The photos exceed the upload size limit.',
        'Fotografiile depășesc limita de încărcare.',
      );
    }
    if (code.contains('session_expired')) {
      return text(
        'Sign in again. Your local draft is preserved.',
        'Autentifică-te din nou. Ciorna locală este păstrată.',
      );
    }
    if (code.contains('work_invalid') ||
        code.contains('work_required') ||
        code.contains('work_serial')) {
      return text(
        'Check the required serial numbers, photos, locality and county.',
        'Verifică seriile, fotografiile, localitatea și județul obligatorii.',
      );
    }
    return text(
      'The action could not be completed. Your local draft is preserved; retry when the connection is available.',
      'Acțiunea nu a putut fi finalizată. Ciorna locală este păstrată; reîncearcă atunci când conexiunea este disponibilă.',
    );
  }

  String change(String key) => switch (key) {
    'created' => text('Created', 'Creată'),
    'kind' => text('Work type', 'Tip lucrare'),
    'oldPole' => text('Existing / old pole', 'Stâlp existent / vechi'),
    'newPole' => text('New pole', 'Stâlp nou'),
    'photos' => text('Photos or photo details', 'Fotografii sau detalii foto'),
    _ => text('Notes', 'Observații'),
  };
}