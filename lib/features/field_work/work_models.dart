import 'dart:convert';
import 'dart:typed_data';

import '../../core/models/photo_location.dart';

enum WorkKind { replacement, repair, removal, pit }

const workRoles = {
  WorkKind.replacement: ['old', 'new'],
  WorkKind.repair: ['before', 'after'],
  WorkKind.removal: ['pole'],
  WorkKind.pit: ['pit'],
};

class PoleIdentity {
  const PoleIdentity({
    this.serialNumber = '',
    this.ntetCode = '',
    this.source = 'manual',
    this.rawCode,
    this.serialState,
    this.confirmed,
    this.evidencePhotoId,
  });
  final String serialNumber;
  final String ntetCode;
  final String source;
  final String? rawCode, serialState, evidencePhotoId;
  final bool? confirmed;
  static final numericSerial = RegExp(r'^[0-9]{1,128}$');
  bool get resolved => serialState == null ? valid : confirmed == true && valid;
  bool get pending =>
      serialState == 'pending' || (serialState == null && serialNumber.isEmpty);

  Map<String, dynamic> toJson() => {
    'serialNumber': serialNumber,
    'ntetCode': ntetCode,
    'source': source,
    'rawCode': rawCode,
    if (serialState != null) 'serialState': serialState,
    if (confirmed != null) 'confirmed': confirmed,
    if (evidencePhotoId != null) 'evidencePhotoId': evidencePhotoId,
  };
  factory PoleIdentity.fromJson(Map<String, dynamic> json) => PoleIdentity(
    serialNumber: json['serialNumber'] as String,
    ntetCode: json['ntetCode'] as String,
    source: json['source'] as String,
    rawCode: json['rawCode'] as String?,
    serialState: json['serialState'] as String?,
    confirmed: json['confirmed'] as bool?,
    evidencePhotoId: json['evidencePhotoId'] as String?,
  );
  String get generatedPayload => jsonEncode({
    'type': 'geocapture.pole',
    'version': 1,
    'ntetCode': ntetCode,
    'serialNumber': serialNumber,
  });
  bool get valid {
    if (serialState == null) {
      return serialNumber.trim().isNotEmpty &&
          serialNumber.length <= 1024 &&
          ntetCode.length <= 128;
    }
    if (ntetCode.length > 128 ||
        ntetCode != ntetCode.trim() ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(ntetCode) ||
        (rawCode?.length ?? 0) > 4096 ||
        !['manual', 'scanned', 'ocr', 'generated'].contains(source) ||
        source == 'scanned' && (rawCode?.trim().isNotEmpty != true) ||
        source == 'generated' &&
            (serialState != 'present' ||
                ntetCode.isEmpty ||
                rawCode != generatedPayload) ||
        confirmed != true) {
      return false;
    }
    return switch (serialState) {
      'present' => numericSerial.hasMatch(serialNumber),
      'missing' => serialNumber.isEmpty,
      'damaged' => serialNumber.isEmpty || numericSerial.hasMatch(serialNumber),
      _ => false,
    };
  }

  bool get validPending =>
      serialState == 'pending' &&
          confirmed != true &&
          serialNumber.isEmpty &&
          ntetCode.length <= 128;
  PoleIdentity copyWith({
    String? serialNumber,
    String? ntetCode,
    String? source,
    String? rawCode,
    String? serialState,
    bool? confirmed,
    String? evidencePhotoId,
    bool clearEvidence = false,
  }) => PoleIdentity(
    serialNumber: serialNumber ?? this.serialNumber,
    ntetCode: ntetCode ?? this.ntetCode,
    source: source ?? this.source,
    rawCode: rawCode ?? this.rawCode,
    serialState: serialState ?? this.serialState,
    confirmed: confirmed ?? this.confirmed,
    evidencePhotoId: clearEvidence
        ? null
        : evidencePhotoId ?? this.evidencePhotoId,
  );

  PoleIdentity generated() => PoleIdentity(
    serialNumber: serialNumber,
    ntetCode: ntetCode,
    source: 'generated',
    rawCode: generatedPayload,
    serialState: serialState,
    confirmed: confirmed,
    evidencePhotoId: evidencePhotoId,
  );
}

String workTimestamp(DateTime utc, int offset) {
  final wall = utc.toUtc().add(Duration(minutes: offset));
  String two(int value) => value.toString().padLeft(2, '0');
  final sign = offset >= 0 ? '+' : '-';
  return '${wall.year}-${two(wall.month)}-${two(wall.day)} ${two(wall.hour)}:${two(wall.minute)}:${two(wall.second)} '
      '(UTC$sign${two(offset.abs() ~/ 60)}:${two(offset.abs() % 60)})';
}

class WorkPhoto {
  WorkPhoto({
    required this.id,
    required this.role,
    required this.location,
    required DateTime capturedAt,
    required this.utcOffsetMinutes,
    required this.locality,
    required this.county,
    required this.placeSource,
    required this.serialVisible,
    required this.originalMimeType,
    this.countyCode,
    this.localityCode,
    Uint8List? original,
    Uint8List? stamped,
  }) : capturedAtUtc = capturedAt.toUtc(),
        original = original == null
            ? null
            : Uint8List.fromList(original).asUnmodifiableView(),
        stamped = stamped == null
            ? null
            : Uint8List.fromList(stamped).asUnmodifiableView();

  final String id, role, locality, county, placeSource, originalMimeType;
  final String? countyCode, localityCode;
  final PhotoLocation location;
  final DateTime capturedAtUtc;
  final int utcOffsetMinutes;
  final bool serialVisible;
  final Uint8List? original, stamped;
  bool get isLocal => original != null && stamped != null;
  String get overlayText =>
      '${location.overlayText}\n$locality, $county\n${workTimestamp(capturedAtUtc, utcOffsetMinutes)}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'latitude': location.latitude,
    'longitude': location.longitude,
    'accuracyMeters': location.accuracyMeters,
    'capturedAtUtc': capturedAtUtc.toIso8601String(),
    'measuredAtUtc': location.measuredAtUtc.toIso8601String(),
    'utcOffsetMinutes': utcOffsetMinutes,
    'locality': locality,
    'county': county,
    'placeSource': placeSource,
    'serialVisible': serialVisible,
    'originalMimeType': originalMimeType,
    'overlayText': overlayText,
    if (countyCode != null) 'countyCode': countyCode,
    if (localityCode != null) 'localityCode': localityCode,
  };
  factory WorkPhoto.fromJson(
      Map<String, dynamic> value, {
        Uint8List? original,
        Uint8List? stamped,
      }) {
    final result = WorkPhoto(
      id: value['id'] as String,
      role: value['role'] as String,
      location: PhotoLocation(
        latitude: (value['latitude'] as num).toDouble(),
        longitude: (value['longitude'] as num).toDouble(),
        accuracyMeters: (value['accuracyMeters'] as num).toDouble(),
        measuredAt: DateTime.parse(value['measuredAtUtc'] as String),
      ),
      capturedAt: DateTime.parse(value['capturedAtUtc'] as String),
      utcOffsetMinutes: value['utcOffsetMinutes'] as int,
      locality: value['locality'] as String,
      county: value['county'] as String,
      placeSource: value['placeSource'] as String,
      serialVisible: value['serialVisible'] as bool,
      originalMimeType: value['originalMimeType'] as String,
      countyCode: value['countyCode'] as String?,
      localityCode: value['localityCode'] as String?,
      original: original,
      stamped: stamped,
    );
    if (result.overlayText != value['overlayText']) {
      throw const FormatException('Invalid photo stamp metadata');
    }
    return result;
  }
  WorkPhoto withBytes(Uint8List originalBytes, Uint8List stampedBytes) =>
      WorkPhoto(
        id: id,
        role: role,
        location: location,
        capturedAt: capturedAtUtc,
        utcOffsetMinutes: utcOffsetMinutes,
        locality: locality,
        county: county,
        placeSource: placeSource,
        serialVisible: serialVisible,
        originalMimeType: originalMimeType,
        countyCode: countyCode,
        localityCode: localityCode,
        original: originalBytes,
        stamped: stampedBytes,
      );
}

class WorkDocument {
  WorkDocument({
    required this.kind,
    this.oldPole,
    this.newPole,
    this.notes = '',
    this.schemaVersion,
    this.progress,
    List<WorkPhoto> photos = const [],
  }) : photos = List.unmodifiable(photos);
  final WorkKind kind;
  final int? schemaVersion;
  final String? progress;
  bool get modern => schemaVersion == 2;
  bool get inProgress => modern && progress == 'in_progress';
  final PoleIdentity? oldPole, newPole;
  final String notes;
  final List<WorkPhoto> photos;
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'oldPole': oldPole?.toJson(),
    'newPole': newPole?.toJson(),
    'notes': notes,
    'photos': photos.map((photo) => photo.toJson()).toList(),
    if (schemaVersion != null) 'schemaVersion': schemaVersion,
    if (progress != null) 'progress': progress,
  };
  factory WorkDocument.fromJson(Map<String, dynamic> value) => WorkDocument(
    kind: WorkKind.values.byName(value['kind'] as String),
    oldPole: value['oldPole'] == null
        ? null
        : PoleIdentity.fromJson(
      Map<String, dynamic>.from(value['oldPole'] as Map),
    ),
    newPole: value['newPole'] == null
        ? null
        : PoleIdentity.fromJson(
      Map<String, dynamic>.from(value['newPole'] as Map),
    ),
    notes: value['notes'] as String,
    schemaVersion: value['schemaVersion'] as int?,
    progress: value['progress'] as String?,
    photos: (value['photos'] as List)
        .map(
          (photo) =>
          WorkPhoto.fromJson(Map<String, dynamic>.from(photo as Map)),
    )
        .toList(),
  );
  WorkDocument copyWith({
    PoleIdentity? oldPole,
    PoleIdentity? newPole,
    String? notes,
    List<WorkPhoto>? photos,
    int? schemaVersion,
    String? progress,
  }) => WorkDocument(
    kind: kind,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    progress: progress ?? this.progress,
    oldPole: oldPole ?? this.oldPole,
    newPole: newPole ?? this.newPole,
    notes: notes ?? this.notes,
    photos: photos ?? this.photos,
  );
  List<String> get allowedRoles => [
    ...workRoles[kind]!,
    if (modern && kind == WorkKind.replacement) ...['old_label', 'new_label'],
    if (modern && (kind == WorkKind.repair || kind == WorkKind.removal))
      'label',
  ];
  bool get validPhotoSet =>
      photos.isNotEmpty &&
          photos.length <= 10 &&
          photos.map((photo) => photo.id).toSet().length == photos.length &&
          photos.every(
                (photo) =>
            allowedRoles.contains(photo.role) &&
                photo.locality.trim().isNotEmpty &&
                photo.county.trim().isNotEmpty,
          );
  bool get readyToSave => modern
      ? schemaVersion == 2 &&
      ['in_progress', 'completed'].contains(progress) &&
      _identitiesFitKind &&
      (inProgress
          ? validPhotoSet &&
          [oldPole, newPole].every(
                (pole) =>
            pole == null || pole.valid || pole.validPending,
          )
          : complete)
      : complete;
  bool get _identitiesFitKind => kind == WorkKind.pit
      ? oldPole == null && newPole == null
      : oldPole?.source != 'generated' &&
      (kind == WorkKind.replacement || newPole == null) &&
      [oldPole, newPole].every((pole) {
        if (pole?.evidencePhotoId == null) return true;
        final roles = identical(pole, newPole)
            ? ['new', 'new_label']
            : kind == WorkKind.replacement
            ? ['old', 'old_label']
            : kind == WorkKind.repair
            ? ['before', 'after', 'label']
            : ['pole', 'label'];
        return photos.any(
              (photo) =>
          photo.id == pole!.evidencePhotoId &&
              roles.contains(photo.role),
        );
      });
  bool get complete => modern
      ? _identitiesFitKind &&
      validPhotoSet &&
      workRoles[kind]!.every(
            (role) => photos.any((photo) => photo.role == role),
      ) &&
      (kind == WorkKind.pit || oldPole?.resolved == true) &&
      (kind != WorkKind.replacement || newPole?.resolved == true)
      : (kind == WorkKind.pit || oldPole?.valid == true) &&
      (kind != WorkKind.replacement ||
          (newPole?.valid == true &&
              newPole!.ntetCode.trim().isNotEmpty)) &&
      photos.length <= 10 &&
      workRoles[kind]!.every(
            (role) => photos.any((photo) => photo.role == role),
      ) &&
      photos.every(
            (photo) =>
        workRoles[kind]!.contains(photo.role) &&
            photo.locality.trim().isNotEmpty &&
            photo.county.trim().isNotEmpty &&
            (photo.role != 'old' || photo.serialVisible),
      );
}

class WorkDetails {
  const WorkDetails({
    required this.id,
    required this.version,
    required this.revision,
    required this.owner,
    required this.document,
  });
  final String id, version, owner;
  final int revision;
  final WorkDocument document;
  factory WorkDetails.fromJson(Map<String, dynamic> json) => WorkDetails(
    id: json['id'] as String,
    version: json['version'] as String,
    revision: json['revision'] as int,
    owner: json['owner'] as String,
    document: WorkDocument.fromJson(
      Map<String, dynamic>.from(json['document'] as Map),
    ),
  );
}

class WorkSettings {
  const WorkSettings({required this.allowQrGeneration, required this.version});
  final bool allowQrGeneration;
  final String version;
  factory WorkSettings.fromJson(Map<String, dynamic> json) => WorkSettings(
    allowQrGeneration: json['allowQrGeneration'] as bool,
    version: json['version'] as String,
  );
}

class WorkDraft {
  const WorkDraft({
    required this.id,
    required this.document,
    this.expectedVersion,
    this.pendingChangeId,
    this.reason = 'Initial upload',
    this.localRevision = 0,
  });
  final String id;
  final WorkDocument document;
  final String? expectedVersion, pendingChangeId;
  final String reason;
  final int localRevision;
  WorkDraft copyWith({
    WorkDocument? document,
    String? pendingChangeId,
    String? reason,
    int? localRevision,
  }) => WorkDraft(
    id: id,
    document: document ?? this.document,
    expectedVersion: expectedVersion,
    pendingChangeId: pendingChangeId ?? this.pendingChangeId,
    reason: reason ?? this.reason,
    localRevision: localRevision ?? this.localRevision,
  );
}