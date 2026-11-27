import 'work_models.dart';

// Same names as the API's revision exports. Original image bytes stay untouched.
String workPhotoName(
    String workId,
    WorkDocument document,
    int index, {
      bool original = false,
    }) {
  final photo = document.photos[index];
  final pole = ['new', 'new_label'].contains(photo.role)
      ? document.newPole
      : document.oldPole;
  var serial = (pole?.serialNumber ?? '')
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');
  if (serial.length > 64) serial = serial.substring(0, 64);
  if (serial.isEmpty) {
    serial = document.kind == WorkKind.pit
        ? 'groapa'
        : switch (pole?.serialState) {
      'missing' => 'fara_serie',
      'damaged' => 'eticheta_deteriorata',
      _ => 'serie_necompletata',
    };
  }
  final role = switch (photo.role) {
    'old' => 'vechi',
    'new' => 'nou',
    'before' => 'inainte',
    'after' => 'remediat',
    'pole' => 'stalp',
    'pit' => 'groapa',
    'old_label' => 'eticheta_veche',
    'new_label' => 'eticheta_noua',
    'label' => 'eticheta',
    _ => 'foto',
  };
  final id = workId.replaceAll('-', '');
  final prefix = id.length < 8 ? id : id.substring(0, 8);
  final extension = original && photo.originalMimeType == 'image/png'
      ? 'png'
      : 'jpg';
  return '${serial}_${role}_${(index + 1).toString().padLeft(2, '0')}_${prefix}_${photo.id.replaceAll('-', '')}.${original ? 'original' : 'stamped'}.$extension';
}