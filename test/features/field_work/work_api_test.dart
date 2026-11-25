import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_repository.dart';

import 'work_test_support.dart';

class WorkApiAdapter implements HttpClientAdapter {
  WorkApiAdapter(this.handle);
  final FutureOr<ResponseBody> Function(RequestOptions) handle;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? body,
      Future<void>? cancel,
      ) async {
    requests.add(options);
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody reply(Object data, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  test(
    'save sends one JSON manifest and both variants of every new photo',
        () async {
      final doc = sampleWorkDocument(kind: WorkKind.replacement);
      late WorkApiAdapter adapter;
      adapter = WorkApiAdapter((request) {
        if (request.path.endsWith('/csrf')) return reply({'token': 'csrf'});
        final body = request.data as FormData;
        expect(body.fields.single.key, 'manifest');
        final manifest = jsonDecode(body.fields.single.value) as Map;
        expect(manifest['changeId'], versionId);
        expect((manifest['document'] as Map)['kind'], 'replacement');
        expect(body.files.length, 4);
        expect(request.headers['X-CSRF-Token'], 'csrf');
        return reply({
          'id': workId,
          'version': versionId,
          'revision': 1,
          'owner': 'worker',
          'document': doc.toJson(),
        });
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter;
      final api = ApiClient.fromDio(dio);
      addTearDown(api.close);
      final result = await HttpWorkRepository(
        api,
      ).save(WorkDraft(id: workId, document: doc, pendingChangeId: versionId));
      expect(result.document.photos.length, 2);
      expect(adapter.requests.map((r) => r.method), ['GET', 'POST']);
    },
  );
  test(
    'editing metadata reuses stored images without uploading them again',
        () async {
      final doc = sampleWorkDocument(local: false);
      final adapter = WorkApiAdapter((request) {
        if (request.path.endsWith('/csrf')) return reply({'token': 'csrf'});
        expect((request.data as FormData).files, isEmpty);
        return reply({
          'id': workId,
          'version': versionId,
          'revision': 2,
          'owner': 'worker',
          'document': doc.toJson(),
        });
      });
      final api = ApiClient.fromDio(
        Dio(BaseOptions(baseUrl: 'https://api.example.com'))
          ..httpClientAdapter = adapter,
      );
      addTearDown(api.close);
      await HttpWorkRepository(api).save(
        WorkDraft(
          id: workId,
          document: doc,
          expectedVersion: versionId,
          pendingChangeId: photoId,
          reason: 'Fixed notes',
        ),
      );
    },
  );
  test(
    'work conflict remains a specific error for preserving local edits',
        () async {
      final adapter = WorkApiAdapter(
            (request) => request.path.endsWith('/csrf')
            ? reply({'token': 'csrf'})
            : reply({'code': 'work_conflict'}, status: 409),
      );
      final api = ApiClient.fromDio(
        Dio(BaseOptions(baseUrl: 'https://api.example.com'))
          ..httpClientAdapter = adapter,
      );
      addTearDown(api.close);
      await expectLater(
        HttpWorkRepository(api).save(
          WorkDraft(
            id: workId,
            document: sampleWorkDocument(),
            pendingChangeId: photoId,
          ),
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'work_conflict'),
        ),
      );
    },
  );
}