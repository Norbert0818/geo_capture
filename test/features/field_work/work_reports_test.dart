import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/field_work/work_list_filters.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_reports_page.dart';
import 'package:geo_capture/features/field_work/work_repository.dart';

import 'modern_work_test_support.dart';
import 'serial_confirmation_test.dart' show serialTap;
import 'work_test_support.dart';

class ReportRepository extends FakeWorkRepository
    implements FilteredWorkRepository, WorkReportRepository {
  final searches = <({bool all, int page, WorkListFilters filters})>[];
  WorkListFilters? exported;
  bool? romanian;
  CancelToken? cancellation;
  Completer<Uint8List>? exportWait;
  Future<Map<String, dynamic>> Function(int page, WorkListFilters filters)?
  onList;
  @override
  Future<Map<String, dynamic>> listFiltered({
    bool all = false,
    int page = 1,
    WorkListFilters filters = const WorkListFilters(),
  }) async {
    searches.add((all: all, page: page, filters: filters));
    return onList != null
        ? await onList!(page, filters)
        : {'items': <Map<String, dynamic>>[], 'page': page, 'total': 0};
  }

  @override
  Future<Uint8List> exportReport({
    required WorkListFilters filters,
    required bool romanian,
    CancelToken? cancelToken,
  }) {
    exported = filters;
    this.romanian = romanian;
    cancellation = cancelToken;
    return exportWait?.future ??
        Future.value(Uint8List.fromList([239, 187, 191, 65]));
  }
}

void main() {
  testWidgets(
    'county and locality filters cascade and county changes clear the previous town',
        (tester) async {
      final repo = ReportRepository();
      await tester.pumpWidget(
        modernShell(
          WorkReportsPage(
            repository: repo,
            onOpen: (_) async {},
            loadPlaces: () async => smallCatalogue(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.searches.single.all, isTrue);
      expect(repo.searches.single.filters.kind, WorkKind.repair);
      expect(repo.searches.single.filters.state, 'completed');
      await serialTap(tester, 'reportLocality');
      await serialTap(tester, 'place:59443');
      expect(repo.searches.last.filters.localityCode, '59443');
      expect(repo.searches.last.filters.countyCode, '12');
      final county = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('reportCounty:12')),
      );
      county.onChanged!('31');
      await tester.pumpAndSettle();
      expect(repo.searches.last.filters.countyCode, '31');
      expect(repo.searches.last.filters.localityCode, '');
      expect(repo.searches.last.filters.locality, '');
    },
  );
  testWidgets('same-name villages show distinct communes before selection', (
      tester,
      ) async {
    final repo = ReportRepository();
    await tester.pumpWidget(
      modernShell(
        WorkReportsPage(
          repository: repo,
          onOpen: (_) async {},
          loadPlaces: () async => smallCatalogue(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await serialTap(tester, 'reportLocality');
    await tester.enterText(find.byKey(const ValueKey('placeSearch')), 'Valea');
    await tester.pumpAndSettle();
    expect(find.text('Alpha · Cluj'), findsOneWidget);
    expect(find.text('Beta · Cluj'), findsOneWidget);
    await serialTap(tester, 'place:10002');
    expect(repo.searches.last.filters.localityCode, '10002');
  });
  testWidgets(
    'report table presents both replacement positions and explicit damaged state',
        (tester) async {
      String? opened;
      await tester.pumpWidget(
        modernShell(
          Scaffold(
            body: WorkReportTable(
              kind: WorkKind.replacement,
              onOpen: (id) async => opened = id,
              items: [
                {
                  'id': workId,
                  'owner': 'worker',
                  'oldSerialNumber': '00012',
                  'newSerialNumber': '',
                  'photoCount': 4,
                  'report': {
                    'oldX': 46.1,
                    'oldY': 24.2,
                    'newX': 46.1001,
                    'newY': 24.2001,
                    'oldSerialState': 'damaged',
                    'newSerialState': 'missing',
                    'status': 'replaced',
                    'photoNames': [
                      '00012_vechi_01.jpg',
                      'fara_serie_nou_02.jpg',
                    ],
                  },
                },
              ],
            ),
          ),
        ),
      );
      expect(find.text('Old latitude (X)'), findsOneWidget);
      expect(find.text('New longitude (Y)'), findsOneWidget);
      expect(find.text('46.100000'), findsOneWidget);
      expect(find.text('46.100100'), findsOneWidget);
      expect(find.text('00012 · Damaged label'), findsOneWidget);
      expect(find.text('No serial'), findsOneWidget);
      final names = find.text('00012_vechi_01.jpg\nfara_serie_nou_02.jpg');
      await tester.ensureVisible(names);
      await tester.tap(names);
      await tester.pumpAndSettle();
      expect(opened, workId);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'typing filters waits for Apply and export carries precisely the applied filters',
        (tester) async {
      final repo = ReportRepository();
      final shared = <String>[];
      await tester.pumpWidget(
        modernShell(
          WorkReportsPage(
            repository: repo,
            onOpen: (_) async {},
            loadPlaces: () async => smallCatalogue(),
            shareFile: (_, bytes, filename, mime) async {
              shared.add(filename);
              expect(mime, 'text/csv');
            },
          ),
          language: 'ro',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('reportSerial')),
        '00012',
      );
      expect(repo.searches, hasLength(1));
      await serialTap(tester, 'applyReportFilters');
      await serialTap(tester, 'exportReportCsv');
      expect(repo.exported!.serial, '00012');
      expect(repo.romanian, isTrue);
      expect(shared.single, startsWith('repair_report_'));
    },
  );
  testWidgets(
    'changing report type cancels an obsolete download and never shares its bytes',
        (tester) async {
      final repo = ReportRepository()..exportWait = Completer<Uint8List>();
      var shared = 0;
      await tester.pumpWidget(
        modernShell(
          WorkReportsPage(
            repository: repo,
            onOpen: (_) async {},
            loadPlaces: () async => smallCatalogue(),
            shareFile: (_, _, _, _) async => shared++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await serialTap(tester, 'exportReportCsv');
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await serialTap(tester, 'reportKind:replacement');
      expect(repo.cancellation!.isCancelled, isTrue);
      repo.exportWait!.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();
      expect(shared, 0);
      expect(repo.searches.last.filters.kind, WorkKind.replacement);
    },
  );
  testWidgets('report pages keep the filters and show the next page', (
      tester,
      ) async {
    final repo = ReportRepository()
      ..onList = (page, filters) async => {
        'items': <Map<String, dynamic>>[],
        'page': page,
        'total': 21,
      };
    await tester.pumpWidget(
      modernShell(
        WorkReportsPage(
          repository: repo,
          onOpen: (_) async {},
          loadPlaces: () async => smallCatalogue(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final next = find.widgetWithText(TextButton, 'Next');
    await tester.scrollUntilVisible(
      next,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(repo.searches.last.page, 2);
    expect(repo.searches.last.filters.kind, WorkKind.repair);
  });
  testWidgets(
    'leaving report cancels pending export without touching a disposed context',
        (tester) async {
      final repo = ReportRepository()..exportWait = Completer<Uint8List>();
      var shared = 0;
      await tester.pumpWidget(
        modernShell(
          WorkReportsPage(
            repository: repo,
            onOpen: (_) async {},
            loadPlaces: () async => smallCatalogue(),
            shareFile: (_, _, _, _) async => shared++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await serialTap(tester, 'exportReportCsv');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(repo.cancellation!.isCancelled, isTrue);
      repo.exportWait!.complete(Uint8List.fromList([1]));
      await tester.pumpAndSettle();
      expect(shared, 0);
      expect(tester.takeException(), isNull);
    },
  );
}