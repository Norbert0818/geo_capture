import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/app.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/core/models/session_user.dart';
import 'package:geo_capture/features/auth/auth_repository.dart';

Finder byName(String name) => find.byKey(ValueKey(name));

SessionUser testUser({bool mustChangePassword = true, bool admin = false}) {
  return SessionUser(
    id: 'b1da98c8-87cc-473b-bd91-834c36a63591',
    username: 'worker01',
    mustChangePassword: mustChangePassword,
    roles: [admin ? 'Admin' : 'User'],
  );
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.restoredUser});

  SessionUser? restoredUser;
  Future<SessionUser?> Function()? onRestore;
  Future<SessionUser> Function(String, String)? onSignIn;
  Future<SessionUser> Function(String)? onChangePassword;

  int signInCalls = 0;
  int changeCalls = 0;
  int signOutCalls = 0;
  String? lastUsername;
  String? lastPassword;
  String? lastNewPassword;

  @override
  Future<SessionUser?> restoreSession() =>
      onRestore?.call() ?? Future.value(restoredUser);

  @override
  Future<SessionUser> signIn(String username, String password) async {
    signInCalls++;
    lastUsername = username;
    lastPassword = password;

    final action = onSignIn;
    return action == null ? testUser() : await action(username, password);
  }

  @override
  Future<SessionUser> changePassword(String next) async {
    changeCalls++;
    lastNewPassword = next;

    final action = onChangePassword;
    return action == null
        ? testUser(mustChangePassword: false)
        : await action(next);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  void dispose() {}
}

Future<void> start(WidgetTester tester, FakeAuthRepository auth) async {
  await tester.pumpWidget(GeoCaptureApp(authRepository: auth));
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String name, String value) async {
  await tester.ensureVisible(byName(name));
  await tester.enterText(byName(name), value);
}

Future<void> press(WidgetTester tester, String name) async {
  await tester.ensureVisible(byName(name));
  await tester.tap(byName(name));
  await tester.pumpAndSettle();
}

Future<void> fillLogin(
  WidgetTester tester, {
  String username = 'worker01',
  String password = 'InitialPassword927',
}) async {
  await enter(tester, 'usernameField', username);
  await enter(tester, 'passwordField', password);
}

Future<void> fillPasswords(
  WidgetTester tester, {
  String next = 'ChangedPassword927',
  String confirmation = 'ChangedPassword927',
}) async {
  await enter(tester, 'newPasswordField', next);
  await enter(tester, 'confirmPasswordField', confirmation);
}

void main() {
  testWidgets('starts with the English sign-in page', (tester) async {
    await start(tester, FakeAuthRepository());

    expect(find.text('Welcome back'), findsOneWidget);
    expect(byName('usernameField'), findsOneWidget);
    expect(find.text('Register'), findsNothing);
  });

  testWidgets('changing language preserves entered credentials', (
    tester,
  ) async {
    await start(tester, FakeAuthRepository());
    await fillLogin(tester);

    await tester.ensureVisible(find.text('RO'));
    await tester.tap(find.text('RO'));
    await tester.pumpAndSettle();

    expect(find.text('Bine ai revenit'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(byName('usernameField')).controller!.text,
      'worker01',
    );
    expect(
      tester.widget<TextFormField>(byName('passwordField')).controller!.text,
      'InitialPassword927',
    );
  });

  testWidgets('empty credentials never reach the repository', (tester) async {
    final auth = FakeAuthRepository();
    await start(tester, auth);
    await press(tester, 'signInButton');

    expect(find.text('Enter your username.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(auth.signInCalls, 0);
  });

  testWidgets('sign-in submits once and preserves password spaces', (
    tester,
  ) async {
    final pending = Completer<SessionUser>();
    final auth = FakeAuthRepository()..onSignIn = (_, _) => pending.future;
    await start(tester, auth);
    await fillLogin(tester, username: '  worker01  ', password: ' secret ');

    await tester.ensureVisible(byName('signInButton'));
    await tester.tap(byName('signInButton'));
    await tester.pump();

    expect(auth.signInCalls, 1);
    expect(auth.lastUsername, 'worker01');
    expect(auth.lastPassword, ' secret ');
    expect(
      tester.widget<FilledButton>(byName('signInButton')).onPressed,
      isNull,
    );

    pending.complete(testUser());
    await tester.pumpAndSettle();

    expect(byName('changePasswordPage'), findsOneWidget);
    expect(byName('accountPage'), findsNothing);
  });

  testWidgets('invalid credentials have a translated message', (tester) async {
    final auth = FakeAuthRepository()
      ..onSignIn = (_, _) async {
        throw const ApiException('invalid_credentials', statusCode: 401);
      };
    await start(tester, auth);
    await fillLogin(tester);
    await press(tester, 'signInButton');

    expect(find.text('Incorrect username or password.'), findsOneWidget);

    await tester.ensureVisible(find.text('RO'));
    await tester.tap(find.text('RO'));
    await tester.pumpAndSettle();

    expect(
      find.text('Nume de utilizator sau parolă incorectă.'),
      findsOneWidget,
    );
  });

  testWidgets('a restored pending account still requires a password change', (
    tester,
  ) async {
    final auth = FakeAuthRepository(restoredUser: testUser());
    await start(tester, auth);

    expect(byName('changePasswordPage'), findsOneWidget);
    expect(byName('currentPasswordField'), findsNothing);
    expect(byName('accountPage'), findsNothing);

    await press(tester, 'signOutButton');

    expect(auth.signOutCalls, 1);
    expect(byName('usernameField'), findsOneWidget);
  });

  testWidgets('a restored completed admin account opens its account page', (
    tester,
  ) async {
    await start(
      tester,
      FakeAuthRepository(
        restoredUser: testUser(mustChangePassword: false, admin: true),
      ),
    );

    expect(byName('accountPage'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);
    expect(byName('changePasswordPage'), findsNothing);
  });

  testWidgets('weak and mismatched passwords are rejected', (tester) async {
    final auth = FakeAuthRepository(restoredUser: testUser());
    await start(tester, auth);

    await fillPasswords(tester, next: 'short', confirmation: 'short');
    await press(tester, 'savePasswordButton');
    expect(auth.changeCalls, 0);

    await fillPasswords(tester, confirmation: 'DifferentPassword927');
    await press(tester, 'savePasswordButton');
    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(auth.changeCalls, 0);
  });

  testWidgets('successful password change opens the account page', (
    tester,
  ) async {
    final auth = FakeAuthRepository(restoredUser: testUser());
    await start(tester, auth);

    await fillPasswords(
      tester,
      next: ' ChangedPassword927 ',
      confirmation: ' ChangedPassword927 ',
    );
    await press(tester, 'savePasswordButton');

    expect(auth.changeCalls, 1);
    expect(auth.lastNewPassword, ' ChangedPassword927 ');
    expect(byName('accountPage'), findsOneWidget);
    expect(byName('changePasswordPage'), findsNothing);
  });

  testWidgets('the existing password is rejected by the server', (
    tester,
  ) async {
    final auth = FakeAuthRepository(restoredUser: testUser())
      ..onChangePassword = (_) async {
        throw const ApiException('password_unchanged', statusCode: 400);
      };
    await start(tester, auth);
    await fillPasswords(tester);
    await press(tester, 'savePasswordButton');

    expect(
      find.text('Choose a password different from your current password.'),
      findsOneWidget,
    );
    expect(byName('changePasswordPage'), findsOneWidget);
    expect(byName('accountPage'), findsNothing);
  });

  testWidgets('an expired session returns to sign-in', (tester) async {
    final auth = FakeAuthRepository(restoredUser: testUser())
      ..onChangePassword = (_) async {
        throw const ApiException('session_expired', statusCode: 401);
      };
    await start(tester, auth);
    await fillPasswords(tester);
    await press(tester, 'savePasswordButton');

    expect(byName('usernameField'), findsOneWidget);
    expect(
      find.text('Your session has expired. Please sign in again.'),
      findsOneWidget,
    );
    expect(byName('accountPage'), findsNothing);
  });

  testWidgets('a later login respects the completed password-change flag', (
    tester,
  ) async {
    final auth = FakeAuthRepository(
      restoredUser: testUser(mustChangePassword: false),
    )..onSignIn = (_, _) async => testUser(mustChangePassword: false);
    await start(tester, auth);
    await press(tester, 'signOutButton');

    await fillLogin(tester, password: 'ChangedPassword927');
    await press(tester, 'signInButton');

    expect(auth.signOutCalls, 1);
    expect(byName('accountPage'), findsOneWidget);
    expect(byName('changePasswordPage'), findsNothing);
  });

  testWidgets('startup waits for the server and allows retry after failure', (
    tester,
  ) async {
    final pending = Completer<SessionUser?>();
    var calls = 0;
    final auth = FakeAuthRepository()
      ..onRestore = () {
        calls++;
        return calls == 1
            ? pending.future
            : Future.value(testUser(mustChangePassword: false));
      };

    await tester.pumpWidget(GeoCaptureApp(authRepository: auth));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(byName('usernameField'), findsNothing);

    pending.completeError(const ApiException('service_unavailable'));
    await tester.pumpAndSettle();

    expect(byName('startupError'), findsOneWidget);
    expect(byName('usernameField'), findsNothing);

    await press(tester, 'retrySessionButton');

    expect(calls, 2);
    expect(byName('accountPage'), findsOneWidget);
  });

  testWidgets('the Romanian password form fits a narrow screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await start(tester, FakeAuthRepository(restoredUser: testUser()));
    await tester.ensureVisible(find.text('RO'));
    await tester.tap(find.text('RO'));
    await tester.pumpAndSettle();

    await fillPasswords(tester, next: 'short', confirmation: 'short');
    await press(tester, 'savePasswordButton');

    expect(find.text('Setează propria parolă'), findsOneWidget);
    expect(byName('changePasswordPage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
