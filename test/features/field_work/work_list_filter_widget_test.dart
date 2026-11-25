import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/models/session_user.dart';
import 'package:geo_capture/features/field_work/work_home_page.dart';
import 'package:geo_capture/features/field_work/work_list_filter_panel.dart';
import 'package:geo_capture/features/field_work/work_list_filters.dart';
import 'package:geo_capture/features/field_work/work_repository.dart';
import 'package:geo_capture/features/field_work/work_storage.dart';
import 'package:geo_capture/l10n/app_localizations.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;

import 'work_test_support.dart';

class FilterRepository extends FakeWorkRepository
    implements FilteredWorkRepository {
  final requests = <({bool all, int page, WorkListFilters filters})>[];
  Future<Map<String, dynamic>> Function(bool, int, WorkListFilters)? onList;
  @override
  Future<Map<String, dynamic>> listFiltered({
    bool all = false,
    int page = 1,
    WorkListFilters filters = const WorkListFilters(),
  }) async {
    requests.add((all: all, page: page, filters: filters));
    return onList != null
        ? onList!(all, page, filters)
        : {'items': [], 'total': 0, 'page': page};
  }
}

Widget shell(Widget child, {bool ro = false}) => MaterialApp(
  locale: Locale(ro ? 'ro' : 'en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: child,
);

Future<void> home(
    WidgetTester tester,
    FilterRepository repository, {
      bool admin = false,
    }) async {
  final db = await databaseFactoryMemory.openDatabase('search-widget');
  addTearDown(db.close);
  await tester.pumpWidget(
    shell(
      WorkHomePage(
        services: FieldWorkServices(
          repository: repository,
          storage: SembastWorkStorage(
            server: 'https://api.example.com',
            openDatabase: () async => db,
          ),
        ),
        user: SessionUser(
          id: workId,
          username: 'worker',
          roles: [admin ? 'Admin' : 'User'],
          mustChangePassword: false,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> visible(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      target,
      240,
      maxScrolls: 35,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> openFilters(WidgetTester tester) async {
  final title = find.text('Search uploaded work').evaluate().isNotEmpty
      ? find.text('Search uploaded work')
      : find.text('Caută lucrări încărcate');
  // Title text may itself not have been lazily built yet.
  final panel = find.byType(WorkListFilterPanel);
  await visible(tester, panel);
  final header = find.text('Search uploaded work').evaluate().isNotEmpty
      ? find.text('Search uploaded work')
      : title;
  await tester.tap(header);
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey(key));
  await visible(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Map<String, dynamic> item(String serial) => {
  'id': workId,
  'kind': 'replacement',
  'owner': 'worker',
  'revision': 2,
  'photoCount': 2,
  'serialNumber': serial,
  'oldSerialNumber': 'OLD-0007',
  'newSerialNumber': serial,
  'locations': ['Sâncraiu, Cluj'],
};

void main() {
  testWidgets(
    'applying a filter resets page two to page one and clearing resets the query',
        (tester) async {
      final repo = FilterRepository()
        ..onList = (all, page, filters) async => {
          'items': [
            item(filters.serial.isEmpty ? 'unfiltered' : filters.serial),
          ],
          'total': filters.isEmpty ? 25 : 1,
          'page': page,
        };
      await home(tester, repo);
      await press(tester, 'nextWorkPage');
      expect(repo.requests.last.page, 2);
      await openFilters(tester);
      final serial = find.byKey(const ValueKey('workFilterSerial'));
      await tester.ensureVisible(serial);
      await tester.enterText(serial, '0002610587');
      await press(tester, 'applyWorkFilters');
      expect(repo.requests.last.page, 1);
      expect(repo.requests.last.filters.serial, '0002610587');
      await visible(tester, find.textContaining('OLD-0007 → 0002610587'));
      expect(find.textContaining('OLD-0007 → 0002610587'), findsOneWidget);
      expect(find.textContaining('Sâncraiu, Cluj'), findsOneWidget);
      await press(tester, 'clearWorkFilters');
      expect(repo.requests.last.filters.isEmpty, isTrue);
      expect(repo.requests.last.page, 1);
    },
  );

  testWidgets('normal users never receive an owner filter control', (
      tester,
      ) async {
    await home(tester, FilterRepository());
    await openFilters(tester);
    expect(find.byKey(const ValueKey('workFilterOwner')), findsNothing);
    expect(find.byKey(const ValueKey('showAllWork')), findsNothing);
  });

  testWidgets('admin owner filter is cleared when switching back to own work', (
      tester,
      ) async {
    final repo = FilterRepository();
    await home(tester, repo, admin: true);
    await press(tester, 'showAllWork');
    await openFilters(tester);
    final owner = find.byKey(const ValueKey('workFilterOwner'));
    await tester.ensureVisible(owner);
    await tester.enterText(owner, 'other-worker');
    await press(tester, 'applyWorkFilters');
    expect(repo.requests.last.all, isTrue);
    expect(repo.requests.last.filters.owner, 'other-worker');
    await press(tester, 'showAllWork');
    expect(repo.requests.last.all, isFalse);
    expect(repo.requests.last.filters.owner, isEmpty);
    expect(find.byKey(const ValueKey('workFilterOwner')), findsNothing);
  });

  testWidgets('a reversed date range is rejected before sending a search', (
      tester,
      ) async {
    var called = false;
    await tester.pumpWidget(
      shell(
        Scaffold(
          body: SingleChildScrollView(
            child: WorkListFilterPanel(
              filters: const WorkListFilters(
                fromDate: '2026-11-26',
                toDate: '2026-11-25',
              ),
              showOwner: false,
              busy: false,
              onApply: (_) => called = true,
            ),
          ),
        ),
      ),
    );
    await openFilters(tester);
    await press(tester, 'applyWorkFilters');
    expect(called, isFalse);
    expect(
      find.text('The end date must be on or after the start date.'),
      findsOneWidget,
    );
  });

  testWidgets('Romanian filter controls fit a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      shell(
        Scaffold(
          body: SingleChildScrollView(
            child: WorkListFilterPanel(
              filters: const WorkListFilters(),
              showOwner: true,
              busy: false,
              onApply: (_) {},
            ),
          ),
        ),
        ro: true,
      ),
    );
    await openFilters(tester);
    await tester.pumpAndSettle();
    expect(find.text('Aplică filtrele'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed search can be retried without losing applied filters', (
      tester,
      ) async {
    final repo = FilterRepository();
    await home(tester, repo);
    await openFilters(tester);
    repo.onList = (_, _, _) async => throw StateError('offline');
    final serial = find.byKey(const ValueKey('workFilterSerial'));
    await tester.ensureVisible(serial);
    await tester.enterText(serial, '0007');
    await press(tester, 'applyWorkFilters');
    repo.onList = (_, page, filters) async => {
      'items': [item(filters.serial)],
      'total': 1,
      'page': page,
    };
    final refresh = find.byIcon(Icons.refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(repo.requests.last.filters.serial, '0007');
    await visible(tester, find.textContaining('OLD-0007 → 0007'));
    expect(find.textContaining('OLD-0007 → 0007'), findsOneWidget);
  });

  testWidgets('late responses cannot update a page after disposal', (
      tester,
      ) async {
    final pending = Completer<Map<String, dynamic>>();
    final repo = FilterRepository();
    await home(tester, repo);
    repo.onList = (_, _, _) => pending.future;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete({'items': [], 'total': 0, 'page': 1});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}