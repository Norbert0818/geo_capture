import 'dart:typed_data';

import 'photo_capture_service.dart';
import 'photo_draft.dart';
import 'photo_stamp_service.dart';
import 'stamped_photo.dart';

class PhotoPreparationService {
  PhotoPreparationService({
    PhotoCaptureService? captureService,
    Future<StampedPhoto> Function(PhotoDraft)? stampPhoto,
  }) : _captureService = captureService ?? PhotoCaptureService(),
       _stampPhoto = stampPhoto ?? PhotoStampService().stamp;

  final PhotoCaptureService _captureService;
  final Future<StampedPhoto> Function(PhotoDraft) _stampPhoto;

  Future<PhotoDraft> capture(Future<Uint8List> Function() takePicture) async {
    final photo = await _captureService.capture(takePicture);
    final stamped = await _stampPhoto(photo);
    return photo.withStamp(stamped);
  }
}
