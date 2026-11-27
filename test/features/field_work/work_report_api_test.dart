import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/field_work/work_list_filters.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_repository.dart';

import 'work_api_test.dart' show WorkApiAdapter;

void main() {
  test('report CSV pins work type language county town state and all-users scope without pagination', () async {
    final adapter = WorkApiAdapter(
          (_) => ResponseBody.fromBytes(
        [239, 187, 191, 65],
        200,
        headers: {
          Headers.contentTypeHeader: ['text/csv; charset=utf-8'],
        },
      ),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..httpClientAdapter = adapter;
    final repository = HttpWorkRepository(ApiClient.fromDio(dio));
    await repository.exportReport(
      filters: const WorkListFilters(
        kind: WorkKind.replacement,
        countyCode: '12',
        localityCode: '59443',
        state: 'in_progress',
        serial: '00012',
      ),
      romanian: true,
    );
    final request = adapter.requests.single;
    expect(request.path, '/api/field-work/reports.csv');
    expect(request.queryParameters, {
      'all': true,
      'kind': 'replacement',
      'countyCode': '12',
      'localityCode': '59443',
      'state': 'in_progress',
      'serial': '00012',
      'lang': 'ro',
    });
    expect(request.headers['Accept'], 'text/csv');
  });
}