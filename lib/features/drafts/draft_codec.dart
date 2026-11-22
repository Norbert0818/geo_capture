import 'dart:typed_data';

import 'package:sembast/blob.dart';

import '../../core/models/photo_location.dart';
import '../capture/photo_draft.dart';
import '../capture/stamped_photo.dart';
import '../uploads/upload_history_models.dart';

class DraftCodec {
  static Map<String, Object?> encodePhoto(PhotoDraft photo, String scope) => {
    'scope': scope,
    'id': photo.id,
    'original': Blob(photo.originalBytes),
    'mimeType': photo.mimeType,
    'capturedAt': photo.capturedAtUtc.toIso8601String(),
    'latitude': photo.location.latitude,
    'longitude': photo.location.longitude,
    'accuracy': photo.location.accuracyMeters,
    'measuredAt': photo.location.measuredAtUtc.toIso8601String(),
    if (photo.stamped case final stamp?)
      'stamp': {
        'bytes': Blob(stamp.bytes),
        'width': stamp.width,
        'height': stamp.height,
        'overlayText': stamp.overlayText,
      },
  };

  static String text(Map<String, Object?> value, String key) {
    final result = value[key];
    if (result is! String) throw const FormatException('Invalid draft text');
    return result;
  }

  static DateTime date(Map<String, Object?> value, String key) {
    final raw = text(value, key);
    if (!raw.endsWith('Z')) throw const FormatException('UTC date required');
    return DateTime.parse(raw).toUtc();
  }

  static Uint8List bytes(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw is! Blob || raw.bytes.isEmpty) {
      throw const FormatException('Invalid draft image');
    }
    return Uint8List.fromList(raw.bytes);
  }

  static double number(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw is! num || !raw.isFinite) throw const FormatException();
    return raw.toDouble();
  }

  static PhotoDraft decodePhoto(Map<String, Object?> value, String scope) {
    final id = text(value, 'id');
    final mime = text(value, 'mimeType');
    if (value['scope'] != scope ||
        !isUploadId(id) ||
        (mime != 'image/jpeg' && mime != 'image/png')) {
      throw const FormatException('Invalid draft photo');
    }
    final photo = PhotoDraft(
      id: id,
      originalBytes: bytes(value, 'original'),
      mimeType: mime,
      capturedAt: date(value, 'capturedAt'),
      location: PhotoLocation(
        latitude: number(value, 'latitude'),
        longitude: number(value, 'longitude'),
        accuracyMeters: number(value, 'accuracy'),
        measuredAt: date(value, 'measuredAt'),
      ),
    );
    final raw = value['stamp'];
    if (raw == null) return photo;
    if (raw is! Map) throw const FormatException();
    final stamp = Map<String, Object?>.from(raw);
    final width = stamp['width'];
    final height = stamp['height'];
    if (width is! int || height is! int || width < 1 || height < 1) {
      throw const FormatException('Invalid draft dimensions');
    }
    return photo.withStamp(
      StampedPhoto(
        bytes: bytes(stamp, 'bytes'),
        width: width,
        height: height,
        overlayText: text(stamp, 'overlayText'),
      ),
    );
  }
}