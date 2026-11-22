import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/auth/auth_repository.dart';
import 'package:geo_capture/features/uploads/upload_history_models.dart';
import 'package:geo_capture/features/uploads/upload_history_repository.dart';

import 'history_test_support.dart';
import 'upload_test_support.dart' as upload_test;

ResponseBody jsonBody(
  Object value, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(value),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

class HistoryAdapter implements HttpClientAdapter {
  HistoryAdapter(this.handle);
  final FutureOr<ResponseBody> Function(RequestOptions) handle;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) await requestStream.drain<void>();
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

(ApiClient, HttpUploadHistoryRepository) repository(
  HistoryAdapter adapter, {
  bool cookies = false,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
    ..httpClientAdapter = adapter;
  if (cookies) dio.interceptors.add(CookieManager(CookieJar()));
  final api = ApiClient.fromDio(dio);
  addTearDown(api.close);
  return (api, HttpUploadHistoryRepository(api));
}

Matcher code(String value) =>
    isA<ApiException>().having((e) => e.code, 'code', value);

void main() {
  test(
    'uses the own-upload endpoint and preserves pagination and leading zeros',
    () async {
      final adapter = HistoryAdapter(
        (_) => jsonBody(pageJson(page: 2, total: 13)),
      );
      final (_, history) = repository(adapter);
      final page = await history.list(page: 2);
      expect(adapter.requests.single.path, '/api/uploads');
      expect(adapter.requests.single.queryParameters, {
        'page': 2,
        'pageSize': 12,
      });
      expect(
        adapter.requests.single.queryParameters.containsKey('ownerId'),
        isFalse,
      );
      expect(page.items.single.serialNumber, '00013 / AB');
      expect(page.total, 13);
      expect(page.hasPrevious, isTrue);
      expect(page.hasNext, isFalse);
    },
  );

  test('uses the admin endpoint only for an all-users request', () async {
    final adapter = HistoryAdapter((_) => jsonBody(pageJson()));
    final (_, history) = repository(adapter);
    await history.list(allUsers: true);
    expect(adapter.requests.single.path, '/api/admin/uploads');
  });

  test('list and details do not prefetch image bytes', () async {
    final adapter = HistoryAdapter(
      (request) => jsonBody(
        request.path == '/api/uploads' ? pageJson() : detailsJson(1),
      ),
    );
    final (_, history) = repository(adapter);
    await history.list();
    final details = await history.details(uploadId(1));
    expect(adapter.requests, hasLength(2));
    expect(details.photos, hasLength(2));
    expect(details.photos.first.coordinatesText, '47.181912, 23.165123');
    expect(details.photos.first.capturedAtUtc.isUtc, isTrue);
  });

  test(
    'fetches both image variants by server IDs through the shared session',
    () async {
      final fixture = upload_test.photo(1);
      final adapter = HistoryAdapter((request) {
        if (request.path == '/api/auth/csrf') {
          return jsonBody({'token': 'csrf'});
        }
        if (request.path == '/api/auth/login') {
          return jsonBody(
            {
              'id': '44444444-4444-4444-8444-444444444444',
              'username': 'worker01',
              'mustChangePassword': false,
              'roles': ['User'],
            },
            headers: {
              'set-cookie': [
                'GeoCapture.Session=test-session; Path=/; Secure; HttpOnly; SameSite=Strict',
              ],
            },
          );
        }
        final original = request.path.endsWith('/original');
        return ResponseBody.fromBytes(
          original ? fixture.originalBytes : fixture.stamped!.bytes,
          200,
          headers: {
            Headers.contentTypeHeader: [original ? 'image/png' : 'image/jpeg'],
          },
        );
      });
      final (api, history) = repository(adapter, cookies: true);
      await HttpAuthRepository(api).signIn('worker01', 'InitialPassword927');
      final original = await history.image(
        uploadId(1),
        savedPhotoId(1),
        original: true,
      );
      final stamped = await history.image(
        uploadId(1),
        savedPhotoId(1),
        original: false,
      );
      expect(original, orderedEquals(fixture.originalBytes));
      expect(stamped, orderedEquals(fixture.stamped!.bytes));
      final requests = adapter.requests.skip(2).toList();
      expect(requests.map((r) => r.path), [
        '/api/uploads/${uploadId(1)}/photos/${savedPhotoId(1)}/original',
        '/api/uploads/${uploadId(1)}/photos/${savedPhotoId(1)}/stamped',
      ]);
      for (final request in requests) {
        expect(
          request.headers['cookie'],
          contains('GeoCapture.Session=test-session'),
        );
        expect(request.responseType, ResponseType.bytes);
        expect(request.headers['X-CSRF-Token'], isNull);
      }
    },
  );

  test(
    'ignores arbitrary image URLs from JSON and rejects path injection',
    () async {
      final adapter = HistoryAdapter((_) => jsonBody(detailsJson(1)));
      final (_, history) = repository(adapter);
      final details = await history.details(uploadId(1));
      expect(details.photos.first.id, savedPhotoId(1));
      expect(adapter.requests.single.uri.host, 'api.example.test');
      expect(
        () => history.image(
          'https://outside.invalid/',
          savedPhotoId(1),
          original: true,
        ),
        throwsA(code('not_found')),
      );
      expect(
        () => history.image(uploadId(1), '../photo', original: true),
        throwsA(code('not_found')),
      );
      expect(adapter.requests, hasLength(1));
    },
  );

  for (final status in [401, 403, 404]) {
    test(
      'keeps image access error $status meaningful with a binary response',
      () async {
        final adapter = HistoryAdapter((_) => jsonBody({}, status: status));
        final (_, history) = repository(adapter);
        final error = switch (status) {
          401 => 'session_expired',
          403 => 'forbidden',
          _ => 'not_found',
        };
        await expectLater(
          history.image(uploadId(1), savedPhotoId(1), original: false),
          throwsA(code(error)),
        );
      },
    );
  }

  test('a forbidden admin request is not displayed as an empty list', () async {
    final adapter = HistoryAdapter((_) => jsonBody({}, status: 403));
    final (_, history) = repository(adapter);
    await expectLater(history.list(allUsers: true), throwsA(code('forbidden')));
  });

  test('HTML or JSON cannot be accepted as a successful image', () async {
    final adapter = HistoryAdapter((_) => jsonBody({'status': 'not a photo'}));
    final (_, history) = repository(adapter);
    await expectLater(
      history.image(uploadId(1), savedPhotoId(1), original: true),
      throwsA(code('service_unavailable')),
    );
  });

  test('rejects malformed list data and a mismatched detail ID', () async {
    var malformed = true;
    final adapter = HistoryAdapter(
      (_) => jsonBody(
        malformed
            ? (pageJson()..['items'] = ['not an object'])
            : detailsJson(2),
      ),
    );
    final (_, history) = repository(adapter);
    await expectLater(history.list(), throwsA(code('service_unavailable')));
    malformed = false;
    await expectLater(
      history.details(uploadId(1)),
      throwsA(code('service_unavailable')),
    );
  });

  test('sorts photos by position and converts explicit timestamps to UTC', () {
    final json = detailsJson(1);
    final photos = (json['photos'] as List).reversed.toList();
    photos.first['capturedAtUtc'] = '2026-11-20T14:00:00+02:00';
    json['photos'] = photos;
    final details = StoredUpload.fromJson(json);
    expect(details.photos.map((p) => p.position), [0, 1]);
    expect(details.photos.last.capturedAtUtc, DateTime.utc(2026, 11, 20, 12));
    expect(details.photos.first.originalWidth, 16);
    expect(details.photos.first.originalSha256.length, 64);
  });
}
