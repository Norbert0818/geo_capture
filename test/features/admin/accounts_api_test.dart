import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/features/admin/admin_accounts_repository.dart';

import 'accounts_test_support.dart';

ResponseBody body(Object value, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(value),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class AccountsAdapter implements HttpClientAdapter {
  AccountsAdapter(this.handle);
  final FutureOr<ResponseBody> Function(RequestOptions) handle;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    if (stream != null) await stream.drain<void>();
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

HttpAdminAccountsRepository repository(AccountsAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
    ..httpClientAdapter = adapter;
  final api = ApiClient.fromDio(dio);
  addTearDown(api.close);
  return HttpAdminAccountsRepository(api);
}

void main() {
  test(
    'creation sends only a trimmed username with a fresh CSRF token',
    () async {
      final adapter = AccountsAdapter(
        (request) => request.path == '/api/auth/csrf'
            ? body({'token': 'csrf-1'})
            : body(credentialsJson(username: 'worker01'), status: 201),
      );
      final account = await repository(adapter).create('  worker01  ');
      expect(adapter.requests.map((r) => r.path), [
        '/api/auth/csrf',
        '/api/admin/accounts',
      ]);
      expect(adapter.requests.last.data, {'username': 'worker01'});
      expect(adapter.requests.last.headers['X-CSRF-Token'], 'csrf-1');
      expect(account.account.mustChangePassword, isTrue);
      expect(account.account.isAdmin, isFalse);
      expect(account.temporaryPassword, isNotEmpty);
    },
  );

  test(
    'status and temporary-password requests carry the current version',
    () async {
      var tokens = 0;
      final adapter = AccountsAdapter((request) {
        if (request.path == '/api/auth/csrf') {
          return body({'token': 'csrf-${++tokens}'});
        }
        return request.path.endsWith('/status')
            ? body(accountJson(2, active: false))
            : body(credentialsJson());
      });
      final accounts = repository(adapter),
          row = AdminAccount.fromJson(accountJson(2));
      await accounts.setActive(row, false);
      await accounts.newTemporaryPassword(row);
      final writes = adapter.requests.where((r) => r.method == 'POST').toList();
      expect(writes[0].data, {'isActive': false, 'version': row.version});
      expect(writes[1].data, {'version': row.version});
      expect(writes.map((r) => r.headers['X-CSRF-Token']), [
        'csrf-1',
        'csrf-2',
      ]);
    },
  );

  for (final error in [
    'username_exists',
    'account_conflict',
    'initial_password_completed',
  ]) {
    test(
      'keeps account error $error instead of treating it as logout',
      () async {
        final adapter = AccountsAdapter(
          (request) => request.path == '/api/auth/csrf'
              ? body({'token': 'csrf'})
              : body({'code': error}, status: 409),
        );
        await expectLater(
          repository(adapter).create('worker01'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', error)),
        );
      },
    );
  }

  test(
    'lists account status, roles and pagination without a CSRF request',
    () async {
      final adapter = AccountsAdapter(
        (_) => body({
          'page': 2,
          'pageSize': 12,
          'total': 13,
          'items': [accountJson(2)],
        }),
      );
      final result = await repository(adapter).list(page: 2);
      expect(adapter.requests.single.path, '/api/admin/accounts');
      expect(adapter.requests.single.queryParameters, {
        'page': 2,
        'pageSize': 12,
      });
      expect(result.hasPrevious, isTrue);
      expect(result.hasNext, isFalse);
      expect(result.items.single.mustChangePassword, isTrue);
    },
  );

  test('rejects a malformed credentials response', () async {
    final adapter = AccountsAdapter(
      (request) => request.path == '/api/auth/csrf'
          ? body({'token': 'csrf'})
          : body({'account': accountJson(2)}, status: 201),
    );
    await expectLater(
      repository(adapter).create('worker01'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'service_unavailable',
        ),
      ),
    );
  });
}
