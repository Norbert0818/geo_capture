import 'package:flutter_test/flutter_test.dart';
import 'package:geo_capture/features/field_work/serial_reading.dart';

void main() {
  for (final label in [
    'N°Serie:',
    'NºSerie:',
    'Nr. serie:',
    'Serie:',
    'Serial number:',
    'S/N:',
    'S N:',
    'N°Série:',
  ]) {
    test('reads $label with leading zeros', () {
      final result = SerialCandidates.extract(text: ['$label 0002610586']);
      expect(result.first.serial, '0002610586');
      expect(result.first.reliable, isTrue);
    });
  }
  test('reads the photographed manufacturer label without selecting telephone or year', () {
    final result = SerialCandidates.extract(
      text: [
        'DERANJAMENTE:\nTEL. 0374443275\nORANGE ROMANIA\nCOMPOSITE TIP R0\n7 m - 2026\nNTET Cd: T0PL0138RO\nN°Serie: 2610586',
      ],
    );
    expect(result.map((x) => x.serial), ['2610586']);
  });
  test(
    'joins split digits cautiously and exposes ambiguity instead of guessing',
        () {
      final reading = SerialReading(
        candidates: SerialCandidates.extract(text: ['Serie: 261 0586']),
      );
      expect(
        reading.candidates.map((x) => x.serial),
        containsAll(['2610586', '261']),
      );
      expect(reading.conflicting, isTrue);
    },
  );
  test('contextual OCR substitutions are marked for human review', () {
    final result = SerialCandidates.extract(text: ['N°Serie: 26I0S86']);
    expect(result.first.serial, '2610586');
    expect(result.first.correctedCharacters, isTrue);
  });
  test('recognizes a number on the line below the serial heading', () {
    expect(
      SerialCandidates.extract(text: ['N°Serie:\n0000012']).first.serial,
      '0000012',
    );
  });
  test('weak bare digits are offered but never preferred', () {
    final reading = SerialReading(
      candidates: SerialCandidates.extract(text: ['2610586']),
    );
    expect(reading.preferred, isNull);
    expect(reading.candidates.single.serial, '2610586');
  });
  for (final content in [
    '2026',
    'TEL\n0374443275',
    'Date\n20261127',
    'NTET Cd: T0PL0138RO',
    'Serial number: illegible',
    'Serial number: OOPS',
    'GPS 46.777987 24.309925',
  ]) {
    test(
      'does not invent a serial from $content',
          () => expect(SerialCandidates.extract(text: [content]), isEmpty),
    );
  }
  test(
    'QR has priority and fills NTET, but conflicting OCR still needs a choice',
        () {
      final reading = SerialReading(
        candidates: SerialCandidates.extract(
          qr: ['NTET Cd: T0PL0138RO; S/N: 00012'],
          text: ['Serie: 00013'],
        ),
      );
      expect(reading.preferred!.serial, '00012');
      expect(reading.preferred!.ntet, 'T0PL0138RO');
      expect(reading.preferred!.source, 'scanned');
      expect(reading.conflicting, isTrue);
    },
  );
  test('same QR and OCR are deduplicated without losing NTET', () {
    final candidates = SerialCandidates.extract(
      qr: ['NTET Cd: T0PL0138RO; S/N: 00012'],
      text: ['Serie: 00012', 'Serie: 00012'],
    );
    expect(candidates, hasLength(1));
    expect(candidates.single.ntet, 'T0PL0138RO');
  });
  test('invalid and unrelated QR values cannot become serials', () {
    expect(
      SerialCandidates.extract(
        qr: ['https://example.test', 'SN: A123', '{"type":"other"}'],
      ),
      isEmpty,
    );
  });
  test(
    'one-digit serials remain supported without a fixed manufacturer length',
        () {
      expect(SerialCandidates.extract(text: ['Serie: 7']).single.serial, '7');
    },
  );
}