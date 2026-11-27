import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/field_work/serial_reader_native.dart';

import 'work_flow_test.dart' show reviewPng;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ocr = MethodChannel('google_mlkit_text_recognizer');
  const barcode = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporary;
  final calls = <MethodCall>[];
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('geocapture-ocr-test-');
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(barcode, (_) async => null);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(ocr, null);
    messenger.setMockMethodCallHandler(barcode, null);
    debugDefaultTargetPlatformOverride = null;
    await temporary.delete(recursive: true);
  });
  Map<String, Object> recognized(String text, {bool marker = false}) {
    final rect = {'left': 1.0, 'top': 1.0, 'right': 12.0, 'bottom': 4.0};
    return {
      'text': text,
      'blocks': marker
          ? [
        {
          'text': text,
          'rect': rect,
          'recognizedLanguages': <String>[],
          'points': <Object>[],
          'lines': [
            {
              'text': text,
              'rect': rect,
              'recognizedLanguages': <String>[],
              'points': <Object>[],
              'elements': <Object>[],
              'confidence': .98,
              'angle': .0,
            },
          ],
        },
      ]
          : <Object>[],
    };
  }

  NativeSerialPhotoReader reader() => NativeSerialPhotoReader(
    supported: true,
    temporaryDirectory: () async => temporary,
  );

  test('native bridge reads a private copy, closes OCR and removes only its temporary directory', () async {
    final sentinel = File('${temporary.path}/keep.txt');
    await sentinel.writeAsString('keep');
    messenger.setMockMethodCallHandler(ocr, (call) async {
      calls.add(call);
      if (call.method == 'vision#closeTextRecognizer') return null;
      final arguments = call.arguments as Map;
      expect(arguments['script'], 0);
      final image = arguments['imageData'] as Map;
      expect(image['path'], startsWith(temporary.path));
      expect(await File(image['path'] as String).exists(), isTrue);
      return recognized('N°Serie: 0002610586');
    });
    final original = Uint8List.fromList(reviewPng);
    final result = await reader().read(original);
    expect(result.preferred!.serial, '0002610586');
    expect(original, reviewPng);
    expect(calls.last.method, 'vision#closeTextRecognizer');
    expect((await temporary.list().toList()).map((x) => x.path), [
      sentinel.path,
    ]);
  });
  test('crop failure retains the successful full-image OCR reading', () async {
    var passes = 0;
    messenger.setMockMethodCallHandler(ocr, (call) async {
      calls.add(call);
      if (call.method == 'vision#closeTextRecognizer') return null;
      if (++passes == 2) throw PlatformException(code: 'crop_failed');
      return recognized('Serie: 00012', marker: true);
    });
    final result = await reader().read(reviewPng);
    expect(passes, 2);
    expect(result.preferred!.serial, '00012');
    expect(result.failed, isFalse);
    expect(await temporary.list().toList(), isEmpty);
  });
  test('a decoded QR remains usable if OCR fails', () async {
    messenger.setMockMethodCallHandler(
      barcode,
          (call) async => call.method == 'analyzeImage'
          ? {
        'data': [
          {'rawValue': 'NTET Cd: T0PL0138RO; S/N: 00012', 'format': 256},
        ],
      }
          : null,
    );
    messenger.setMockMethodCallHandler(ocr, (call) async {
      if (call.method == 'vision#closeTextRecognizer') return null;
      throw PlatformException(code: 'recognizer_failed');
    });
    final result = await reader().read(reviewPng);
    expect(result.preferred!.serial, '00012');
    expect(result.preferred!.ntet, 'T0PL0138RO');
    expect(result.preferred!.source, 'scanned');
    expect(await temporary.list().toList(), isEmpty);
  });
  test(
    'invalid image cleans native resources and allows manual fallback',
        () async {
      messenger.setMockMethodCallHandler(ocr, (call) async {
        calls.add(call);
        return null;
      });
      final result = await reader().read(Uint8List.fromList([1, 2, 3]));
      expect(result.failed, isTrue);
      expect(calls.last.method, 'vision#closeTextRecognizer');
      expect(await temporary.list().toList(), isEmpty);
    },
  );
  test('unsupported platforms do not touch native channels or files', () async {
    final result = await NativeSerialPhotoReader(
      supported: false,
      temporaryDirectory: () => throw StateError('must not run'),
    ).read(reviewPng);
    expect(result.supported, isFalse);
    expect(calls, isEmpty);
  });
}