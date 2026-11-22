import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../capture/photo_draft.dart';

typedef UploadSerials = ({String oldSerialNumber, String newSerialNumber});

class UploadLimits {
  const UploadLimits({
    required this.maxPhotos,
    required this.maxSerialNumberLength,
    required this.maxFileBytes,
    required this.maxBatchBytes,
  });

  final int maxPhotos;
  final int maxSerialNumberLength;
  final int maxFileBytes;
  final int maxBatchBytes;

  factory UploadLimits.fromJson(Map<String, dynamic> json) {
    int positive(String key) {
      final value = json[key];
      if (value is! int || value < 1) throw const FormatException();
      return value;
    }

    return UploadLimits(
      maxPhotos: positive('maxPhotos'),
      maxSerialNumberLength: positive('maxSerialNumberLength'),
      maxFileBytes: positive('maxFileBytes'),
      maxBatchBytes: positive('maxBatchBytes'),
    );
  }

  String? serialError(String value) {
    final serial = value.trim();
    return serial.isEmpty ||
        serial.length > maxSerialNumberLength ||
        RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(serial)
        ? 'invalid_serial_number'
        : null;
  }
}

class UploadBatch {
  UploadBatch._(
      this.id,
      this.oldSerialNumber,
      this.newSerialNumber,
      List<PhotoDraft> photos,
      ) : photos = List.unmodifiable(photos);

  final String id;
  final String oldSerialNumber;
  final String newSerialNumber;
  final List<PhotoDraft> photos;

  factory UploadBatch.create({
    required String oldSerialNumber,
    required String newSerialNumber,
    required List<PhotoDraft> photos,
    required UploadLimits limits,
    String Function()? newId,
  }) {
    if (limits.serialError(oldSerialNumber) != null) {
      throw const ApiException('invalid_old_serial_number');
    }
    if (limits.serialError(newSerialNumber) != null) {
      throw const ApiException('invalid_new_serial_number');
    }
    if (photos.isEmpty) throw const ApiException('no_photos');
    if (photos.length > limits.maxPhotos) {
      throw const ApiException('too_many_photos');
    }

    final ids = <String>{};
    var totalBytes = 0;
    for (final photo in photos) {
      final stamped = photo.stamped;
      if (stamped == null) throw const ApiException('photo_not_ready');
      if (!_isId(photo.id) || !ids.add(photo.id.toLowerCase())) {
        throw const ApiException('invalid_manifest');
      }
      for (final bytes in [photo.originalBytes, stamped.bytes]) {
        if (bytes.isEmpty) throw const ApiException('invalid_photo');
        if (bytes.length > limits.maxFileBytes) {
          throw const ApiException('upload_too_large');
        }
        totalBytes += bytes.length;
      }
    }
    if (totalBytes > limits.maxBatchBytes) {
      throw const ApiException('upload_too_large');
    }

    final id = (newId ?? const Uuid().v4)();
    if (!_isId(id)) throw const ApiException('invalid_manifest');
    return UploadBatch._(
      id,
      oldSerialNumber.trim(),
      newSerialNumber.trim(),
      photos,
    );
  }

  Map<String, dynamic> get manifest => {
    'id': id,
    'oldSerialNumber': oldSerialNumber,
    'newSerialNumber': newSerialNumber,
    'photos': [
      for (final photo in photos)
        {
          'id': photo.id,
          'latitude': photo.location.latitude,
          'longitude': photo.location.longitude,
          'accuracyMeters': photo.location.accuracyMeters,
          'capturedAtUtc': photo.capturedAtUtc.toIso8601String(),
          'locationMeasuredAtUtc': photo.location.measuredAtUtc
              .toIso8601String(),
        },
    ],
  };

  static bool _isId(String value) =>
      RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
          .hasMatch(value) &&
          value != '00000000-0000-0000-0000-000000000000';
}

class UploadReceipt {
  UploadReceipt({
    required this.id,
    required this.clientUploadId,
    required this.oldSerialNumber,
    required this.newSerialNumber,
    required this.uploadedAtUtc,
    required this.replayed,
    required List<String> photoIds,
  }) : photoIds = List.unmodifiable(photoIds);

  final String id;
  final String clientUploadId;
  final String oldSerialNumber;
  final String newSerialNumber;
  final DateTime uploadedAtUtc;
  final bool replayed;
  final List<String> photoIds;

  int get photoCount => photoIds.length;

  factory UploadReceipt.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final clientId = json['clientUploadId'];
    final oldSerial = json['oldSerialNumber'];
    final newSerial = json['newSerialNumber'];
    final date = json['uploadedAtUtc'];
    final replayed = json['replayed'];
    final photos = json['photos'];
    if (id is! String ||
        !UploadBatch._isId(id) ||
        clientId is! String ||
        !UploadBatch._isId(clientId) ||
        oldSerial is! String ||
        oldSerial.trim().isEmpty ||
        newSerial is! String ||
        newSerial.trim().isEmpty ||
        date is! String ||
        replayed is! bool ||
        photos is! List) {
      throw const FormatException();
    }
    final ids = <String>[];
    for (final photo in photos) {
      if (photo is! Map || photo['clientPhotoId'] is! String) {
        throw const FormatException();
      }
      ids.add(photo['clientPhotoId'] as String);
    }
    return UploadReceipt(
      id: id,
      clientUploadId: clientId,
      oldSerialNumber: oldSerial,
      newSerialNumber: newSerial,
      uploadedAtUtc: DateTime.parse(date).toUtc(),
      replayed: replayed,
      photoIds: ids,
    );
  }

  bool confirms(UploadBatch batch) =>
      clientUploadId.toLowerCase() == batch.id.toLowerCase() &&
          oldSerialNumber == batch.oldSerialNumber &&
          newSerialNumber == batch.newSerialNumber &&
          photoIds.length == batch.photos.length &&
          photoIds.map((id) => id.toLowerCase()).toSet().length ==
              photoIds.length &&
          photoIds
              .map((id) => id.toLowerCase())
              .toSet()
              .containsAll(batch.photos.map((photo) => photo.id.toLowerCase()));
}