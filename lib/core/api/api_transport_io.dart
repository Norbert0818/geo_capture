import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

Dio createDio(BaseOptions options) {
  final dio = Dio(options);
  dio.interceptors.add(CookieManager(CookieJar()));
  return dio;
}
