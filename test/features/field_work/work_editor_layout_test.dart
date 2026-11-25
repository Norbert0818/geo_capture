import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/field_work/work_editor_page.dart';
import 'package:geo_capture/features/field_work/work_identity_editor.dart';
import 'package:geo_capture/features/field_work/work_models.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import 'work_test_support.dart';

class DelayedWorkStore extends MemoryWorkStore {
  Completer<void>? gate;
  @override
  Future<int> write(WorkDraft draft) async {
    if (gate != null) await gate!.future;
    return super.write(draft);
  }
}

void main() {
  for (final language in ['en', 'ro']) {
    testWidgets(
      '$language typing keeps the form position stable while autosaving',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = DelayedWorkStore();
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: WorkEditorPage(
              draft: WorkDraft(
                id: workId,
                document: sampleWorkDocument(kind: WorkKind.removal),
              ),
              store: store,
              repository: FakeWorkRepository(),
              allowGeneration: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find
            .descendant(
          of: find.byType(WorkIdentityEditor),
          matching: find.byType(TextField),
        )
            .first;
        await tester.ensureVisible(field);
        await tester.showKeyboard(field);
        await tester.pumpAndSettle();
        final before = tester.getTopLeft(field);
        final status = find.byKey(const ValueKey('workSaveStatus'));
        final statusSize = tester.getSize(status);
        store.gate = Completer<void>();
        await tester.enterText(field, '0002610586');
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.getTopLeft(field), before);
        expect(tester.getSize(status), statusSize);
        expect(
          tester.widget<TextField>(field).controller!.selection.baseOffset,
          10,
        );
        store.gate!.complete();
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(field), before);
        expect(tester.getSize(status), statusSize);
        expect(
          store.drafts[workId]!.document.oldPole!.serialNumber,
          '0002610586',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}