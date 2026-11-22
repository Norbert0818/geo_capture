import 'dart:convert';
import 'dart:io';

/// Adds one local development certificate without disabling TLS validation.
SecurityContext? createApiSecurityContext({
  required Uri apiUri,
  required bool isDebug,
  String developmentCertificateBase64 = '',
}) {
  if (developmentCertificateBase64.isEmpty) return null;

  if (!isDebug) {
    throw StateError(
      'DEV_HTTPS_CERT_BASE64 is allowed only in a debug build. '
      'Use a publicly trusted HTTPS API for profile and release builds.',
    );
  }

  if (apiUri.scheme != 'https' ||
      apiUri.host != 'localhost' ||
      apiUri.userInfo.isNotEmpty ||
      (apiUri.path.isNotEmpty && apiUri.path != '/') ||
      apiUri.hasQuery ||
      apiUri.hasFragment) {
    throw StateError(
      'The development certificate can be used only with an '
      'https://localhost API origin.',
    );
  }

  try {
    final bytes = base64Decode(developmentCertificateBase64);
    final pem = utf8.decode(bytes);
    final publicCertificate = RegExp(
      r'^\s*-----BEGIN CERTIFICATE-----\s+'
      r'[A-Za-z0-9+/=\s]+'
      r'-----END CERTIFICATE-----\s*$',
    );
    if (!publicCertificate.hasMatch(pem)) {
      throw const FormatException('Expected one public PEM certificate.');
    }

    return SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(bytes);
  } on FormatException {
    throw StateError(
      'Invalid DEV_HTTPS_CERT_BASE64. Run GeoCapture_Android.bat again.',
    );
  } on TlsException {
    throw StateError(
      'The development certificate could not be loaded. '
      'Run GeoCapture_Android.bat again.',
    );
  }
}
