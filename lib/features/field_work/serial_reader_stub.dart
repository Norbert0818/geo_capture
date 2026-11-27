import 'dart:typed_data';

import 'serial_reading.dart';

SerialPhotoReader createReader() => _UnavailableReader();

class _UnavailableReader implements SerialPhotoReader {
  @override
  Future<SerialReading> read(Uint8List original) async =>
      const SerialReading(supported: false);
}