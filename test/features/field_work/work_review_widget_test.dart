import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/field_work/work_editor_page.dart';
import 'package:geo_capture/features/field_work/work_flow.dart';
import 'package:geo_capture/features/field_work/work_identity_editor.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/features/field_work/work_review_page.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import 'work_flow_test.dart' show reviewDocument, reviewPng;
import 'work_test_support.dart';

class ReviewRepository extends FakeWorkRepository {
  final images = <({String id, bool original})>[];
  @override
  Future<Uint8List> image(
      String workId,
      String photoId, {
        bool original = false,
      }) async {
    images.add((id: photoId, original: original));
    return reviewPng;
  }
}

Future<List<Object?>> openPage(
    WidgetTester tester,
    Widget page, {
      String language = 'en',
    }) async {
  final results = <Object?>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            key: const ValueKey('openReviewTestPage'),
            onPressed: () async {
              results.add(
                await Navigator.push<Object?>(
                  context,
                  MaterialPageRoute(builder: (_) => page),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('openReviewTestPage')));
  await tester.pumpAndSettle();
  return results;
}

Future<void> tapReview(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in WorkKind.values) {
    testWidgets(
      '${kind.name} review shows each required phase without uploading',
          (tester) async {
        final repo = ReviewRepository();
        final document = reviewDocument(kind);
        await openPage(
          tester,
          WorkReviewPage(
            draft: WorkDraft(id: workId, document: document),
            repository: repo,
          ),
        );
        final list = find.byKey(const ValueKey('workReviewList'));
        for (final phase in workFlow(kind)) {
          final card = find.byKey(ValueKey('reviewPhase:${phase.key}'));
          if (card.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              card,
              240,
              scrollable: find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first,
            );
          }
          expect(card, findsOneWidget);
        }
        expect(repo.sent, isEmpty);
        expect(repo.images, isEmpty);
        expect(
          tester
              .widget<FilledButton>(
            find.byKey(const ValueKey('confirmWorkUpload')),
          )
              .onPressed,
          isNotNull,
        );
      },
    );
  }

  testWidgets(
    'canceling review preserves the draft and confirmation performs one upload',
        (tester) async {
      final store = MemoryWorkStore();
      final repo = ReviewRepository();
      final document = reviewDocument(WorkKind.pit);
      final result = await openPage(
        tester,
        WorkEditorPage(
          draft: WorkDraft(id: workId, document: document),
          store: store,
          repository: repo,
          allowGeneration: false,
        ),
      );
      await tapReview(tester, 'workContinue');
      expect(find.byType(WorkReviewPage), findsOneWidget);
      expect(repo.sent, isEmpty);
      await tapReview(tester, 'cancelWorkReview');
      expect(repo.sent, isEmpty);
      expect(store.drafts[workId]!.document.photos, hasLength(1));
      await tapReview(tester, 'workContinue');
      await tapReview(tester, 'confirmWorkUpload');
      expect(repo.sent, hasLength(1));
      expect(store.drafts, isEmpty);
      expect(result, [true]);
      expect(repo.sent.single.document.toJson(), document.toJson());
    },
  );

  testWidgets(
    'editing the reviewed new identity returns to its exact wizard step',
        (tester) async {
      final store = MemoryWorkStore();
      final repo = ReviewRepository();
      await openPage(
        tester,
        WorkEditorPage(
          draft: WorkDraft(
            id: workId,
            document: reviewDocument(WorkKind.replacement),
          ),
          store: store,
          repository: repo,
          allowGeneration: false,
        ),
      );
      final last = find.text('New pole photo');
      await tester.ensureVisible(last);
      await tester.tap(last);
      await tester.pumpAndSettle();
      await tapReview(tester, 'workContinue');
      final edit = find.byKey(const ValueKey('editReview:newIdentity'));
      await tester.scrollUntilVisible(
        edit,
        240,
        scrollable: find
            .descendant(
          of: find.byKey(const ValueKey('workReviewList')),
          matching: find.byType(Scrollable),
        )
            .first,
      );
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(tester.widget<Stepper>(find.byType(Stepper)).currentStep, 2);
      final serial = find
          .descendant(
        of: find.byType(WorkIdentityEditor),
        matching: find.byType(TextField),
      )
          .first;
      await tester.ensureVisible(serial);
      await tester.enterText(serial, '0009999');
      await tester.pumpAndSettle();
      await tapReview(tester, 'workContinue');
      await tapReview(tester, 'workContinue');
      expect(repo.sent, isEmpty);
      await tapReview(tester, 'confirmWorkUpload');
      expect(repo.sent.single.document.newPole!.serialNumber, '0009999');
    },
  );

  testWidgets(
    'missing required photos stay in the editor without a network save',
        (tester) async {
      final repo = ReviewRepository();
      await openPage(
        tester,
        WorkEditorPage(
          draft: WorkDraft(
            id: workId,
            document: WorkDocument(kind: WorkKind.pit),
          ),
          store: MemoryWorkStore(),
          repository: repo,
          allowGeneration: false,
        ),
      );
      await tapReview(tester, 'workContinue');
      expect(find.byType(WorkReviewPage), findsNothing);
      expect(repo.sent, isEmpty);
      expect(
        find.text('Complete the required identifiers, photos and locations.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a revision must have its reason before review and shows that reason',
        (tester) async {
      final repo = ReviewRepository();
      await openPage(
        tester,
        WorkEditorPage(
          draft: WorkDraft(
            id: workId,
            document: reviewDocument(WorkKind.pit),
            expectedVersion: versionId,
            reason: 'ab',
          ),
          store: MemoryWorkStore(),
          repository: repo,
          allowGeneration: false,
        ),
      );
      await tapReview(tester, 'workContinue');
      expect(find.byType(WorkReviewPage), findsNothing);
      expect(repo.sent, isEmpty);
      final reason = find.byType(TextFormField).last;
      await tester.ensureVisible(reason);
      await tester.enterText(reason, 'Retook the photo');
      await tester.pumpAndSettle();
      await tapReview(tester, 'workContinue');
      final notes = find.text('Retook the photo');
      await tester.scrollUntilVisible(
        notes,
        240,
        scrollable: find
            .descendant(
          of: find.byKey(const ValueKey('workReviewList')),
          matching: find.byType(Scrollable),
        )
            .first,
      );
      expect(notes, findsOneWidget);
      expect(find.text('Save new revision'), findsOneWidget);
      await tapReview(tester, 'confirmWorkUpload');
      expect(repo.sent.single.reason, 'Retook the photo');
      expect(repo.sent.single.expectedVersion, versionId);
    },
  );

  testWidgets(
    'a frozen upload retry keeps its ID and bypasses a second review',
        (tester) async {
      final store = MemoryWorkStore();
      final repo = ReviewRepository();
      final draft = WorkDraft(
        id: workId,
        document: reviewDocument(WorkKind.replacement),
        pendingChangeId: versionId,
      );
      final revision = await store.write(draft);
      await openPage(
        tester,
        WorkEditorPage(
          draft: draft.copyWith(localRevision: revision),
          store: store,
          repository: repo,
          allowGeneration: false,
        ),
      );
      await tester.tap(find.text('Retry pending upload'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkReviewPage), findsNothing);
      expect(repo.sent, hasLength(1));
      expect(repo.sent.single.pendingChangeId, versionId);
    },
  );

  testWidgets('double confirmation cannot create two saves or pop two pages', (
      tester,
      ) async {
    final repo = ReviewRepository();
    final pending = Completer<WorkDetails>();
    repo.onSave = (_) => pending.future;
    final result = await openPage(
      tester,
      WorkEditorPage(
        draft: WorkDraft(id: workId, document: reviewDocument(WorkKind.pit)),
        store: MemoryWorkStore(),
        repository: repo,
        allowGeneration: false,
      ),
    );
    await tapReview(tester, 'workContinue');
    final confirm = find.byKey(const ValueKey('confirmWorkUpload'));
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.sent, hasLength(1));
    expect(result, isEmpty);
    pending.complete(
      WorkDetails(
        id: workId,
        version: versionId,
        revision: 1,
        owner: 'worker',
        document: WorkDocument.fromJson(repo.sent.single.document.toJson()),
      ),
    );
    await tester.pumpAndSettle();
    expect(result, [true]);
  });

  testWidgets(
    'review can inspect remote original and stamped photos without uploading',
        (tester) async {
      final repo = ReviewRepository();
      final document = reviewDocument(WorkKind.pit, local: false);
      await openPage(
        tester,
        WorkReviewPage(
          draft: WorkDraft(
            id: workId,
            document: document,
            expectedVersion: versionId,
            reason: 'Corrected data',
          ),
          repository: repo,
        ),
      );
      final image = find
          .descendant(
        of: find.byKey(
          ValueKey('reviewPhoto:${document.photos.single.id}'),
        ),
        matching: find.byType(InkWell),
      )
          .first;
      await tester.ensureVisible(image);
      await tester.tap(image);
      await tester.pumpAndSettle();
      expect(find.text('Original photo'), findsOneWidget);
      expect(
        tester
            .widget<InteractiveViewer>(
          find.byKey(const ValueKey('zoomStampedWorkPhoto')),
        )
            .maxScale,
        8,
      );
      expect(
        tester
            .widget<InteractiveViewer>(
          find.byKey(const ValueKey('zoomOriginalWorkPhoto')),
        )
            .maxScale,
        8,
      );
      expect(repo.images.any((call) => call.original), isTrue);
      expect(repo.sent, isEmpty);
    },
  );

  testWidgets('Romanian review actions stay above Android system navigation', (
      tester,
      ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await openPage(
      tester,
      WorkReviewPage(
        draft: WorkDraft(
          id: workId,
          document: reviewDocument(WorkKind.replacement),
        ),
        repository: ReviewRepository(),
      ),
      language: 'ro',
    );
    final button = find.byKey(const ValueKey('confirmWorkUpload'));
    expect(find.text('Încarcă lucrarea'), findsOneWidget);
    expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(720 - 48 - 16));
    expect(tester.takeException(), isNull);
  });
}