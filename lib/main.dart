import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'features/auth/auth_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final baseUrl = kIsWeb
      ? Uri.base.origin
      : const String.fromEnvironment('API_BASE_URL');

  final uri = Uri.tryParse(baseUrl);

  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw StateError(
      'Web: open the app from https://localhost:7043. '
      'Native: set --dart-define=API_BASE_URL=https://YOUR_API_HOST.',
    );
  }

  runApp(GeoCaptureApp(authRepository: HttpAuthRepository(ApiClient(baseUrl))));
}
