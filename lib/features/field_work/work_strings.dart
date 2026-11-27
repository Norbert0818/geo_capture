import 'package:flutter/widgets.dart';

import 'work_models.dart';

class WorkStrings {
  WorkStrings(this.ro);
  final bool ro;
  factory WorkStrings.of(BuildContext context) =>
      WorkStrings(Localizations.localeOf(context).languageCode == 'ro');
  String text(String en, String romanian) => ro ? romanian : en;
  String get title => text('Field work', 'Lucrări pe teren');
  String serial(String? number, String? state) {
    if (number?.isNotEmpty == true) {
      return state == 'damaged'
          ? '$number · ${text('Damaged label', 'Etichetă deteriorată')}'
          : number!;
    }
    return switch (state) {
      'missing' => text('No serial number', 'Fără număr de serie'),
      'damaged' => text('Damaged label', 'Etichetă deteriorată'),
      _ => text('Serial not recorded yet', 'Seria nu este încă înregistrată'),
    };
  }

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
    'old_label' => text('Old pole label', 'Eticheta stâlpului vechi'),
    'new_label' => text('New pole label', 'Eticheta stâlpului nou'),
    'label' => text('Pole label', 'Eticheta stâlpului'),
    _ => text('Pit photo', 'Poză groapă'),
  };
  String error(String? code) {
    if (code == null) return '';
    if (code.contains('work_serial_decision_required')) {
      return text(
        'Confirm whether a serial exists, is missing or damaged.',
        'Confirmă dacă seria există, lipsește sau eticheta este deteriorată.',
      );
    }
    if (code.contains('work_invalid_place')) {
      return text(
        'The selected locality does not match its county.',
        'Localitatea selectată nu corespunde județului.',
      );
    }
    if (code.contains('work_catalogue_unavailable')) {
      return text(
        'The locality catalogue is unavailable. Try again later.',
        'Catalogul localităților nu este disponibil. Reîncearcă ulterior.',
      );
    }
    if (code.contains('work_invalid_serial_evidence')) {
      return text(
        'Confirm the serial using a photo from the correct pole.',
        'Confirmă seria folosind o fotografie a stâlpului corect.',
      );
    }
    if (code.contains('work_export_too_many')) {
      return text(
        'The export is limited to 1,000 work records. Narrow the search filters and retry.',
        'Exportul este limitat la 1.000 de lucrări. Restrânge filtrele și reîncearcă.',
      );
    }
    if (code.contains('work_export_too_large')) {
      return text(
        'This export exceeds the size limit.',
        'Exportul depășește limita de dimensiune.',
      );
    }
    if (code.contains('work_export_invalid_revision')) {
      return text(
        'Open an existing saved version and retry the export.',
        'Deschide o versiune salvată existentă și reîncearcă exportul.',
      );
    }
    if (code.contains('not_found')) {
      return text(
        'This work or saved version is unavailable.',
        'Lucrarea sau versiunea salvată nu este disponibilă.',
      );
    }
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
    if (code.contains('work_invalid_filters') ||
        code.contains('work_filters_unavailable')) {
      return text(
        'Check the search filters and capture date range, then retry.',
        'Verifică filtrele și intervalul datelor fotografiilor, apoi reîncearcă.',
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
    'schemaVersion' => text('Work format', 'Formatul lucrării'),
    'progress' => text('Work status', 'Starea lucrării'),
    _ => text('Notes', 'Observații'),
  };
}