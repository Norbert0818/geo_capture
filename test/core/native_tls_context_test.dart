import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/core/api/native_tls_context.dart';

import 'tls_fixture.dart';

String get encodedCertificate => base64Encode(utf8.encode(testCertificatePem));

Future<HttpServer> localHttpsServer() async {
  final context = SecurityContext()
    ..useCertificateChainBytes(utf8.encode(testCertificatePem))
    ..usePrivateKeyBytes(utf8.encode(testPrivateKeyPem));
  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  server.listen((request) {
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"status":"ok"}');
    request.response.close();
  }, onError: (Object error) {});
  addTearDown(() => server.close(force: true));
  return server;
}

HttpClient localClient(SecurityContext? context) {
  final client = HttpClient(context: context)
    ..connectionTimeout = const Duration(seconds: 3)
    ..findProxy = (_) => 'DIRECT';
  addTearDown(() => client.close(force: true));
  return client;
}

Future<String> readHealth(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  final response = await request.close();
  return response.transform(utf8.decoder).join();
}

void main() {
  test('normal builds retain the standard platform trust store', () {
    expect(
      createApiSecurityContext(
        apiUri: Uri.parse('https://api.example.test'),
        isDebug: false,
      ),
      isNull,
    );
  });

  test('debug client connects to the trusted local HTTPS server', () async {
    final server = await localHttpsServer();
    final uri = Uri.parse('https://localhost:${server.port}');
    final context = createApiSecurityContext(
      apiUri: uri,
      isDebug: true,
      developmentCertificateBase64: encodedCertificate,
    );
    expect(
      await readHealth(localClient(context), uri.resolve('/health')),
      '{"status":"ok"}',
    );
  });

  test(
    'untrusted local HTTPS is rejected without an explicit certificate',
    () async {
      final server = await localHttpsServer();
      final uri = Uri.parse('https://localhost:${server.port}/health');
      await expectLater(
        readHealth(localClient(null), uri),
        throwsA(isA<HandshakeException>()),
      );
    },
  );

  test('trusting the certificate still requires a matching hostname', () async {
    final server = await localHttpsServer();
    final context = createApiSecurityContext(
      apiUri: Uri.parse('https://localhost:${server.port}'),
      isDebug: true,
      developmentCertificateBase64: encodedCertificate,
    );
    await expectLater(
      readHealth(
        localClient(context),
        Uri.parse('https://127.0.0.1:${server.port}/health'),
      ),
      throwsA(isA<HandshakeException>()),
    );
  });

  test(
    'debug trust does not change the process-wide default trust store',
    () async {
      final server = await localHttpsServer();
      final uri = Uri.parse('https://localhost:${server.port}/health');
      final context = createApiSecurityContext(
        apiUri: uri.replace(path: ''),
        isDebug: true,
        developmentCertificateBase64: encodedCertificate,
      );
      expect(await readHealth(localClient(context), uri), '{"status":"ok"}');
      await expectLater(
        readHealth(localClient(null), uri),
        throwsA(isA<HandshakeException>()),
      );
    },
  );

  test('profile and release builds reject development certificate defines', () {
    expect(
      () => createApiSecurityContext(
        apiUri: Uri.parse('https://localhost:7043'),
        isDebug: false,
        developmentCertificateBase64: encodedCertificate,
      ),
      throwsStateError,
    );
  });

  for (final url in [
    'http://localhost:7043',
    'https://api.example.test',
    'https://127.0.0.1:7043',
    'https://name@localhost:7043',
    'https://localhost:7043/api',
    'https://localhost:7043/?query=1',
    'https://localhost:7043/#fragment',
  ]) {
    test('development trust rejects the API setting $url', () {
      expect(
        () => createApiSecurityContext(
          apiUri: Uri.parse(url),
          isDebug: true,
          developmentCertificateBase64: encodedCertificate,
        ),
        throwsStateError,
      );
    });
  }

  final invalidCertificates = <String, String>{
    'invalid base64': '%%%not-base64%%%',
    'non-certificate text': base64Encode(utf8.encode('hello')),
    'invalid certificate data': base64Encode(
      utf8.encode(
        '-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n',
      ),
    ),
    'private key': base64Encode(utf8.encode(testPrivateKeyPem)),
  };
  for (final entry in invalidCertificates.entries) {
    test('invalid development configuration fails closed: ${entry.key}', () {
      expect(
        () => createApiSecurityContext(
          apiUri: Uri.parse('https://localhost:7043'),
          isDebug: true,
          developmentCertificateBase64: entry.value,
        ),
        throwsStateError,
      );
    });
  }
}
