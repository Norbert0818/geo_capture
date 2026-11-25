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
  });
  final String serialNumber;
  final String ntetCode;
  final String source;
  final String? rawCode;

  Map<String, dynamic> toJson() => {
    'serialNumber': serialNumber,
    'ntetCode': ntetCode,
    'source': source,
    'rawCode': rawCode,
  };
  factory PoleIdentity.fromJson(Map<String, dynamic> json) => PoleIdentity(
    serialNumber: json['serialNumber'] as String,
    ntetCode: json['ntetCode'] as String,
    source: json['source'] as String,
    rawCode: json['rawCode'] as String?,
  );
  String get generatedPayload => jsonEncode({
    'type': 'geocapture.pole',
    'version': 1,
    'ntetCode': ntetCode,
    'serialNumber': serialNumber,
  });
  bool get valid =>
      serialNumber.trim().isNotEmpty &&
      serialNumber.length <= 1024 &&
      ntetCode.length <= 128;
  PoleIdentity generated() => PoleIdentity(
    serialNumber: serialNumber,
    ntetCode: ntetCode,
    source: 'generated',
    rawCode: generatedPayload,
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
    List<WorkPhoto> photos = const [],
  }) : photos = List.unmodifiable(photos);
  final WorkKind kind;
  final PoleIdentity? oldPole, newPole;
  final String notes;
  final List<WorkPhoto> photos;
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'oldPole': oldPole?.toJson(),
    'newPole': newPole?.toJson(),
    'notes': notes,
    'photos': photos.map((photo) => photo.toJson()).toList(),
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
  }) => WorkDocument(
    kind: kind,
    oldPole: oldPole ?? this.oldPole,
    newPole: newPole ?? this.newPole,
    notes: notes ?? this.notes,
    photos: photos ?? this.photos,
  );
  bool get complete =>
      (kind == WorkKind.pit || oldPole?.valid == true) &&
      (kind != WorkKind.replacement ||
          (newPole?.valid == true && newPole!.ntetCode.trim().isNotEmpty)) &&
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