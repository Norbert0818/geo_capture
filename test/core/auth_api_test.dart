import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/core/models/session_user.dart';
import 'package:geo_capture/features/auth/auth_repository.dart';

Map<String, dynamic> userJson({bool mustChangePassword = true}) => {
  'id': 'b1da98c8-87cc-473b-bd91-834c36a63591',
  'username': 'worker01',
  'mustChangePassword': mustChangePassword,
  'roles': ['User'],
};

ResponseBody jsonResponse(Object? body, {int status = 200}) {
  return ResponseBody.fromString(
    body == null ? '' : jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handle);

  final FutureOr<ResponseBody> Function(RequestOptions) handle;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture,
      ) async {
    requests.add(options);
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

HttpAuthRepository createRepository(FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
  dio.httpClientAdapter = adapter;
  return HttpAuthRepository(ApiClient.fromDio(dio));
}

void main() {
  test('sign-in gets CSRF first and preserves password whitespace', () async {
    final adapter = FakeAdapter((request) {
      if (request.path == '/api/auth/csrf') {
        return jsonResponse({'token': 'csrf-1'});
      }
      return jsonResponse(userJson());
    });

    final auth = createRepository(adapter);
    addTearDown(auth.dispose);

    final user = await auth.signIn('  worker01  ', ' secret ');

    expect(user.mustChangePassword, isTrue);
    expect(adapter.requests.map((r) => r.path).toList(), [
      '/api/auth/csrf',
      '/api/auth/login',
    ]);
    expect(adapter.requests.last.headers['X-CSRF-Token'], 'csrf-1');
    expect(adapter.requests.last.data, {
      'username': 'worker01',
      'password': ' secret ',
    });
  });

  test('every write gets a fresh CSRF token', () async {
    var tokenNumber = 0;

    final adapter = FakeAdapter((request) {
      if (request.path == '/api/auth/csrf') {
        return jsonResponse({'token': 'csrf-${++tokenNumber}'});
      }
      if (request.path == '/api/auth/logout') {
        return jsonResponse(null, status: 204);
      }
      return jsonResponse(
        userJson(mustChangePassword: request.path == '/api/auth/login'),
      );
    });

    final auth = createRepository(adapter);
    addTearDown(auth.dispose);

    await auth.signIn('worker01', 'InitialPassword927');
    final changed = await auth.changePassword(
      'ChangedPassword927',
    );
    await auth.signOut();

    expect(changed.mustChangePassword, isFalse);

    final writes = adapter.requests.where((r) => r.method == 'POST').toList();
    expect(writes[1].path, '/api/auth/initial-password');
    expect(writes[1].data, {'newPassword': 'ChangedPassword927'});
    expect(
      writes.map((r) => r.headers['X-CSRF-Token']).toList(),
      ['csrf-1', 'csrf-2', 'csrf-3'],
    );
  });

  test('an expired session restores as signed out', () async {
    final auth = createRepository(
      FakeAdapter((_) => jsonResponse(null, status: 401)),
    );
    addTearDown(auth.dispose);

    expect(await auth.restoreSession(), isNull);
  });

  test('a server failure is not treated as a signed-out session', () async {
    final auth = createRepository(
      FakeAdapter((_) => jsonResponse(null, status: 503)),
    );
    addTearDown(auth.dispose);

    await expectLater(
      auth.restoreSession(),
      throwsA(
        isA<ApiException>().having(
              (error) => error.code,
          'code',
          'service_unavailable',
        ),
      ),
    );
  });

  test('incorrect credentials produce a specific error', () async {
    final auth = createRepository(FakeAdapter((request) {
      return request.path == '/api/auth/csrf'
          ? jsonResponse({'token': 'csrf'})
          : jsonResponse(null, status: 401);
    }));
    addTearDown(auth.dispose);

    await expectLater(
      auth.signIn('worker01', 'wrong-password'),
      throwsA(
        isA<ApiException>().having(
              (error) => error.code,
          'code',
          'invalid_credentials',
        ),
      ),
    );
  });

  test('a weak new password has its own error', () async {
    final auth = createRepository(FakeAdapter((request) {
      return request.path == '/api/auth/csrf'
          ? jsonResponse({'token': 'csrf'})
          : jsonResponse({
        'code': 'password_change_failed',
        'details': ['PasswordTooShort'],
      }, status: 400);
    }));
    addTearDown(auth.dispose);

    await expectLater(
      auth.changePassword('short'),
      throwsA(
        isA<ApiException>().having(
              (error) => error.code,
          'code',
          'password_rules',
        ),
      ),
    );
  });

  test('a missing CSRF token prevents submission', () async {
    final adapter = FakeAdapter((_) => jsonResponse({}));
    final auth = createRepository(adapter);
    addTearDown(auth.dispose);

    await expectLater(
      auth.signIn('worker01', 'InitialPassword927'),
      throwsA(isA<ApiException>()),
    );

    expect(adapter.requests.length, 1);
    expect(adapter.requests.single.path, '/api/auth/csrf');
  });

  test('a user response must include the password-change flag', () {
    final json = userJson()..remove('mustChangePassword');

    expect(
          () => SessionUser.fromJson(json),
      throwsFormatException,
    );
  });

  test('the repository returns an existing session', () async {
    final auth = createRepository(
      FakeAdapter((_) => jsonResponse(userJson(mustChangePassword: false))),
    );
    addTearDown(auth.dispose);

    final user = await auth.restoreSession();

    expect(user!.username, 'worker01');
    expect(user.mustChangePassword, isFalse);
  });
}