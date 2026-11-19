class SessionUser {
  SessionUser({
    required this.id,
    required this.username,
    required this.mustChangePassword,
    required List<String> roles,
  }) : roles = List.unmodifiable(roles);

  final String id;
  final String username;
  final bool mustChangePassword;
  final List<String> roles;

  bool get isAdmin => roles.contains('Admin');

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final username = json['username'];
    final mustChangePassword = json['mustChangePassword'];
    final roles = json['roles'];

    if (id is! String ||
        id.isEmpty ||
        username is! String ||
        username.isEmpty ||
        mustChangePassword is! bool ||
        roles is! List ||
        roles.any((role) => role is! String)) {
      throw const FormatException('Invalid user response.');
    }

    return SessionUser(
      id: id,
      username: username,
      mustChangePassword: mustChangePassword,
      roles: roles.cast<String>(),
    );
  }
}
