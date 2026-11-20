import 'dart:typed_data';

import '../../core/models/photo_location.dart';
import 'stamped_photo.dart';

class CaptureException implements Exception {
  const CaptureException(this.code);

  final String code;
}

class PhotoDraft {
  PhotoDraft({
    required this.id,
    required Uint8List originalBytes,
    required this.mimeType,
    required DateTime capturedAt,
    required this.location,
  }) : originalBytes = Uint8List.fromList(originalBytes).asUnmodifiableView(),
       capturedAtUtc = capturedAt.toUtc(),
       stamped = null;

  PhotoDraft._({
    required this.id,
    required this.originalBytes,
    required this.mimeType,
    required this.capturedAtUtc,
    required this.location,
    required this.stamped,
  });

  final String id;
  final Uint8List originalBytes;
  final String mimeType;
  final DateTime capturedAtUtc;
  final PhotoLocation location;
  final StampedPhoto? stamped;

  String get filename => '$id.${mimeType == 'image/png' ? 'png' : 'jpg'}';
  String get stampedFilename => '$id.coords.jpg';

  PhotoDraft withStamp(StampedPhoto value) {
    if (value.overlayText != location.overlayText) {
      throw ArgumentError('The stamp must match this photo location.');
    }

    return PhotoDraft._(
      id: id,
      originalBytes: originalBytes,
      mimeType: mimeType,
      capturedAtUtc: capturedAtUtc,
      location: location,
      stamped: value,
    );
  }
}
