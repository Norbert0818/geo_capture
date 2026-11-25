import 'work_models.dart';

class WorkListFilters {
  const WorkListFilters({
    this.kind,
    this.serial = '',
    this.ntet = '',
    this.locality = '',
    this.county = '',
    this.owner = '',
    this.fromDate = '',
    this.toDate = '',
  });

  final WorkKind? kind;
  final String serial, ntet, locality, county, owner, fromDate, toDate;

  Map<String, String> toQueryParameters() => {
    if (kind != null) 'kind': kind!.name,
    for (final entry in {
      'serial': serial,
      'ntet': ntet,
      'locality': locality,
      'county': county,
      'owner': owner,
      'fromDate': fromDate,
      'toDate': toDate,
    }.entries)
      if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
  };

  bool get isEmpty => toQueryParameters().isEmpty;

  bool get validDates {
    bool valid(String value) {
      if (value.isEmpty) return true;
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
      final parsed = DateTime.tryParse(value);
      return parsed != null && date(parsed) == value;
    }

    return valid(fromDate) &&
        valid(toDate) &&
        (fromDate.isEmpty || toDate.isEmpty || fromDate.compareTo(toDate) <= 0);
  }

  WorkListFilters withoutOwner() => WorkListFilters(
    kind: kind,
    serial: serial,
    ntet: ntet,
    locality: locality,
    county: county,
    fromDate: fromDate,
    toDate: toDate,
  );

  static String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';
}