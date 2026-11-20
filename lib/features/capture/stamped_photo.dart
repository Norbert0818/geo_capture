import 'dart:typed_data';

class StampedPhoto {
  StampedPhoto({
    required Uint8List bytes,
    required this.width,
    required this.height,
    required this.overlayText,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final Uint8List bytes;
  final int width;
  final int height;
  final String overlayText;

  String get mimeType => 'image/jpeg';
}
