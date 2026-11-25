import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/core/models/session_user.dart';
import 'package:geo_capture/features/field_work/work_file_share.dart';
import 'package:geo_capture/features/field_work/work_home_page.dart';
import 'package:geo_capture/features/field_work/work_list_filters.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_repository.dart';
import 'package:geo_capture/features/field_work/work_storage.dart';
import 'package:geo_capture/l10n/app_localizations.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;

import 'work_list_filter_widget_test.dart'
    show FilterRepository, openFilters, press, visible;
import 'work_test_support.dart' show workId, versionId;

class ExportRepository extends FilterRepository
    implements WorkExportRepository {
  final csvCalls = <({bool all, WorkListFilters filters})>[];
  final zipCalls = <({String id, int revision})>[];
  CancelToken? lastToken;
  Future<Uint8List> Function()? onCsv, onZip;
  final csvBytes = Uint8List.fromList([239, 187, 191, 65]);
  final zipBytes = Uint8List.fromList([80, 75, 3, 4]);
  @override
  Future<Uint8List> exportCsv({
    bool all = false,
    WorkListFilters filters = const WorkListFilters(),
    CancelToken? cancelToken,
  }) async {
    csvCalls.add((all: all, filters: filters));
    lastToken = cancelToken;
    return onCsv != null ? onCsv!() : csvBytes;
  }

  @override
  Future<Uint8List> exportZip(
      String id, {
        required int revision,
        CancelToken? cancelToken,
      }) async {
    zipCalls.add((id: id, revision: revision));
    lastToken = cancelToken;
    return onZip != null ? onZip!() : zipBytes;
  }

  @override
  Future<WorkDetails> details(String id) async => WorkDetails(
    id: id,
    version: versionId,
    revision: 3,
    owner: 'worker',
    document: WorkDocument(kind: WorkKind.pit),
  );
  @override
  Future<List<Map<String, dynamic>>> history(String id) async => [
    {
      'revision': 1,
      'actor': 'worker',
      'atUtc': '2026-11-24T12:00:00Z',
      'reason': 'Initial upload',
      'changes': ['created'],
      'document': WorkDocument(kind: WorkKind.pit).toJson(),
    },
  ];
}

class SharedExport {
  final files = <({Uint8List bytes, String name, String mime})>[];
  Future<void> call(
      BuildContext context,
      Uint8List bytes,
      String filename,
      String mimeType,
      ) async {
    files.add((bytes: bytes, name: filename, mime: mimeType));
  }
}

Widget exportShell(Widget child, {bool ro = false}) => MaterialApp(
  locale: Locale(ro ? 'ro' : 'en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: child,
);

Future<void> startHome(
    WidgetTester tester,
    ExportRepository repository,
    SharedExport shared, {
      bool admin = false,
      bool ro = false,
    }) async {
  final db = await databaseFactoryMemory.openDatabase('export-home');
  addTearDown(db.close);
  await tester.pumpWidget(
    exportShell(
      WorkHomePage(
        services: FieldWorkServices(
          repository: repository,
          storage: SembastWorkStorage(
            server: 'https://api.example.com',
            openDatabase: () async => db,
          ),
          shareFile: shared.call,
        ),
        user: SessionUser(
          id: workId,
          username: 'worker',
          roles: [admin ? 'Admin' : 'User'],
          mustChangePassword: false,
        ),
      ),
      ro: ro,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> startDetails(
    WidgetTester tester,
    ExportRepository repository,
    SharedExport shared, {
      bool ro = false,
    }) async {
  await tester.pumpWidget(
    exportShell(
      WorkDetailsPage(
        id: workId,
        repository: repository,
        onEdit: (_) async {},
        shareFile: shared.call,
      ),
      ro: ro,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('CSV uses applied filters rather than unsubmitted text', (
      tester,
      ) async {
    final repo = ExportRepository();
    final shared = SharedExport();
    await startHome(tester, repo, shared);
    await openFilters(tester);
    final serial = find.byKey(const ValueKey('workFilterSerial'));
    await tester.ensureVisible(serial);
    await tester.enterText(serial, '0007');
    await press(tester, 'applyWorkFilters');
    await tester.ensureVisible(serial);
    await tester.enterText(serial, 'not-applied');
    await press(tester, 'exportWorkCsv');
    expect(repo.csvCalls.single.filters.serial, '0007');
    expect(repo.csvCalls.single.all, isFalse);
    expect(shared.files.single.bytes, repo.csvBytes);
    expect(shared.files.single.mime, 'text/csv');
    expect(shared.files.single.name, endsWith('.csv'));
  });

  testWidgets('admin CSV export preserves all-user and owner scope', (
      tester,
      ) async {
    final repo = ExportRepository();
    final shared = SharedExport();
    await startHome(tester, repo, shared, admin: true);
    await press(tester, 'showAllWork');
    await openFilters(tester);
    final owner = find.byKey(const ValueKey('workFilterOwner'));
    await tester.ensureVisible(owner);
    await tester.enterText(owner, 'other-worker');
    await press(tester, 'applyWorkFilters');
    await press(tester, 'exportWorkCsv');
    expect(repo.csvCalls.single.all, isTrue);
    expect(repo.csvCalls.single.filters.owner, 'other-worker');
  });

  testWidgets(
    'pending CSV export disables duplicates and clears busy state after sharing',
        (tester) async {
      final pending = Completer<Uint8List>();
      final repo = ExportRepository()..onCsv = () => pending.future;
      final shared = SharedExport();
      await startHome(tester, repo, shared);
      final button = find.byKey(const ValueKey('exportWorkCsv'));
      await visible(tester, button);
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      expect(repo.csvCalls, hasLength(1));
      pending.complete(repo.csvBytes);
      await tester.pumpAndSettle();
      expect(shared.files, hasLength(1));
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    },
  );

  testWidgets(
    'an export error is shown without sharing an error response as a file',
        (tester) async {
      final repo = ExportRepository()
        ..onCsv = () async => throw const ApiException('work_export_too_many');
      final shared = SharedExport();
      await startHome(tester, repo, shared);
      await press(tester, 'exportWorkCsv');
      expect(shared.files, isEmpty);
      expect(find.textContaining('1,000 work records'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('exportWorkCsv')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('ZIP export pins the displayed revision and filename', (
      tester,
      ) async {
    final repo = ExportRepository();
    final shared = SharedExport();
    await startDetails(tester, repo, shared);
    await press(tester, 'exportWorkZip:3');
    expect(repo.zipCalls.single, (id: workId, revision: 3));
    expect(shared.files.single.bytes, repo.zipBytes);
    expect(shared.files.single.name, workZipFilename(workId, 3));
    expect(shared.files.single.mime, 'application/zip');
  });

  testWidgets(
    'a historical ZIP uses its own revision and shows shared busy state',
        (tester) async {
      final pending = Completer<Uint8List>();
      final repo = ExportRepository()..onZip = () => pending.future;
      final shared = SharedExport();
      await startDetails(tester, repo, shared);
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();
      await tester.tap(find.text('v1 · worker'));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('exportWorkZip:1'));
      await visible(tester, button);
      await tester.tap(button);
      await tester.pump();
      expect(repo.zipCalls.single.revision, 1);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      pending.complete(repo.zipBytes);
      await tester.pumpAndSettle();
      expect(shared.files.single.name, workZipFilename(workId, 1));
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    },
  );

  for (final zip in [false, true]) {
    testWidgets(
      'leaving ${zip ? 'ZIP' : 'CSV'} export cancels the request and prevents a late share',
          (tester) async {
        final pending = Completer<Uint8List>();
        final repo = ExportRepository();
        final shared = SharedExport();
        if (zip) {
          repo.onZip = () => pending.future;
          await startDetails(tester, repo, shared);
        } else {
          repo.onCsv = () => pending.future;
          await startHome(tester, repo, shared);
        }
        final button = find.byKey(
          ValueKey(zip ? 'exportWorkZip:3' : 'exportWorkCsv'),
        );
        await visible(tester, button);
        await tester.tap(button);
        await tester.pump();
        final token = repo.lastToken;
        expect(token, isNotNull);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        expect(token!.isCancelled, isTrue);
        pending.complete(zip ? repo.zipBytes : repo.csvBytes);
        await tester.pumpAndSettle();
        expect(shared.files, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Romanian export controls fit a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = ExportRepository();
    final shared = SharedExport();
    await startHome(tester, repo, shared, ro: true);
    await visible(tester, find.byKey(const ValueKey('exportWorkCsv')));
    expect(find.text('Exportă CSV filtrat'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await startDetails(tester, repo, shared, ro: true);
    expect(find.text('Exportă ZIP · v3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}