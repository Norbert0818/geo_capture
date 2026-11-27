import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RomaniaCounty {
  const RomaniaCounty(this.code, this.name);
  final String code, name;
}

class RomaniaPlace {
  const RomaniaPlace({
    required this.countyCode,
    required this.county,
    required this.name,
    this.code,
    this.unit = '',
  });
  final String countyCode, county, name, unit;
  final String? code;
  String get label =>
      unit.isEmpty ? '$name, $county' : '$name · $unit, $county';
}

class RomaniaPlaces {
  RomaniaPlaces.fromJson(Map<String, dynamic> data) {
    if (data['format'] != 'geocapture.romania-places' || data['version'] != 1) {
      throw const FormatException('Invalid Romania locality catalogue');
    }
    for (final value in data['counties'] as List) {
      final county = RomaniaCounty(
        value['code'] as String,
        value['name'] as String,
      );
      if (_counties.containsKey(county.code)) {
        throw const FormatException('Duplicate county');
      }
      _counties[county.code] = county;
    }
    for (final value in data['localities'] as List) {
      final county = _counties[value['countyCode']];
      final code = value['code'] as String;
      if (county == null || _places.containsKey(code)) {
        throw const FormatException('Invalid locality');
      }
      _places[code] = RomaniaPlace(
        countyCode: county.code,
        county: county.name,
        code: code,
        name: value['name'] as String,
        unit: value['unit'] as String,
      );
    }
    final names = <String, String>{};
    for (final place in _places.values) {
      names[place.code!] = fold(place.name);
      _search[place.code!] = fold(
        '${place.name} ${place.unit} ${place.county}',
      );
    }
    _ordered = _places.values.toList()
      ..sort((a, b) {
        final name = names[a.code!]!.compareTo(names[b.code!]!);
        return name != 0 ? name : a.label.compareTo(b.label);
      });
    for (final place in _ordered) {
      _byCounty.putIfAbsent(place.countyCode, () => []).add(place);
    }
  }
  final _counties = <String, RomaniaCounty>{};
  final _places = <String, RomaniaPlace>{};
  late final List<RomaniaPlace> _ordered;
  final _search = <String, String>{};
  final _byCounty = <String, List<RomaniaPlace>>{};
  static Future<RomaniaPlaces>? _loaded;
  static Future<RomaniaPlaces> load() => _loaded ??= rootBundle
      .loadString('assets/data/romania_places.json')
      .then((text) => compute(_decodeRomaniaPlaces, text));
  List<RomaniaCounty> get counties =>
      _counties.values.toList()
        ..sort((a, b) => fold(a.name).compareTo(fold(b.name)));
  RomaniaCounty? county(String? code) => _counties[code];
  RomaniaPlace? place(String? code) => _places[code];
  int get localityCount => _places.length;

  static String fold(String value) {
    var result = value.toLowerCase();
    const source = 'ăâîșşțţáéíóöőúüű';
    const target = 'aaissttaeiooouuu';
    for (var i = 0; i < source.length; i++) {
      result = result.replaceAll(source[i], target[i]);
    }
    result = result.replaceAll(RegExp('[\u0300-\u036f]'), '');
    result = result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return result.replaceAll(RegExp(r'\b(?:tirgu|tg)\b'), 'targu');
  }

  List<RomaniaPlace> search(
      String query, {
        String? countyCode,
        int limit = 100,
      }) {
    final terms = fold(query).split(' ').where((x) => x.isNotEmpty).toList();
    final matches =
    (countyCode == null
        ? _ordered
        : _byCounty[countyCode] ?? <RomaniaPlace>[])
        .where(
          (place) =>
          terms.every((term) => _search[place.code!]!.contains(term)),
    );
    return matches.take(limit < 0 ? 0 : limit).toList();
  }

  RomaniaPlace? match(String locality, String countyName) {
    String countyKey(String value) =>
        fold(value)
            .replaceAll(RegExp(r'\b(?:judetul|judet|county|municipiul)\b'), '')
            .trim();
    final counties = _counties.values.where(
          (x) => countyKey(x.name) == countyKey(countyName),
    );
    if (counties.length != 1) return null;
    final name = fold(locality)
        .replaceAll(RegExp(r'\b(?:municipiul|orasul|comuna|satul)\b'), '')
        .trim();
    final places = _places.values
        .where(
          (x) => x.countyCode == counties.single.code && fold(x.name) == name,
    )
        .toList();
    return places.length == 1 ? places.single : null;
  }
}

RomaniaPlaces _decodeRomaniaPlaces(String text) =>
    RomaniaPlaces.fromJson(jsonDecode(text) as Map<String, dynamic>);