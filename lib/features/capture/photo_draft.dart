import 'dart:typed_data';

import '../../core/models/photo_location.dart';

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
        capturedAtUtc = capturedAt.toUtc();

  final String id;
  final Uint8List originalBytes;
  final String mimeType;
  final DateTime capturedAtUtc;
  final PhotoLocation location;

  String get filename => '$id.${mimeType == 'image/png' ? 'png' : 'jpg'}';
}