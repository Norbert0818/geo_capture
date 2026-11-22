import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_transport.dart'
    if (dart.library.io) 'api_transport_io.dart'
    if (dart.library.js_interop) 'api_transport_web.dart'
    as transport;

class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  @override
  String toString() => 'ApiException($code)';
}

class ApiClient {
  ApiClient(String baseUrl)
    : _dio = transport.createDio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          contentType: Headers.jsonContentType,
          headers: const {'Accept': 'application/json'},
        ),
      );

  ApiClient.fromDio(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
      );
      return _readObject(response);
    } on DioException catch (error) {
      throw _mapError(error, path);
    }
  }

  Future<Uint8List> getImage(String path, {CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Accept': 'image/jpeg, image/png'},
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final bytes = response.data;
      final mime = response.headers
          .value(Headers.contentTypeHeader)
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (bytes == null ||
          bytes.isEmpty ||
          (mime != 'image/jpeg' && mime != 'image/png')) {
        throw const ApiException('service_unavailable');
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (error) {
      throw _mapError(error, path);
    }
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final csrf = await get('/api/auth/csrf');
    final token = csrf['token'];

    if (token is! String || token.isEmpty) {
      throw const ApiException('service_unavailable');
    }

    try {
      final response = await _dio.post<dynamic>(
        path,
        data: body,
        options: Options(headers: {'X-CSRF-Token': token}),
      );

      return _readObject(response);
    } on DioException catch (error) {
      throw _mapError(error, path);
    }
  }

  Future<Map<String, dynamic>> postMultipart(
    String path,
    FormData body, {
    ProgressCallback? onSendProgress,
  }) async {
    final csrf = await get('/api/auth/csrf');
    final token = csrf['token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException('service_unavailable');
    }

    try {
      final response = await _dio.post<dynamic>(
        path,
        data: body,
        options: Options(
          contentType: Headers.multipartFormDataContentType,
          headers: {'X-CSRF-Token': token},
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(seconds: 90),
        ),
        onSendProgress: onSendProgress,
      );
      return _readObject(response);
    } on DioException catch (error) {
      throw _mapError(error, path);
    }
  }

  Map<String, dynamic> _readObject(Response<dynamic> response) {
    if (response.statusCode == 204) {
      return {};
    }

    final data = response.data;

    if (data is Map<String, dynamic>) {
      return data;
    }

    throw const ApiException('service_unavailable');
  }

  ApiException _mapError(DioException error, String path) {
    final status = error.response?.statusCode;
    final data = error.response?.data;

    if (error.type == DioExceptionType.cancel) {
      return const ApiException('request_cancelled');
    }

    if (status == 404) {
      return ApiException('not_found', statusCode: status);
    }

    if (status == 401) {
      return ApiException(
        path == '/api/auth/login' ? 'invalid_credentials' : 'session_expired',
        statusCode: status,
      );
    }

    if (status == 429) {
      return ApiException('too_many_attempts', statusCode: status);
    }

    if (status == 403) {
      return ApiException('forbidden', statusCode: status);
    }

    if (status == 413) {
      return ApiException('upload_too_large', statusCode: status);
    }

    const uploadErrors = {
      'invalid_upload_form',
      'invalid_manifest',
      'invalid_serial_number',
      'duplicate_photo_id',
      'duplicate_photo_file',
      'invalid_photo',
      'invalid_photo_dimensions',
      'invalid_location',
      'invalid_photo_time',
      'photo_pair_required',
      'stamped_jpeg_required',
      'upload_too_large',
      'multipart_required',
      'upload_id_conflict',
      'invalid_username',
      'username_exists',
      'account_conflict',
      'account_protected',
      'initial_password_completed',
    };
    if ({400, 409, 415}.contains(status) &&
        data is Map &&
        uploadErrors.contains(data['code'])) {
      return ApiException(data['code'] as String, statusCode: status);
    }

    if (status == 400 && data is Map) {
      final code = data['code'];
      final rawDetails = data['details'];
      final details = rawDetails is List
          ? rawDetails.whereType<String>().toList()
          : <String>[];

      if (code == 'password_change_failed') {
        return ApiException(
          details.contains('PasswordMismatch')
              ? 'wrong_current_password'
              : details.contains('ConcurrencyFailure')
              ? 'session_expired'
              : 'password_rules',
          statusCode: status,
        );
      }

      if (code == 'password_unchanged' ||
          code == 'csrf_invalid' ||
          code == 'invalid_input') {
        return ApiException(code as String, statusCode: status);
      }
    }

    if (status == 409) {
      return ApiException('session_expired', statusCode: status);
    }

    return ApiException('service_unavailable', statusCode: status);
  }

  void close() {
    _dio.close(force: true);
  }
}
