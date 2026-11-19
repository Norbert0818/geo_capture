import '../../core/api/api_client.dart';
import '../../core/models/session_user.dart';

abstract interface class AuthRepository {
  Future<SessionUser?> restoreSession();

  Future<SessionUser> signIn(String username, String password);

  Future<SessionUser> changePassword(String newPassword);

  Future<void> signOut();

  void dispose();
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._api);

  final ApiClient _api;

  @override
  Future<SessionUser?> restoreSession() async {
    try {
      return _readUser(await _api.get('/api/auth/me'));
    } on ApiException catch (error) {
      if (error.code == 'session_expired') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<SessionUser> signIn(String username, String password) async {
    return _readUser(await _api.post('/api/auth/login', {
      'username': username.trim(),
      'password': password,
    }));
  }

  @override
  Future<SessionUser> changePassword(String newPassword) async {
    return _readUser(await _api.post('/api/auth/initial-password', {
      'newPassword': newPassword,
    }));
  }

  @override
  Future<void> signOut() async {
    await _api.post('/api/auth/logout', {});
  }

  SessionUser _readUser(Map<String, dynamic> json) {
    try {
      return SessionUser.fromJson(json);
    } on FormatException {
      throw const ApiException('service_unavailable');
    }
  }

  @override
  void dispose() {
    _api.close();
  }
}