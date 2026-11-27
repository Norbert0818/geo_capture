import 'serial_reading.dart';
import 'serial_reader_stub.dart'
if (dart.library.io) 'serial_reader_native.dart'
as implementation;

export 'serial_reading.dart';

SerialPhotoReader createSerialPhotoReader() => implementation.createReader();