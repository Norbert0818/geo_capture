bool isUploadId(String value) =>
    RegExp(
      r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
    ).hasMatch(value) &&
    value != '00000000-0000-0000-0000-000000000000';

String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw const FormatException();
  return value;
}

String _id(Map<String, dynamic> json, String key) {
  final value = _text(json, key);
  if (!isUploadId(value)) throw const FormatException();
  return value;
}

int _integer(Map<String, dynamic> json, String key, {int minimum = 0}) {
  final value = json[key];
  if (value is! int || value < minimum) throw const FormatException();
  return value;
}

double _number(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) throw const FormatException();
  return value.toDouble();
}

DateTime _date(Map<String, dynamic> json, String key) {
  final text = _text(json, key);
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(text)) {
    throw const FormatException();
  }
  return DateTime.parse(text).toUtc();
}

List<Map<String, dynamic>> _objects(Map<String, dynamic> json, String key) {
  final values = json[key];
  if (values is! List) throw const FormatException();
  return values.map((value) {
    if (value is! Map<String, dynamic>) throw const FormatException();
    return value;
  }).toList();
}

class UploadHistoryItem {
  const UploadHistoryItem({
    required this.id,
    required this.clientUploadId,
    required this.serialNumber,
    required this.ownerId,
    required this.uploadedByUsername,
    required this.uploadedAtUtc,
    required this.photoCount,
    required this.version,
  });

  final String id;
  final String clientUploadId;
  final String serialNumber;
  final String ownerId;
  final String uploadedByUsername;
  final DateTime uploadedAtUtc;
  final int photoCount;
  final String version;

  factory UploadHistoryItem.fromJson(Map<String, dynamic> json) =>
      UploadHistoryItem(
        id: _id(json, 'id'),
        clientUploadId: _id(json, 'clientUploadId'),
        serialNumber: _text(json, 'serialNumber'),
        ownerId: _id(json, 'ownerId'),
        uploadedByUsername: _text(json, 'uploadedByUsername'),
        uploadedAtUtc: _date(json, 'uploadedAtUtc'),
        photoCount: _integer(json, 'photoCount', minimum: 1),
        version: _id(json, 'version'),
      );
}

class UploadHistoryResult {
  UploadHistoryResult({
    required this.page,
    required this.pageSize,
    required this.total,
    required List<UploadHistoryItem> items,
  }) : items = List.unmodifiable(items);

  final int page;
  final int pageSize;
  final int total;
  final List<UploadHistoryItem> items;

  int get totalPages => total == 0 ? 1 : (total / pageSize).ceil();
  bool get hasPrevious => page > 1;
  bool get hasNext => page * pageSize < total;

  factory UploadHistoryResult.fromJson(Map<String, dynamic> json) =>
      UploadHistoryResult(
        page: _integer(json, 'page', minimum: 1),
        pageSize: _integer(json, 'pageSize', minimum: 1),
        total: _integer(json, 'total'),
        items: _objects(json, 'items').map(UploadHistoryItem.fromJson).toList(),
      );
}

class StoredPhoto {
  const StoredPhoto({
    required this.id,
    required this.clientPhotoId,
    required this.position,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.coordinatesText,
    required this.capturedAtUtc,
    required this.locationMeasuredAtUtc,
    required this.originalMimeType,
    required this.originalWidth,
    required this.originalHeight,
    required this.stampedWidth,
    required this.stampedHeight,
    required this.originalByteLength,
    required this.stampedByteLength,
    required this.originalSha256,
    required this.stampedSha256,
  });

  final String id;
  final String clientPhotoId;
  final int position;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final String coordinatesText;
  final DateTime capturedAtUtc;
  final DateTime locationMeasuredAtUtc;
  final String originalMimeType;
  final int originalWidth;
  final int originalHeight;
  final int stampedWidth;
  final int stampedHeight;
  final int originalByteLength;
  final int stampedByteLength;
  final String originalSha256;
  final String stampedSha256;

  factory StoredPhoto.fromJson(Map<String, dynamic> json) => StoredPhoto(
    id: _id(json, 'id'),
    clientPhotoId: _id(json, 'clientPhotoId'),
    position: _integer(json, 'position'),
    latitude: _number(json, 'latitude'),
    longitude: _number(json, 'longitude'),
    accuracyMeters: _number(json, 'accuracyMeters'),
    coordinatesText: _text(json, 'coordinatesText'),
    capturedAtUtc: _date(json, 'capturedAtUtc'),
    locationMeasuredAtUtc: _date(json, 'locationMeasuredAtUtc'),
    originalMimeType: _text(json, 'originalMimeType'),
    originalWidth: _integer(json, 'originalWidth', minimum: 1),
    originalHeight: _integer(json, 'originalHeight', minimum: 1),
    stampedWidth: _integer(json, 'stampedWidth', minimum: 1),
    stampedHeight: _integer(json, 'stampedHeight', minimum: 1),
    originalByteLength: _integer(json, 'originalByteLength', minimum: 1),
    stampedByteLength: _integer(json, 'stampedByteLength', minimum: 1),
    originalSha256: _text(json, 'originalSha256'),
    stampedSha256: _text(json, 'stampedSha256'),
  );
}

class StoredUpload {
  StoredUpload({required this.summary, required List<StoredPhoto> photos})
    : photos = List.unmodifiable(photos);

  final UploadHistoryItem summary;
  final List<StoredPhoto> photos;

  factory StoredUpload.fromJson(Map<String, dynamic> json) {
    final photos = _objects(json, 'photos').map(StoredPhoto.fromJson).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    if (photos.isEmpty ||
        photos.map((photo) => photo.id).toSet().length != photos.length) {
      throw const FormatException();
    }
    return StoredUpload(
      summary: UploadHistoryItem.fromJson({
        ...json,
        'photoCount': photos.length,
      }),
      photos: photos,
    );
  }
}
