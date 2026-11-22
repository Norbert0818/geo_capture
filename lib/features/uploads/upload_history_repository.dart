import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import 'upload_history_models.dart';

abstract interface class UploadHistoryRepository {
  Future<UploadHistoryResult> list({
    bool allUsers = false,
    int page = 1,
    int pageSize = 12,
  });
  Future<StoredUpload> details(String uploadId);
  Future<Uint8List> image(
    String uploadId,
    String photoId, {
    required bool original,
    CancelToken? cancelToken,
  });
}

class HttpUploadHistoryRepository implements UploadHistoryRepository {
  HttpUploadHistoryRepository(this._api);

  final ApiClient _api;

  @override
  Future<UploadHistoryResult> list({
    bool allUsers = false,
    int page = 1,
    int pageSize = 12,
  }) async {
    if (page < 1 || pageSize < 1 || pageSize > 50) {
      throw const ApiException('invalid_page');
    }
    final json = await _api.get(
      allUsers ? '/api/admin/uploads' : '/api/uploads',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    try {
      final result = UploadHistoryResult.fromJson(json);
      if (result.page != page ||
          result.pageSize != pageSize ||
          result.items.length > pageSize) {
        throw const FormatException();
      }
      return result;
    } on FormatException {
      throw const ApiException('service_unavailable');
    }
  }

  @override
  Future<StoredUpload> details(String uploadId) async {
    _checkId(uploadId);
    final json = await _api.get('/api/uploads/$uploadId');
    try {
      final result = StoredUpload.fromJson(json);
      if (result.summary.id.toLowerCase() != uploadId.toLowerCase()) {
        throw const FormatException();
      }
      return result;
    } on FormatException {
      throw const ApiException('service_unavailable');
    }
  }

  @override
  Future<Uint8List> image(
    String uploadId,
    String photoId, {
    required bool original,
    CancelToken? cancelToken,
  }) {
    _checkId(uploadId);
    _checkId(photoId);
    // Build the protected API path locally; never fetch an arbitrary response URL.
    return _api.getImage(
      '/api/uploads/$uploadId/photos/$photoId/${original ? 'original' : 'stamped'}',
      cancelToken: cancelToken,
    );
  }

  static void _checkId(String id) {
    if (!isUploadId(id)) throw const ApiException('not_found', statusCode: 404);
  }
}
