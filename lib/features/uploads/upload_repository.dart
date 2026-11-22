import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import 'upload_batch.dart';

abstract interface class UploadRepository {
  Future<UploadLimits> getLimits();

  Future<UploadReceipt> upload(
    UploadBatch batch, {
    void Function(int sent, int total)? onProgress,
  });
}

class HttpUploadRepository implements UploadRepository {
  HttpUploadRepository(this._api);

  // The same client is shared with HttpAuthRepository, including its cookies.
  final ApiClient _api;

  @override
  Future<UploadLimits> getLimits() async {
    final json = await _api.get('/api/uploads/limits');
    try {
      return UploadLimits.fromJson(json);
    } on FormatException {
      throw const ApiException('service_unavailable');
    }
  }

  @override
  Future<UploadReceipt> upload(
    UploadBatch batch, {
    void Function(int sent, int total)? onProgress,
  }) async {
    // FormData is single-use. Rebuild it for every attempt, keeping the batch ID.
    final form = FormData();
    form.fields.add(MapEntry('manifest', jsonEncode(batch.manifest)));
    for (final photo in batch.photos) {
      form.files.add(
        MapEntry(
          'original_${photo.id}',
          MultipartFile.fromBytes(
            photo.originalBytes,
            filename: photo.filename,
          ),
        ),
      );
      form.files.add(
        MapEntry(
          'stamped_${photo.id}',
          MultipartFile.fromBytes(
            photo.stamped!.bytes,
            filename: photo.stampedFilename,
          ),
        ),
      );
    }

    final json = await _api.postMultipart(
      '/api/uploads',
      form,
      onSendProgress: onProgress,
    );
    try {
      final receipt = UploadReceipt.fromJson(json);
      if (!receipt.confirms(batch)) throw const FormatException();
      return receipt;
    } on FormatException {
      throw const ApiException('service_unavailable');
    }
  }
}
