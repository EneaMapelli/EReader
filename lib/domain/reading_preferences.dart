/// Presentation-only settings. Never change book text, source anchors,
/// voice profiles, audio payloads, or cloud consent.
class ReadingPreferences {
  const ReadingPreferences({
    this.fontSize = 19,
    this.lineHeight = 1.75,
    this.fontFamily = 'serif',
    this.palette = 'system',
  });

  final double fontSize;
  final double lineHeight;
  /// Generic family names supported by the reader's Flutter text renderer.
  final String fontFamily;
  /// The visual EPUB palette, not the device-wide application theme.
  final String palette;

  static const fontFamilies = {'serif', 'sans-serif', 'monospace'};
  static const palettes = {'system', 'sepia', 'night'};

  void validate() {
    if (!fontSize.isFinite || fontSize < 14 || fontSize > 32 ||
        !lineHeight.isFinite || lineHeight < 1.2 || lineHeight > 2.4 ||
        !fontFamilies.contains(fontFamily) ||
        !palettes.contains(palette)) {
      throw const FormatException('Invalid visual reading preferences');
    }
  }

  ReadingPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    String? palette,
  }) => ReadingPreferences(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    fontFamily: fontFamily ?? this.fontFamily,
    palette: palette ?? this.palette,
  );

  Map<String, Object> toJson() {
    validate();
    return {
      'version': 1,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'fontFamily': fontFamily,
      'palette': palette,
    };
  }

  factory ReadingPreferences.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported visual preferences version');
    }
    final fontSize = json['fontSize'];
    final lineHeight = json['lineHeight'];
    final fontFamily = json['fontFamily'];
    final palette = json['palette'];
    if (fontSize is! num || lineHeight is! num ||
        fontFamily is! String || palette is! String) {
      throw const FormatException('Malformed visual preferences');
    }
    final value = ReadingPreferences(
      fontSize: fontSize.toDouble(),
      lineHeight: lineHeight.toDouble(),
      fontFamily: fontFamily,
      palette: palette,
    );
    value.validate();
    return value;
  }
}
