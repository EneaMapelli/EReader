/// Whole-book progress based on original canonical UTF-16 source offsets.
/// Audio duration, words-per-minute and PDF visual pages are deliberately
/// not inferred from text length.
class ReadingSourceProgress {
  const ReadingSourceProgress._();

  static double fraction({required int offset, required int length}) {
    if (length <= 0) return 0;
    return offset.clamp(0, length).toDouble() / length;
  }

  static int offsetForFraction({
    required double fraction,
    required int length,
  }) {
    if (length <= 0) return 0;
    if (!fraction.isFinite) {
      throw ArgumentError.value(fraction, 'fraction', 'Must be finite');
    }
    return (fraction.clamp(0.0, 1.0) * length).round()
        .clamp(0, length).toInt();
  }

  static int percentage({required int offset, required int length}) {
    if (length <= 0) return 0;
    return (100 * fraction(offset: offset, length: length)).round();
  }
}
