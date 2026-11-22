import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/uploads/upload_batch.dart';
import 'package:geo_capture/features/uploads/upload_repository.dart';

import 'upload_test_support.dart';

ResponseBody jsonBody(Object value, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class UploadAdapter implements HttpClientAdapter {
  UploadAdapter(this.handle);

  final FutureOr<ResponseBody> Function(RequestOptions) handle;
  final requests = <RequestOptions>[];
  final bodies = <Uint8List>[];

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture,
      ) async {
    requests.add(options);
    if (requestStream != null) {
      final bytes = BytesBuilder();
      await for (final chunk in requestStream) {
        bytes.add(chunk);
      }
      bodies.add(bytes.takeBytes());
    }
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

(ApiClient, HttpUploadRepository) repository(UploadAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.example.test',
      contentType: Headers.jsonContentType,
    ),
  )..httpClientAdapter = adapter;
  final api = ApiClient.fromDio(dio);
  addTearDown(api.close);
  return (api, HttpUploadRepository(api));
}

Matcher apiError(String code) =>
    isA<ApiException>().having((error) => error.code, 'code', code);

void main() {
  test(
    'sends both image variants, per-photo GPS, UTC times and a serial as text',
        () async {
      final batch = UploadBatch.create(
        oldSerialNumber: 'OLD',
        newSerialNumber: '  000123 / AB  ',
        photos: [photo(1), photo(2)],
        limits: limits,
      );
      final adapter = UploadAdapter((request) {
        if (request.path == '/api/auth/csrf') {
          return jsonBody({'token': 'csrf-1'});
        }
        return jsonBody(receiptJson(batch), status: 201);
      });
      final (_, uploads) = repository(adapter);
      final receipt = await uploads.upload(batch);

      expect(receipt.newSerialNumber, '000123 / AB');
      expect(receipt.photoCount, 2);
      expect(adapter.requests.map((r) => r.path), [
        '/api/auth/csrf',
        '/api/uploads',
      ]);
      final post = adapter.requests.last;
      expect(post.headers['X-CSRF-Token'], 'csrf-1');
      expect(post.contentType, startsWith('multipart/form-data; boundary='));
      final form = post.data as FormData;
      expect(form.fields.single.key, 'manifest');
      final manifest =
      jsonDecode(form.fields.single.value) as Map<String, dynamic>;
      expect(manifest['newSerialNumber'], '000123 / AB');
      expect(manifest['oldSerialNumber'], 'OLD');
      expect(manifest.containsKey('ownerId'), isFalse);
      final metadata = manifest['photos'] as List;
      expect(metadata[0]['latitude'], batch.photos[0].location.latitude);
      expect(metadata[1]['latitude'], batch.photos[1].location.latitude);
      expect(metadata[0]['capturedAtUtc'], endsWith('Z'));
      expect(metadata[0]['locationMeasuredAtUtc'], endsWith('Z'));
      expect(form.files.map((file) => file.key), [
        'original_${batch.photos[0].id}',
        'stamped_${batch.photos[0].id}',
        'original_${batch.photos[1].id}',
        'stamped_${batch.photos[1].id}',
      ]);
      final wire = latin1.decode(adapter.bodies.single);
      for (final photo in batch.photos) {
        expect(wire, contains(latin1.decode(photo.originalBytes)));
        expect(wire, contains(latin1.decode(photo.stamped!.bytes)));
      }
    },
  );

  test(
    'retry keeps the batch ID but builds fresh multipart data and CSRF tokens',
        () async {
      final batch = UploadBatch.create(
        oldSerialNumber: 'OLD',
        newSerialNumber: '0007',
        photos: [photo(1)],
        limits: limits,
      );
      var csrf = 0;
      var posts = 0;
      final adapter = UploadAdapter((request) {
        if (request.path == '/api/auth/csrf') {
          return jsonBody({'token': 'csrf-${++csrf}'});
        }
        posts++;
        return jsonBody(
          receiptJson(batch, replayed: posts > 1),
          status: posts == 1 ? 201 : 200,
        );
      });
      final (_, uploads) = repository(adapter);
      await uploads.upload(batch);
      final second = await uploads.upload(batch);
      final writes = adapter.requests.where((r) => r.method == 'POST').toList();
      expect(second.replayed, isTrue);
      expect(writes.map((r) => r.headers['X-CSRF-Token']), [
        'csrf-1',
        'csrf-2',
      ]);
      expect(identical(writes[0].data, writes[1].data), isFalse);
      expect(
        (writes[0].data as FormData).fields.map(
              (entry) => [entry.key, entry.value],
        ),
        (writes[1].data as FormData).fields.map(
              (entry) => [entry.key, entry.value],
        ),
      );
      expect(adapter.bodies.length, 2);
    },
  );

  for (final entry in [
    (409, 'upload_id_conflict'),
    (400, 'invalid_photo_time'),
    (413, 'upload_too_large'),
  ]) {
    test('preserves upload error ${entry.$2}', () async {
      final batch = UploadBatch.create(
        oldSerialNumber: 'OLD',
        newSerialNumber: 'X',
        photos: [photo(1)],
        limits: limits,
      );
      final adapter = UploadAdapter(
            (request) => request.path == '/api/auth/csrf'
            ? jsonBody({'token': 'csrf'})
            : jsonBody({'code': entry.$2}, status: entry.$1),
      );
      final (_, uploads) = repository(adapter);
      await expectLater(uploads.upload(batch), throwsA(apiError(entry.$2)));
    });
  }

  test('missing CSRF prevents the multipart POST', () async {
    final batch = UploadBatch.create(
      oldSerialNumber: 'OLD',
      newSerialNumber: 'X',
      photos: [photo(1)],
      limits: limits,
    );
    final adapter = UploadAdapter((_) => jsonBody({}));
    final (_, uploads) = repository(adapter);
    await expectLater(
      uploads.upload(batch),
      throwsA(apiError('service_unavailable')),
    );
    expect(adapter.requests.single.path, '/api/auth/csrf');
  });

  test('a response for different photos cannot confirm this upload', () async {
    final batch = UploadBatch.create(
      oldSerialNumber: 'OLD',
      newSerialNumber: 'X',
      photos: [photo(1)],
      limits: limits,
    );
    final adapter = UploadAdapter((request) {
      if (request.path == '/api/auth/csrf') return jsonBody({'token': 'csrf'});
      return jsonBody(receiptJson(batch)..['photos'] = [], status: 201);
    });
    final (_, uploads) = repository(adapter);
    await expectLater(
      uploads.upload(batch),
      throwsA(apiError('service_unavailable')),
    );
  });

  test('reads server limits and rejects an expired session', () async {
    var expired = false;
    final adapter = UploadAdapter(
          (_) => expired
          ? jsonBody({}, status: 401)
          : jsonBody({
        'maxPhotos': 3,
        'maxSerialNumberLength': 17,
        'maxFileBytes': 1000,
        'maxBatchBytes': 5000,
      }),
    );
    final (_, uploads) = repository(adapter);
    final value = await uploads.getLimits();
    expect(value.maxPhotos, 3);
    expect(value.maxSerialNumberLength, 17);
    expired = true;
    await expectLater(
      uploads.getLimits(),
      throwsA(apiError('session_expired')),
    );
  });
}