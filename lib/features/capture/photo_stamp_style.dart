/// The text height is relative to the shorter side of the upright photo.
class PhotoStampStyle {
  const PhotoStampStyle({
    this.relativeTextHeight = 0.035,
    this.minTextHeight = 20,
    this.maxTextHeight = 84,
  }) : assert(relativeTextHeight > 0 && relativeTextHeight <= 0.1),
        assert(minTextHeight > 0),
        assert(maxTextHeight >= minTextHeight);

  final double relativeTextHeight;
  final double minTextHeight;
  final double maxTextHeight;

  double textHeight(int shortEdge) =>
      (shortEdge * relativeTextHeight).clamp(minTextHeight, maxTextHeight);
}