import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';

import 'native_tls_context.dart';

Dio createDio(BaseOptions options) {
  final context = createApiSecurityContext(
    apiUri: Uri.parse(options.baseUrl),
    isDebug: kDebugMode,
    developmentCertificateBase64: const String.fromEnvironment(
      'DEV_HTTPS_CERT_BASE64',
    ),
  );

  final dio = Dio(options)
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient(context: context),
    );
  dio.interceptors.add(CookieManager(CookieJar()));
  return dio;
}
