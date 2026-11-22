import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/app.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/admin/admin_accounts_page.dart';
import 'package:geo_capture/features/admin/admin_accounts_repository.dart';
import 'package:geo_capture/l10n/app_localizations.dart';

import 'accounts_test_support.dart';

Finder key(String value) => find.byKey(ValueKey(value));
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late FakeAccountsRepository repository;
  setUp(() => repository = FakeAccountsRepository());
  Future<void> start(WidgetTester tester, {String language = 'en'}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AdminAccountsPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final admin in [false, true]) {
    testWidgets('only an administrator sees Users: admin=$admin', (
      tester,
    ) async {
      await tester.pumpWidget(
        GeoCaptureApp(
          authRepository: AccountsTestAuth(admin: admin),
          accountsRepository: repository,
        ),
      );
      await tester.pumpAndSettle();
      expect(key('manageUsersButton'), admin ? findsOneWidget : findsNothing);
      if (admin) {
        await tap(tester, key('manageUsersButton'));
        expect(repository.pages, [1]);
      }
    });
  }

  testWidgets(
    'creates a user, shows credentials once, then clears the dialog',
    (tester) async {
      await start(tester);
      await tap(tester, key('createUserButton'));
      await tap(tester, key('confirmCreateAccount'));
      expect(repository.created, isEmpty);
      await tester.enterText(key('newUsernameField'), 'new-worker');
      await tap(tester, key('confirmCreateAccount'));
      expect(repository.created, ['new-worker']);
      expect(key('createdUsername'), findsOneWidget);
      expect(key('createdPassword'), findsOneWidget);
      await tap(tester, key('closeCredentialsButton'));
      expect(key('createdPassword'), findsNothing);
      expect(find.text('Gc9!GeneratedTestPassword1234'), findsNothing);
      await tester.scrollUntilVisible(find.text('new-worker'), 200);
      expect(find.text('new-worker'), findsOneWidget);
    },
  );

  testWidgets('canceling account creation sends nothing', (tester) async {
    await start(tester);
    await tap(tester, key('createUserButton'));
    await tester.enterText(key('newUsernameField'), 'unused');
    await tap(tester, key('cancelCreateAccount'));
    expect(repository.created, isEmpty);
  });

  testWidgets(
    'a duplicate username shows an error without hiding the user list',
    (tester) async {
      repository.onCreate = (_) async =>
          throw const ApiException('username_exists', statusCode: 409);
      await start(tester);
      await tap(tester, key('createUserButton'));
      await tester.enterText(key('newUsernameField'), 'worker02');
      await tap(tester, key('confirmCreateAccount'));
      expect(key('createAccountError'), findsOneWidget);
      expect(key('createdPassword'), findsNothing);
      await tap(tester, key('cancelCreateAccount'));
      await tap(tester, key('refreshAccountsButton'));
      expect(repository.pages.length, 2);
    },
  );

  testWidgets(
    'disable and enable require confirmation and the latest version',
    (tester) async {
      await start(tester);
      await tap(tester, key('status:${accountId(2)}'));
      await tap(tester, find.text('Cancel'));
      expect(repository.statuses, isEmpty);
      await tap(tester, key('status:${accountId(2)}'));
      await tap(tester, key('confirmAccountAction'));
      expect(repository.statuses.single.active, isFalse);
      final firstVersion = repository.statuses.single.version;
      await tap(tester, key('status:${accountId(2)}'));
      await tap(tester, key('confirmAccountAction'));
      expect(repository.statuses.last.active, isTrue);
      expect(repository.statuses.last.version, isNot(firstVersion));
    },
  );

  testWidgets(
    'admins are protected and a temporary password is only offered before the first change',
    (tester) async {
      await start(tester);
      expect(key('status:${accountId(1)}'), findsNothing);
      expect(key('temporary:${accountId(3)}'), findsNothing);
      await tap(tester, key('temporary:${accountId(2)}'));
      await tap(tester, key('confirmAccountAction'));
      expect(repository.temporary, [accountId(2)]);
      expect(find.text('Gc9!ReplacementTestPassword1234'), findsOneWidget);
      await tap(tester, key('closeCredentialsButton'));
    },
  );

  testWidgets('Romanian creation and credentials fit a narrow mobile screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await start(tester, language: 'ro');
    await tap(tester, key('createUserButton'));
    await tester.enterText(key('newUsernameField'), 'nou-utilizator');
    await tap(tester, key('confirmCreateAccount'));
    expect(find.text('Date de autentificare'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tap(tester, key('closeCredentialsButton'));
  });

  testWidgets('a second click cannot submit a second create request', (
    tester,
  ) async {
    final pending = Completer<AccountCredentials>();
    repository.onCreate = (_) => pending.future;
    await start(tester);
    await tap(tester, key('createUserButton'));
    await tester.enterText(key('newUsernameField'), 'new-worker');
    await tester.tap(key('confirmCreateAccount'));
    await tester.pump();
    await tester.tap(key('confirmCreateAccount'));
    await tester.pump();
    expect(repository.created, ['new-worker']);
    pending.complete(AccountCredentials.fromJson(credentialsJson()));
    await tester.pumpAndSettle();
    await tap(tester, key('closeCredentialsButton'));
  });

  testWidgets(
    'a concurrency conflict stays on the admin page and asks for refresh',
    (tester) async {
      repository.statusFailure = const ApiException(
        'account_conflict',
        statusCode: 409,
      );
      await start(tester);
      await tap(tester, key('status:${accountId(2)}'));
      await tap(tester, key('confirmAccountAction'));
      expect(key('accountActionError'), findsOneWidget);
      repository.statusFailure = null;
      await tap(tester, key('refreshAccountsButton'));
      expect(key('accountActionError'), findsNothing);
    },
  );
}
