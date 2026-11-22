import 'package:geo_capture/core/api/api_client.dart';
import 'package:geo_capture/core/models/session_user.dart';
import 'package:geo_capture/features/admin/admin_accounts_repository.dart';
import 'package:geo_capture/features/auth/auth_repository.dart';

String accountId(int n) =>
    '88888888-8888-4888-8888-${n.toString().padLeft(12, '0')}';

Map<String, dynamic> accountJson(
  int n, {
  String? username,
  bool admin = false,
  bool active = true,
  bool pending = true,
  String? version,
}) => {
  'id': accountId(n),
  'username': username ?? (admin ? 'admin01' : 'worker0$n'),
  'isActive': active,
  'mustChangePassword': pending,
  'createdAtUtc': '2026-11-21T12:00:00Z',
  'version': version ?? 'version-$n',
  'roles': [admin ? 'Admin' : 'User'],
};

Map<String, dynamic> credentialsJson({String username = 'new-worker'}) => {
  'account': accountJson(5, username: username),
  'temporaryPassword': 'Gc9!GeneratedTestPassword1234',
};

class FakeAccountsRepository implements AdminAccountsRepository {
  final rows = <AdminAccount>[
    AdminAccount.fromJson(accountJson(1, admin: true, pending: false)),
    AdminAccount.fromJson(accountJson(2)),
    AdminAccount.fromJson(accountJson(3, pending: false)),
  ];
  final pages = <int>[];
  final created = <String>[];
  final statuses = <({String id, bool active, String version})>[];
  final temporary = <String>[];
  int revision = 10;
  Future<AccountCredentials> Function(String name)? onCreate;
  ApiException? statusFailure;

  @override
  Future<AdminAccountsResult> list({int page = 1}) async {
    pages.add(page);
    return AdminAccountsResult(
      page: page,
      pageSize: 12,
      total: rows.length,
      items: rows,
    );
  }

  @override
  Future<AccountCredentials> create(String username) async {
    created.add(username);
    if (onCreate != null) return onCreate!(username);
    final result = AccountCredentials.fromJson(
      credentialsJson(username: username),
    );
    rows.add(result.account);
    return result;
  }

  @override
  Future<AdminAccount> setActive(AdminAccount account, bool active) async {
    statuses.add((id: account.id, active: active, version: account.version));
    if (statusFailure != null) throw statusFailure!;
    final next = AdminAccount(
      id: account.id,
      username: account.username,
      isActive: active,
      mustChangePassword: account.mustChangePassword,
      createdAtUtc: account.createdAtUtc,
      version: 'version-${revision++}',
      roles: account.roles,
    );
    rows[rows.indexWhere((row) => row.id == account.id)] = next;
    return next;
  }

  @override
  Future<AccountCredentials> newTemporaryPassword(AdminAccount account) async {
    temporary.add(account.id);
    return AccountCredentials(account, 'Gc9!ReplacementTestPassword1234');
  }
}

class AccountsTestAuth implements AuthRepository {
  AccountsTestAuth({this.admin = true});
  final bool admin;
  SessionUser get user => SessionUser(
    id: accountId(1),
    username: 'admin01',
    mustChangePassword: false,
    roles: [admin ? 'Admin' : 'User'],
  );
  @override
  Future<SessionUser?> restoreSession() async => user;
  @override
  Future<SessionUser> signIn(String username, String password) async => user;
  @override
  Future<SessionUser> changePassword(String password) async => user;
  @override
  Future<void> signOut() async {}
  @override
  void dispose() {}
}
