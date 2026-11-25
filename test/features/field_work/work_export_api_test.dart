import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/field_work/work_file_share.dart';
import 'package:geo_capture/features/field_work/work_list_filters.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_repository.dart';

import 'work_api_test.dart' show WorkApiAdapter;
import 'work_test_support.dart' show workId;

ResponseBody binary(List<int> bytes, String mime, {int status = 200}) =>
    ResponseBody.fromBytes(
      bytes,
      status,
      headers: {
        Headers.contentTypeHeader: [mime],
      },
    );
ApiClient client(WorkApiAdapter adapter) => ApiClient.fromDio(
  Dio(BaseOptions(baseUrl: 'https://api.example.com'))
    ..httpClientAdapter = adapter,
);

void main() {
  test(
    'CSV export sends the applied filters and scope but no page number',
        () async {
      final data = utf8.encode('\uFEFFwork_id,old_serial_number\r\n');
      final adapter = WorkApiAdapter(
            (_) => binary(data, 'text/csv; charset=utf-8'),
      );
      final repository = HttpWorkRepository(client(adapter));
      final result = await repository.exportCsv(
        all: true,
        filters: const WorkListFilters(
          kind: WorkKind.replacement,
          serial: '0007',
          owner: 'worker',
          locality: 'Sâncraiu',
          fromDate: '2026-11-25',
        ),
      );
      expect(result, data);
      final request = adapter.requests.single;
      expect(request.path, '/api/field-work/export.csv');
      expect(request.queryParameters, {
        'all': true,
        'kind': 'replacement',
        'serial': '0007',
        'owner': 'worker',
        'locality': 'Sâncraiu',
        'fromDate': '2026-11-25',
      });
      expect(request.headers['Accept'], 'text/csv');
    },
  );

  test('ZIP export explicitly pins the displayed revision', () async {
    final data = Uint8List.fromList([80, 75, 3, 4]);
    final adapter = WorkApiAdapter((_) => binary(data, 'application/zip'));
    final repository = HttpWorkRepository(client(adapter));
    expect(await repository.exportZip(workId, revision: 3), data);
    expect(adapter.requests.single.path, '/api/field-work/$workId/export.zip');
    expect(adapter.requests.single.queryParameters, {'revision': 3});
    expect(adapter.requests.single.headers['Accept'], 'application/zip');
  });

  for (final input in [
    (
    status: 400,
    code: 'work_export_too_many',
    expected: 'work_export_too_many',
    ),
    (
    status: 413,
    code: 'work_export_too_large',
    expected: 'work_export_too_large',
    ),
    (status: 401, code: 'unauthorized', expected: 'session_expired'),
    (status: 403, code: 'forbidden', expected: 'forbidden'),
  ]) {
    test(
      'binary error ${input.status} is decoded as ${input.expected}',
          () async {
        final adapter = WorkApiAdapter(
              (_) => binary(
            utf8.encode(jsonEncode({'code': input.code})),
            'application/json',
            status: input.status,
          ),
        );
        expect(
          HttpWorkRepository(client(adapter)).exportCsv(),
          throwsA(
            isA<ApiException>().having(
                  (error) => error.code,
              'code',
              input.expected,
            ),
          ),
        );
      },
    );
  }

  test('HTML or JSON success bodies cannot be shared as ZIP files', () async {
    final adapter = WorkApiAdapter(
          (_) => binary(utf8.encode('<html>Error</html>'), 'text/html'),
    );
    expect(
      HttpWorkRepository(client(adapter)).exportZip(workId, revision: 1),
      throwsA(
        isA<ApiException>().having(
              (error) => error.code,
          'code',
          'service_unavailable',
        ),
      ),
    );
  });

  test('the download byte limit and cancellation are enforced', () async {
    final adapter = WorkApiAdapter(
          (_) => binary([1, 2, 3, 4], 'application/zip'),
    );
    final api = client(adapter);
    expect(
      api.getFile('/file', mimeType: 'application/zip', maxBytes: 3),
      throwsA(
        isA<ApiException>().having(
              (error) => error.code,
          'code',
          'work_export_too_large',
        ),
      ),
    );
    final token = CancelToken()..cancel();
    expect(
      api.getFile('/file', mimeType: 'application/zip', cancelToken: token),
      throwsA(
        isA<ApiException>().having(
              (error) => error.code,
          'code',
          'request_cancelled',
        ),
      ),
    );
  });

  test(
    'export filenames are stable and contain no platform-specific path punctuation',
        () {
      expect(
        workCsvFilename(DateTime.utc(2026, 11, 25, 12, 34, 56)),
        'geocapture-works-20261125-123456.csv',
      );
      expect(
        workZipFilename(workId, 3),
        'work_11111111111141118111111111111111_v3.zip',
      );
    },
  );
}