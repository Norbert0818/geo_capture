import 'dart:typed_data';

import 'pole_code.dart';
import 'work_models.dart';

class SerialCandidate {
  const SerialCandidate({
    required this.serial,
    required this.source,
    required this.raw,
    required this.score,
    this.ntet = '',
    this.correctedCharacters = false,
  });
  final String serial, source, raw, ntet;
  final int score;
  final bool correctedCharacters;
  bool get reliable => score >= 80;
}

class SerialReading {
  const SerialReading({
    this.candidates = const [],
    this.supported = true,
    this.failed = false,
  });
  final List<SerialCandidate> candidates;
  final bool supported, failed;
  SerialCandidate? get preferred =>
      candidates.isEmpty || !candidates.first.reliable
          ? null
          : candidates.first;
  bool get conflicting =>
      candidates.where((x) => x.reliable).map((x) => x.serial).toSet().length >
          1;
}

abstract interface class SerialPhotoReader {
  Future<SerialReading> read(Uint8List original);
}

class SerialCandidates {
  static final label = RegExp(
    r'(?:\b(?:(?:nr|no|n)[.°º]?\s*)?seri[ae](?:l(?:\s*(?:number|no|nr))?)?\b|\bs\s*[/\\ ]\s*n\b)\s*[:=#.-]?\s*',
    caseSensitive: false,
  );
  static String fold(String text) =>
      text.replaceAll('é', 'e').replaceAll('É', 'E');
  static bool containsLabel(String line) => label.hasMatch(fold(line));
  static String? _digits(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[OoQq]'), '0')
        .replaceAll(RegExp(r'[IiLl|]'), '1')
        .replaceAll(RegExp(r'[Ss]'), '5')
        .replaceAll(RegExp(r'[Bb]'), '8')
        .replaceAll(RegExp(r'[Zz]'), '2')
        .replaceAll(RegExp(r'\s+'), '');
    return PoleIdentity.numericSerial.hasMatch(normalized) ? normalized : null;
  }

  static List<SerialCandidate> extract({
    Iterable<String> qr = const [],
    Iterable<String> text = const [],
  }) {
    final result = <SerialCandidate>[];
    void add(SerialCandidate candidate) {
      if (!PoleIdentity.numericSerial.hasMatch(candidate.serial)) return;
      final index = result.indexWhere((x) => x.serial == candidate.serial);
      if (index < 0) {
        result.add(candidate);
      } else if (candidate.score > result[index].score ||
          result[index].ntet.isEmpty && candidate.ntet.isNotEmpty) {
        result[index] = candidate;
      }
    }

    for (final raw in qr) {
      try {
        final pole = PoleCode.read(raw);
        if (PoleIdentity.numericSerial.hasMatch(pole.serialNumber)) {
          add(
            SerialCandidate(
              serial: pole.serialNumber,
              ntet: pole.ntetCode,
              source: 'scanned',
              raw: raw,
              score: 110,
            ),
          );
        }
      } catch (_) {
        /* A manufacturer QR can contain unrelated content. */
      }
    }
    for (final passage in text) {
      final lines = passage
          .split(RegExp(r'[\r\n]+'))
          .map((x) => x.trim())
          .where((x) => x.isNotEmpty)
          .toList();
      for (var index = 0; index < lines.length; index++) {
        final line = fold(lines[index]);
        final marker = label.firstMatch(line);
        if (marker != null) {
          var tail = line.substring(marker.end).trim();
          if (tail.isEmpty && index + 1 < lines.length) tail = lines[index + 1];
          final span = RegExp(
            r'^([0-9OoQqIiLl|SsBbZz]+(?:[ \t]+[0-9OoQqIiLl|SsBbZz]+)*)(?![A-Za-z0-9])',
          ).firstMatch(tail)?.group(1);
          if (span == null) continue;
          final tokens = span.split(RegExp(r'\s+'));
          final first = _digits(tokens.first);
          if (first == null) continue;
          final corrected = RegExp(r'[A-Za-z|]').hasMatch(span);
          // Never turn a word such as "illegible" into a number.
          if (corrected && !RegExp(r'[0-9]').hasMatch(span)) continue;
          final raw =
              lines[index] +
                  (tail == line.substring(marker.end).trim() ? '' : '\n$tail');
          add(
            SerialCandidate(
              serial: first,
              source: 'ocr',
              raw: raw,
              score: corrected ? 85 : 100,
              correctedCharacters: corrected,
            ),
          );
          if (tokens.length > 1 &&
              tokens.every((x) => x.length <= 4) &&
              !RegExp(r'^(19|20|21)[0-9]{2}$').hasMatch(tokens.last)) {
            final joined = _digits(span);
            if (joined != null) {
              add(
                SerialCandidate(
                  serial: joined,
                  source: 'ocr',
                  raw: raw,
                  score: corrected ? 86 : 101,
                  correctedCharacters: corrected,
                ),
              );
            }
          }
        } else if (RegExp(r'^[0-9]{4,32}$').hasMatch(line) &&
            !RegExp(r'^(19|20|21)[0-9]{2}$').hasMatch(line) &&
            (index == 0 ||
                !RegExp(
                  r'tel|telefon|deranj|date|data',
                  caseSensitive: false,
                ).hasMatch(lines[index - 1]))) {
          add(
            SerialCandidate(
              serial: line,
              source: 'ocr',
              raw: lines[index],
              score: 30,
            ),
          );
        }
      }
    }
    result.sort((a, b) => b.score.compareTo(a.score));
    return result.take(6).toList();
  }
}