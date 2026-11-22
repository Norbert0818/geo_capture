import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:geo_capture/features/uploads/upload_history_models.dart';
import 'package:geo_capture/features/uploads/upload_history_repository.dart';

import 'upload_test_support.dart' as upload_test;

String uploadId(int n) =>
    '22222222-2222-4222-8222-${n.toString().padLeft(12, '0')}';
String savedPhotoId(int n) =>
    '33333333-3333-4333-8333-${n.toString().padLeft(12, '0')}';

Map<String, dynamic> summaryJson(int n, {int photoCount = 1}) => {
  'id': uploadId(n),
  'clientUploadId': '77777777-7777-4777-8777-${n.toString().padLeft(12, '0')}',
  'serialNumber': '000$n / AB',
  'ownerId': '44444444-4444-4444-8444-444444444444',
  'uploadedByUsername': n.isEven ? 'worker02' : 'worker01',
  'uploadedAtUtc': '2026-11-20T12:01:00Z',
  'photoCount': photoCount,
  'version': '55555555-5555-4555-8555-555555555555',
};

Map<String, dynamic> storedPhotoJson(int n) {
  final draft = upload_test.photo(n);
  return {
    'id': savedPhotoId(n),
    'clientPhotoId': draft.id,
    'position': n - 1,
    'latitude': 47.181912,
    'longitude': 23.165123,
    'accuracyMeters': 5.0,
    'coordinatesText': '47.181912, 23.165123',
    'capturedAtUtc': '2026-11-20T12:00:00Z',
    'locationMeasuredAtUtc': '2026-11-20T11:59:59Z',
    'originalMimeType': 'image/png',
    'originalWidth': 16,
    'originalHeight': 12,
    'stampedWidth': 16,
    'stampedHeight': 12,
    'originalByteLength': draft.originalBytes.length,
    'stampedByteLength': draft.stamped!.bytes.length,
    'originalSha256': List.filled(64, 'A').join(),
    'stampedSha256': List.filled(64, 'B').join(),
    'originalUrl': 'https://outside.invalid/never-fetch-this',
    'stampedUrl': 'https://outside.invalid/never-fetch-this-either',
  };
}

Map<String, dynamic> detailsJson(int n, {int photoCount = 2}) => {
  ...summaryJson(n, photoCount: photoCount),
  'photos': [for (var i = 1; i <= photoCount; i++) storedPhotoJson(i)],
};

Map<String, dynamic> pageJson({
  int page = 1,
  int pageSize = 12,
  int total = 25,
}) {
  final first = (page - 1) * pageSize + 1;
  return {
    'page': page,
    'pageSize': pageSize,
    'total': total,
    'items': [
      for (var n = first; n < first + pageSize && n <= total; n++)
        summaryJson(n),
    ],
  };
}

class FakeHistoryRepository implements UploadHistoryRepository {
  final lists = <({bool allUsers, int page, int pageSize})>[];
  final detailsCalls = <String>[];
  final images =
      <
        ({
          String uploadId,
          String photoId,
          bool original,
          CancelToken? cancelToken,
        })
      >[];
  Future<UploadHistoryResult> Function(bool allUsers, int page, int pageSize)?
  onList;
  Future<StoredUpload> Function(String id)? onDetails;
  Future<Uint8List> Function(String uploadId, String photoId, bool original)?
  onImage;

  @override
  Future<UploadHistoryResult> list({
    bool allUsers = false,
    int page = 1,
    int pageSize = 12,
  }) async {
    lists.add((allUsers: allUsers, page: page, pageSize: pageSize));
    return onList == null
        ? UploadHistoryResult.fromJson(pageJson(page: page, pageSize: pageSize))
        : await onList!(allUsers, page, pageSize);
  }

  @override
  Future<StoredUpload> details(String id) async {
    detailsCalls.add(id);
    return onDetails == null
        ? StoredUpload.fromJson(detailsJson(1))
        : await onDetails!(id);
  }

  @override
  Future<Uint8List> image(
    String uploadId,
    String photoId, {
    required bool original,
    CancelToken? cancelToken,
  }) async {
    images.add((
      uploadId: uploadId,
      photoId: photoId,
      original: original,
      cancelToken: cancelToken,
    ));
    if (onImage != null) return onImage!(uploadId, photoId, original);
    final photo = upload_test.photo(1);
    return original ? photo.originalBytes : photo.stamped!.bytes;
  }
}
