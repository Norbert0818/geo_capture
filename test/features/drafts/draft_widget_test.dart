import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/app.dart';
import 'package:geo_capture/core/models/session_user.dart';
import 'package:geo_capture/features/auth/auth_repository.dart';
import 'package:geo_capture/features/capture/photo_draft_store.dart';
import 'package:geo_capture/features/drafts/draft_snapshot.dart';
import 'package:geo_capture/features/drafts/draft_storage_panel.dart';
import 'package:geo_capture/features/uploads/upload_panel.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import '../uploads/upload_test_support.dart';
import 'draft_test_support.dart';

Finder key(String value) => find.byKey(ValueKey(value));

class _Auth implements AuthRepository {
  _Auth(this.current);
  SessionUser? current;
  @override
  Future<SessionUser?> restoreSession() async => current;
  @override
  Future<SessionUser> signIn(String username, String password) async =>
      current = SessionUser(
        id: username,
        username: username,
        mustChangePassword: false,
        roles: ['User'],
      );
  @override
  Future<SessionUser> changePassword(String newPassword) async => current!;
  @override
  Future<void> signOut() async {
    current = null;
  }

  @override
  void dispose() {}
}

void main() {
  Widget app(Widget child, {String language = 'en'}) => MaterialApp(
    locale: Locale(language),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets(
    'closing and reopening the form restores both partially typed fields',
        (tester) async {
      final disk = TestDraftDisk();
      var drafts = PhotoDraftStore(persistence: disk);
      await drafts.restore();
      await tester.pumpWidget(
        app(SerialNumberDialog(limits: limits, drafts: drafts)),
      );
      await tester.enterText(key('oldSerialNumberField'), '00012-OLD');
      await tester.enterText(key('newSerialNumberField'), '00034-NEW');
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      drafts.dispose();
      drafts = PhotoDraftStore(persistence: disk);
      addTearDown(drafts.dispose);
      await drafts.restore();
      await tester.pumpWidget(
        app(SerialNumberDialog(limits: limits, drafts: drafts)),
      );
      expect(
        tester
            .widget<TextFormField>(key('oldSerialNumberField'))
            .controller!
            .text,
        '00012-OLD',
      );
      expect(
        tester
            .widget<TextFormField>(key('newSerialNumberField'))
            .controller!
            .text,
        '00034-NEW',
      );
    },
  );

  testWidgets(
    'a failed local save is visible and the retry button saves the photo',
        (tester) async {
      final disk = TestDraftDisk()..failWrites = true;
      final drafts = PhotoDraftStore(persistence: disk);
      addTearDown(drafts.dispose);
      await drafts.restore();
      await drafts.capture(() async => photo(1));
      await tester.pumpWidget(app(DraftStoragePanel(drafts: drafts)));
      expect(key('localDraftError'), findsOneWidget);
      disk.failWrites = false;
      await tester.tap(key('retryLocalDrafts'));
      await tester.pumpAndSettle();
      expect(key('localDraftError'), findsNothing);
      expect(disk.saved.snapshot.photos, hasLength(1));
    },
  );

  testWidgets('Romanian storage error controls fit a narrow screen', (
      tester,
      ) async {
    tester.view.physicalSize = const Size(320, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final disk = TestDraftDisk()..failWrites = true;
    final drafts = PhotoDraftStore(persistence: disk);
    addTearDown(drafts.dispose);
    await drafts.restore();
    await drafts.capture(() async => photo(1));
    await tester.pumpWidget(
      app(
        SingleChildScrollView(child: DraftStoragePanel(drafts: drafts)),
        language: 'ro',
      ),
    );
    expect(find.text('Reîncearcă salvarea locală'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account restores only the signed-in users photo count across sign-out',
        (tester) async {
      final storage = TestDraftStorage();
      await storage
          .forUser('a')
          .write(
        DraftSnapshot(photos: [photo(1), photo(2)]),
        expectedRevision: 0,
      );
      final auth = _Auth(
        SessionUser(
          id: 'a',
          username: 'a',
          mustChangePassword: false,
          roles: ['User'],
        ),
      );
      await tester.pumpWidget(
        GeoCaptureApp(authRepository: auth, draftStorage: storage),
      );
      await tester.pumpAndSettle();
      expect(find.text('Photos (2)'), findsOneWidget);
      await tester.tap(key('signOutButton'));
      await tester.pumpAndSettle();
      await tester.enterText(key('usernameField'), 'b');
      await tester.enterText(key('passwordField'), 'password');
      await tester.tap(key('signInButton'));
      await tester.pumpAndSettle();
      expect(find.text('Photos (0)'), findsOneWidget);
      expect(storage.forUser('a').saved.snapshot.photos, hasLength(2));
      await tester.tap(key('signOutButton'));
      await tester.pumpAndSettle();
      await tester.enterText(key('usernameField'), 'a');
      await tester.enterText(key('passwordField'), 'password');
      await tester.tap(key('signInButton'));
      await tester.pumpAndSettle();
      expect(find.text('Photos (2)'), findsOneWidget);
    },
  );

  testWidgets('read failure leaves capture disabled and saved data intact', (
      tester,
      ) async {
    final storage = TestDraftStorage();
    final disk = storage.forUser('a');
    await disk.write(DraftSnapshot(photos: [photo(1)]), expectedRevision: 0);
    disk.failReads = true;
    final auth = _Auth(
      SessionUser(
        id: 'a',
        username: 'a',
        mustChangePassword: false,
        roles: ['User'],
      ),
    );
    await tester.pumpWidget(
      GeoCaptureApp(authRepository: auth, draftStorage: storage),
    );
    await tester.pumpAndSettle();
    expect(key('localDraftError'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(key('openPhotosButton')).onPressed,
      isNull,
    );
    expect(disk.saved.snapshot.photos, hasLength(1));
    disk.failReads = false;
    await tester.tap(key('retryLocalDrafts'));
    await tester.pumpAndSettle();
    expect(find.text('Photos (1)'), findsOneWidget);
  });
}