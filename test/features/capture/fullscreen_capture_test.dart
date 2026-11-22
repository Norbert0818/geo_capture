import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/capture/capture_view.dart';
import 'package:geo_capture/features/capture/photo_draft.dart';
import 'package:geo_capture/features/capture/photo_draft_store.dart';
import 'package:geo_capture/features/uploads/upload_batch.dart';
import 'package:geo_capture/features/uploads/upload_controller.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import '../uploads/upload_test_support.dart';

Finder key(String name) => find.byKey(ValueKey(name));

void main() {
  late PhotoDraftStore drafts;
  late FakeUploadRepository repository;
  late UploadController uploads;

  setUp(() {
    drafts = PhotoDraftStore();
    repository = FakeUploadRepository();
    uploads = UploadController(drafts: drafts, repository: repository);
  });

  tearDown(() {
    uploads.dispose();
    drafts.dispose();
  });

  Future<void> start(
      WidgetTester tester, {
        Size size = const Size(390, 844),
        String language = 'en',
        bool loading = false,
        bool ready = true,
        String? error,
        VoidCallback? takePhoto,
        VoidCallback? retry,
        double textScale = 1,
      }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('openCamera'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => CaptureView(
                      drafts: drafts,
                      uploads: uploads,
                      loading: loading,
                      cameraReady: ready,
                      cameraError: error,
                      onTakePhoto:
                      takePhoto ??
                              () => drafts.capture(() async => photo(1)),
                      onRetry: retry ?? () {},
                      preview: const ColoredBox(
                        key: ValueKey('liveCamera'),
                        color: Colors.teal,
                      ),
                    ),
                  ),
                ),
                child: const Text('Open camera'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(key('openCamera'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> gallery(WidgetTester tester) async {
    await tester.tap(key('reviewPhotosButton'));
    await tester.pumpAndSettle();
  }

  Future<void> beginUpload(WidgetTester tester, String serial) async {
    await tester.tap(key('openUploadButton'));
    await tester.pumpAndSettle();
    expect(key('serialNumberField'), findsOneWidget);
    await tester.enterText(key('serialNumberField'), serial);
    await tester.tap(key('confirmUploadButton'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('camera fills the screen behind safe, reachable controls', (
      tester,
      ) async {
    await start(tester);
    final viewport = tester.getRect(key('cameraViewport'));
    expect(viewport, const Rect.fromLTWH(0, 0, 390, 844));
    expect(tester.getRect(key('liveCamera')), viewport);
    expect(
      tester.getRect(key('closeCameraButton')).top,
      greaterThanOrEqualTo(28),
    );
    expect(
      tester.getRect(key('takePhotoButton')).bottom,
      lessThanOrEqualTo(820),
    );
    expect(find.byType(AppBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape camera still fills the page and controls fit', (
      tester,
      ) async {
    await start(tester, size: const Size(844, 390));
    expect(tester.getSize(key('cameraViewport')), const Size(844, 390));
    expect(
      tester.getRect(key('takePhotoButton')).bottom,
      lessThanOrEqualTo(366),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Romanian controls fit a narrow screen with larger text', (
      tester,
      ) async {
    await start(
      tester,
      size: const Size(320, 568),
      language: 'ro',
      textScale: 1.4,
    );
    expect(find.text('Fotografii (0)'), findsOneWidget);
    expect(find.text('Încarcă'), findsOneWidget);
    expect(find.byTooltip('Fă o fotografie'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shutter adds a photo and updates the visible photo count', (
      tester,
      ) async {
    await start(tester);
    await tester.tap(key('takePhotoButton'));
    await tester.pumpAndSettle();
    expect(drafts.items, hasLength(1));
    expect(find.text('Photos (1)'), findsOneWidget);
    expect(tester.widget<Text>(key('cameraPhotoCount')).data, '1');
    expect(
      tester.widget<TextButton>(key('openUploadButton')).onPressed,
      isNotNull,
    );
  });

  testWidgets('capture blocks repeated shots and leaving until it completes', (
      tester,
      ) async {
    final result = Completer<PhotoDraft>();
    await start(tester, takePhoto: () => drafts.capture(() => result.future));
    await tester.tap(key('takePhotoButton'));
    await tester.pump();
    expect(tester.widget<IconButton>(key('takePhotoButton')).onPressed, isNull);
    expect(
      tester.widget<IconButton>(key('closeCameraButton')).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(key('reviewPhotosButton')).onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(key('cameraViewport'), findsOneWidget);
    result.complete(photo(1));
    await tester.pumpAndSettle();
    await tester.tap(key('closeCameraButton'));
    await tester.pumpAndSettle();
    expect(key('openCamera'), findsOneWidget);
  });

  testWidgets('loading camera cannot take a photo', (tester) async {
    await start(tester, loading: true, ready: false);
    expect(find.text('Starting camera...'), findsOneWidget);
    expect(tester.widget<IconButton>(key('takePhotoButton')).onPressed, isNull);
    expect(key('liveCamera'), findsNothing);
  });

  testWidgets(
    'camera error offers retry while saved drafts remain accessible',
        (tester) async {
      var retries = 0;
      await drafts.capture(() async => photo(1));
      await start(
        tester,
        ready: false,
        error: 'camera_unavailable',
        retry: () => retries++,
      );
      await tester.tap(key('retryCameraButton'));
      expect(retries, 1);
      expect(
        tester.widget<IconButton>(key('takePhotoButton')).onPressed,
        isNull,
      );
      await gallery(tester);
      expect(find.text('Pending photos (1)'), findsOneWidget);
    },
  );

  testWidgets('empty gallery opens without a serial prompt or upload', (
      tester,
      ) async {
    await start(tester);
    expect(
      tester.widget<TextButton>(key('openUploadButton')).onPressed,
      isNull,
    );
    await gallery(tester);
    expect(find.text('No photos yet.'), findsOneWidget);
    expect(key('serialNumberField'), findsNothing);
    expect(repository.batches, isEmpty);
    await tester.tap(key('closePhotoReviewButton'));
    await tester.pumpAndSettle();
    expect(key('cameraViewport'), findsOneWidget);
  });

  testWidgets('gallery removes only the selected draft', (tester) async {
    await drafts.capture(() async => photo(1));
    await drafts.capture(() async => photo(2));
    final remainingId = drafts.items.last.id;
    await start(tester);
    await gallery(tester);
    final remove = find.byTooltip('Remove photo').first;
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(drafts.items.single.id, remainingId);
    expect(find.text('Pending photos (1)'), findsOneWidget);
  });

  testWidgets('upload opens the serial dialog and cancel retains the photo', (
      tester,
      ) async {
    await drafts.capture(() async => photo(1));
    await start(tester);
    await tester.tap(key('openUploadButton'));
    await tester.pumpAndSettle();
    expect(key('serialNumberField'), findsOneWidget);
    await tester.tap(key('cancelUploadButton'));
    await tester.pumpAndSettle();
    expect(repository.batches, isEmpty);
    expect(drafts.items, hasLength(1));
    expect(key('closePhotoReviewButton'), findsOneWidget);
  });

  testWidgets(
    'upload keeps drafts and blocks closing until server confirmation',
        (tester) async {
      final result = Completer<UploadReceipt>();
      repository.onUpload = (_) => result.future;
      await drafts.capture(() async => photo(1));
      await start(tester);
      await beginUpload(tester, '000123');
      expect(repository.batches.single.serialNumber, '000123');
      expect(drafts.items, hasLength(1));
      expect(
        tester.widget<IconButton>(key('closePhotoReviewButton')).onPressed,
        isNull,
      );
      repository.progress!(100, 100);
      await tester.pump();
      expect(key('uploadSuccess'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(key('closePhotoReviewButton'), findsOneWidget);
      result.complete(receiptFor(repository.batches.single));
      await tester.pumpAndSettle();
      expect(drafts.items, isEmpty);
      expect(key('uploadSuccess'), findsOneWidget);
      await tester.tap(key('closePhotoReviewButton'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(key('takePhotoButton')).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'an unconfirmed upload stays locked and retries with the same batch id',
        (tester) async {
      repository.onUpload = (_) async =>
      throw const ApiException('service_unavailable');
      await drafts.capture(() async => photo(1));
      await start(tester);
      await beginUpload(tester, 'A-0001');
      await tester.pumpAndSettle();
      final batch = repository.batches.single;
      await tester.tap(key('closePhotoReviewButton'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(key('takePhotoButton')).onPressed,
        isNull,
      );
      repository.onUpload = (value) async => receiptFor(value, replayed: true);
      await tester.tap(key('openUploadButton'));
      await tester.pumpAndSettle();
      expect(key('serialNumberField'), findsNothing);
      expect(repository.batches.last.id, batch.id);
      expect(drafts.items, isEmpty);
      expect(key('uploadSuccess'), findsOneWidget);
    },
  );

  testWidgets('reviewing existing photos does not start an upload', (
      tester,
      ) async {
    await drafts.capture(() async => photo(1));
    await start(tester);
    await gallery(tester);
    expect(repository.limitsCalls, 0);
    expect(repository.batches, isEmpty);
    expect(key('serialNumberField'), findsNothing);
  });

  testWidgets('scrolling the review does not reopen a canceled serial prompt', (
      tester,
      ) async {
    for (var number = 1; number <= 5; number++) {
      await drafts.capture(() async => photo(number));
    }
    await start(tester);
    await tester.tap(key('openUploadButton'));
    await tester.pumpAndSettle();
    await tester.tap(key('cancelUploadButton'));
    await tester.pumpAndSettle();
    await tester.drag(key('photoReviewList'), const Offset(0, -2400));
    await tester.pumpAndSettle();
    await tester.drag(key('photoReviewList'), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(key('uploadPhotosButton'), findsOneWidget);
    expect(key('serialNumberField'), findsNothing);
    expect(repository.batches, isEmpty);
  });
}