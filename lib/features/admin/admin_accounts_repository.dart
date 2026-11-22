import '../../core/api/api_client.dart';

class AdminAccount {
  AdminAccount({
    required this.id,
    required this.username,
    required this.isActive,
    required this.mustChangePassword,
    required this.createdAtUtc,
    required this.version,
    required List<String> roles,
  }) : roles = List.unmodifiable(roles);

  final String id;
  final String username;
  final bool isActive;
  final bool mustChangePassword;
  final DateTime createdAtUtc;
  final String version;
  final List<String> roles;
  bool get isAdmin => roles.contains('Admin');

  factory AdminAccount.fromJson(Map<String, dynamic> json) {
    final id = json['id'],
        username = json['username'],
        active = json['isActive'];
    final pending = json['mustChangePassword'], created = json['createdAtUtc'];
    final version = json['version'], roles = json['roles'];
    if (id is! String ||
        id.isEmpty ||
        username is! String ||
        username.isEmpty ||
        active is! bool ||
        pending is! bool ||
        created is! String ||
        version is! String ||
        version.isEmpty ||
        roles is! List ||
        roles.any((r) => r is! String)) {
      throw const FormatException();
    }
    return AdminAccount(
      id: id,
      username: username,
      isActive: active,
      mustChangePassword: pending,
      createdAtUtc: DateTime.parse(created).toUtc(),
      version: version,
      roles: roles.cast<String>(),
    );
  }
}

class AdminAccountsResult {
  AdminAccountsResult({
    required this.page,
    required this.pageSize,
    required this.total,
    required List<AdminAccount> items,
  }) : items = List.unmodifiable(items);

  final int page, pageSize, total;
  final List<AdminAccount> items;
  bool get hasPrevious => page > 1;
  bool get hasNext => page * pageSize < total;
  int get pages => total == 0 ? 1 : (total / pageSize).ceil();

  factory AdminAccountsResult.fromJson(Map<String, dynamic> json) {
    final page = json['page'],
        size = json['pageSize'],
        total = json['total'],
        rows = json['items'];
    if (page is! int ||
        page < 1 ||
        size is! int ||
        size < 1 ||
        total is! int ||
        total < 0 ||
        rows is! List) {
      throw const FormatException();
    }
    return AdminAccountsResult(
      page: page,
      pageSize: size,
      total: total,
      items: rows.map((row) {
        if (row is! Map<String, dynamic>) throw const FormatException();
        return AdminAccount.fromJson(row);
      }).toList(),
    );
  }
}

class AccountCredentials {
  const AccountCredentials(this.account, this.temporaryPassword);
  final AdminAccount account;
  final String temporaryPassword;

  factory AccountCredentials.fromJson(Map<String, dynamic> json) {
    final account = json['account'], password = json['temporaryPassword'];
    if (account is! Map<String, dynamic> ||
        password is! String ||
        password.isEmpty) {
      throw const FormatException();
    }
    return AccountCredentials(AdminAccount.fromJson(account), password);
  }
}

abstract interface class AdminAccountsRepository {
  Future<AdminAccountsResult> list({int page = 1});
  Future<AccountCredentials> create(String username);
  Future<AdminAccount> setActive(AdminAccount account, bool active);
  Future<AccountCredentials> newTemporaryPassword(AdminAccount account);
}

class HttpAdminAccountsRepository implements AdminAccountsRepository {
  HttpAdminAccountsRepository(this._api);
  final ApiClient _api;

  Future<T> _read<T>(
    Future<Map<String, dynamic>> call,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final json = await call;
    try {
      return parse(json);
    } on FormatException {
      throw const ApiException('service_unavailable');
    }
  }

  @override
  Future<AdminAccountsResult> list({int page = 1}) => _read(
    _api.get(
      '/api/admin/accounts',
      queryParameters: {'page': page, 'pageSize': 12},
    ),
    AdminAccountsResult.fromJson,
  );
  @override
  Future<AccountCredentials> create(String username) => _read(
    _api.post('/api/admin/accounts', {'username': username.trim()}),
    AccountCredentials.fromJson,
  );
  @override
  Future<AdminAccount> setActive(AdminAccount account, bool active) => _read(
    _api.post('/api/admin/accounts/${Uri.encodeComponent(account.id)}/status', {
      'isActive': active,
      'version': account.version,
    }),
    AdminAccount.fromJson,
  );
  @override
  Future<AccountCredentials> newTemporaryPassword(
    AdminAccount account,
  ) => _read(
    _api.post(
      '/api/admin/accounts/${Uri.encodeComponent(account.id)}/temporary-password',
      {'version': account.version},
    ),
    AccountCredentials.fromJson,
  );
}
