import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/app.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/core/models/session_user.dart';
import 'package:geo_capture/features/auth/account_page.dart';
import 'package:geo_capture/features/auth/auth_repository.dart';
import 'package:geo_capture/features/uploads/upload_details_page.dart';
import 'package:geo_capture/features/uploads/upload_history_models.dart';
import 'package:geo_capture/features/uploads/upload_history_page.dart';
import 'package:geo_capture/features/uploads/uploaded_photo_page.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import 'history_test_support.dart';
import 'upload_test_support.dart' as upload_test;

Finder key(String name) => find.byKey(ValueKey(name));

SessionUser user({bool admin = false}) => SessionUser(
  id: '44444444-4444-4444-8444-444444444444',
  username: 'worker01',
  mustChangePassword: false,
  roles: [admin ? 'Admin' : 'User'],
);

class HistoryTestAuth implements AuthRepository {
  @override
  Future<SessionUser?> restoreSession() async => user();
  @override
  Future<SessionUser> signIn(String username, String password) async => user();
  @override
  Future<SessionUser> changePassword(String password) async => user();
  @override
  Future<void> signOut() async {}
  @override
  void dispose() {}
}

Widget app(Widget home, {String language = 'en'}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: home,
);

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late FakeHistoryRepository repository;
  setUp(() => repository = FakeHistoryRepository());

  testWidgets(
    'the app passes the shared history repository to the own-upload button',
    (tester) async {
      await tester.pumpWidget(
        GeoCaptureApp(
          authRepository: HistoryTestAuth(),
          historyRepository: repository,
        ),
      );
      await tester.pumpAndSettle();
      expect(key('myUploadsButton'), findsOneWidget);
      expect(key('allUploadsButton'), findsNothing);
      await tap(tester, key('myUploadsButton'));
      expect(repository.lists.single.allUsers, isFalse);
      expect(find.text('My uploads'), findsOneWidget);
    },
  );

  testWidgets(
    'an admin gets an all-upload button using the admin endpoint mode',
    (tester) async {
      await tester.pumpWidget(
        app(
          AccountPage(
            user: user(admin: true),
            locale: const Locale('en'),
            onLocaleChanged: (_) {},
            onSignOut: () async {},
            historyRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(key('myUploadsButton'), findsOneWidget);
      await tap(tester, key('allUploadsButton'));
      expect(repository.lists.single.allUsers, isTrue);
      expect(find.text('All uploads'), findsOneWidget);
      expect(find.text('Uploaded by: worker02'), findsWidgets);
    },
  );

  testWidgets(
    'paging requests the next and previous pages without loading images',
    (tester) async {
      await tester.pumpWidget(app(UploadHistoryPage(repository: repository)));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 3'), findsOneWidget);
      await tap(tester, key('nextHistoryPage'));
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(find.text('00013 / AB'), findsOneWidget);
      await tap(tester, key('previousHistoryPage'));
      expect(repository.lists.map((call) => call.page), [1, 2, 1]);
      expect(repository.images, isEmpty);
      expect(repository.detailsCalls, isEmpty);
    },
  );

  testWidgets('an empty list can be refreshed and is different from an error', (
    tester,
  ) async {
    repository.onList = (_, page, size) async =>
        UploadHistoryResult.fromJson(pageJson(total: 0));
    await tester.pumpWidget(app(UploadHistoryPage(repository: repository)));
    await tester.pumpAndSettle();
    expect(key('historyEmpty'), findsOneWidget);
    expect(tester.widget<IconButton>(key('nextHistoryPage')).onPressed, isNull);
    repository.onList = null;
    await tap(tester, key('refreshHistoryButton'));
    expect(key('historyEmpty'), findsNothing);
    expect(find.text('0001 / AB'), findsOneWidget);
  });

  testWidgets('a forbidden response shows an error and retry can recover', (
    tester,
  ) async {
    repository.onList = (_, page, size) async =>
        throw const ApiException('forbidden', statusCode: 403);
    await tester.pumpWidget(
      app(UploadHistoryPage(repository: repository, allUsers: true)),
    );
    await tester.pumpAndSettle();
    expect(key('historyError'), findsOneWidget);
    expect(key('historyEmpty'), findsNothing);
    repository.onList = null;
    await tap(tester, find.text('Try again'));
    expect(key('historyError'), findsNothing);
    expect(find.text('0001 / AB'), findsOneWidget);
  });

  testWidgets(
    'details open images only on demand and switch between both variants',
    (tester) async {
      await tester.pumpWidget(app(UploadHistoryPage(repository: repository)));
      await tester.pumpAndSettle();
      await tap(tester, key('upload:${uploadId(1)}'));
      expect(repository.detailsCalls.single, uploadId(1));
      expect(repository.images, isEmpty);
      expect(find.text('47.181912, 23.165123'), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      await tap(tester, key('stamped:${savedPhotoId(1)}'));
      expect(repository.images.single.original, isFalse);
      expect(repository.images.single.photoId, savedPhotoId(1));
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tap(tester, key('viewOriginalChip'));
      expect(repository.images.last.original, isTrue);
      final provider =
          tester.widget<Image>(key('savedPhotoImage')).image as MemoryImage;
      expect(provider.bytes, orderedEquals(upload_test.photo(1).originalBytes));
    },
  );

  testWidgets('Romanian details fit a narrow phone screen', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        UploadDetailsPage(repository: repository, uploadId: uploadId(1)),
        language: 'ro',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Detaliile încărcării'), findsOneWidget);
    await tester.ensureVisible(key('original:${savedPhotoId(1)}'));
    await tester.pumpAndSettle();
    expect(find.text('Cu coordonate'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an unavailable image shows the session error instead of a broken thumbnail',
    (tester) async {
      repository.onImage = (_, photo, original) async =>
          throw const ApiException('session_expired', statusCode: 401);
      await tester.pumpWidget(
        app(
          UploadedPhotoPage(
            repository: repository,
            uploadId: uploadId(1),
            photo: StoredPhoto.fromJson(storedPhotoJson(1)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Your session has expired. Sign in again.'),
        findsOneWidget,
      );
      expect(key('savedPhotoImage'), findsNothing);
    },
  );

  testWidgets(
    'a slower old image request cannot replace a newly selected variant',
    (tester) async {
      final old = Completer<Uint8List>();
      repository.onImage = (_, photo, original) async =>
          original ? upload_test.photo(1).originalBytes : await old.future;
      await tester.pumpWidget(
        app(
          UploadedPhotoPage(
            repository: repository,
            uploadId: uploadId(1),
            photo: StoredPhoto.fromJson(storedPhotoJson(1)),
          ),
        ),
      );
      await tester.pump();
      await tap(tester, key('viewOriginalChip'));
      expect(repository.images.first.cancelToken!.isCancelled, isTrue);
      old.complete(upload_test.photo(1).stamped!.bytes);
      await tester.pumpAndSettle();
      final provider =
          tester.widget<Image>(key('savedPhotoImage')).image as MemoryImage;
      expect(provider.bytes, orderedEquals(upload_test.photo(1).originalBytes));
      expect(
        tester.widget<ChoiceChip>(key('viewOriginalChip')).selected,
        isTrue,
      );
    },
  );

  testWidgets(
    'closing an image cancels its request without a late state update',
    (tester) async {
      final result = Completer<Uint8List>();
      repository.onImage = (_, photo, original) => result.future;
      await tester.pumpWidget(
        app(
          UploadedPhotoPage(
            repository: repository,
            uploadId: uploadId(1),
            photo: StoredPhoto.fromJson(storedPhotoJson(1)),
          ),
        ),
      );
      await tester.pump();
      final token = repository.images.single.cancelToken!;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(token.isCancelled, isTrue);
      result.complete(upload_test.photo(1).stamped!.bytes);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a slow previous list response cannot overwrite a changed view', (
    tester,
  ) async {
    final old = Completer<UploadHistoryResult>();
    repository.onList = (all, page, size) => all
        ? Future.value(UploadHistoryResult.fromJson(pageJson()))
        : old.future;
    await tester.pumpWidget(app(UploadHistoryPage(repository: repository)));
    await tester.pump();
    await tester.pumpWidget(
      app(UploadHistoryPage(repository: repository, allUsers: true)),
    );
    await tester.pumpAndSettle();
    old.complete(UploadHistoryResult.fromJson(pageJson(total: 0)));
    await tester.pumpAndSettle();
    expect(find.text('All uploads'), findsOneWidget);
    expect(key('historyEmpty'), findsNothing);
    expect(find.text('0001 / AB'), findsOneWidget);
  });
}
