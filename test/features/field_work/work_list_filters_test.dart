import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/field_work/work_list_filters.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_repository.dart';

import 'work_api_test.dart' show WorkApiAdapter, reply;

void main() {
  test('empty filters do not add query arguments', () {
    expect(const WorkListFilters().isEmpty, isTrue);
    expect(const WorkListFilters().toQueryParameters(), isEmpty);
  });

  test('identifiers keep leading zeroes and filter text is trimmed', () {
    const filters = WorkListFilters(
      kind: WorkKind.replacement,
      serial: ' 0002610586 ',
      ntet: ' T0PL0138RO ',
      locality: ' Sâncraiu ',
      county: ' Cluj ',
      owner: ' worker ',
      fromDate: '2026-11-24',
      toDate: '2026-11-25',
    );
    expect(filters.toQueryParameters(), {
      'kind': 'replacement',
      'serial': '0002610586',
      'ntet': 'T0PL0138RO',
      'locality': 'Sâncraiu',
      'county': 'Cluj',
      'owner': 'worker',
      'fromDate': '2026-11-24',
      'toDate': '2026-11-25',
    });
  });

  test('leaving all-user scope removes only the owner filter', () {
    const filters = WorkListFilters(
      owner: 'worker',
      serial: '0007',
      locality: 'Zalău',
    );
    expect(filters.withoutOwner().toQueryParameters(), {
      'serial': '0007',
      'locality': 'Zalău',
    });
  });

  test('capture dates are calendar days without UTC conversion', () {
    expect(WorkListFilters.date(DateTime(2026, 11, 25, 0, 30)), '2026-11-25');
    expect(
      const WorkListFilters(
        fromDate: '2026-11-25',
        toDate: '2026-11-25',
      ).validDates,
      isTrue,
    );
    expect(const WorkListFilters(toDate: '2026-11-25').validDates, isTrue);
    expect(
      const WorkListFilters(
        fromDate: '2026-11-26',
        toDate: '2026-11-25',
      ).validDates,
      isFalse,
    );
    expect(const WorkListFilters(fromDate: '2026-02-30').validDates, isFalse);
  });

  test(
    'HTTP repository sends filters with page and scope as separate query values',
        () async {
      final adapter = WorkApiAdapter(
            (_) => reply({'items': [], 'total': 0, 'page': 2}),
      );
      final client = ApiClient.fromDio(
        Dio(BaseOptions(baseUrl: 'https://api.example.com'))
          ..httpClientAdapter = adapter,
      );
      final repository = HttpWorkRepository(client);
      const serial = "0007%_' OR 1=1 --";
      await repository.listFiltered(
        all: true,
        page: 2,
        filters: const WorkListFilters(
          serial: serial,
          locality: 'Sâncraiu',
          fromDate: '2026-11-25',
        ),
      );
      final request = adapter.requests.single;
      expect(request.queryParameters, {
        'all': true,
        'page': 2,
        'serial': serial,
        'locality': 'Sâncraiu',
        'fromDate': '2026-11-25',
      });
      expect(request.path, '/api/field-work');
    },
  );

  test('the original list method still works without filters', () async {
    final adapter = WorkApiAdapter(
          (_) => reply({'items': [], 'total': 0, 'page': 1}),
    );
    final repository = HttpWorkRepository(
      ApiClient.fromDio(
        Dio(BaseOptions(baseUrl: 'https://api.example.com'))
          ..httpClientAdapter = adapter,
      ),
    );
    await repository.list();
    expect(adapter.requests.single.queryParameters, {'all': false, 'page': 1});
  });
}