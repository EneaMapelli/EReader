/// Presentation-only settings. Never change book text, source anchors,
/// voice profiles, audio payloads, or cloud consent.
class ReadingPreferences {
  const ReadingPreferences({
    this.fontSize = 19,
    this.lineHeight = 1.75,
    this.fontFamily = 'serif',
    this.palette = 'system',
    this.contentWidth = 760,
    this.textAlignment = 'auto',
    this.paragraphSpacingFactor = 1.0,
    this.letterSpacing = 0.0,
    this.wordSpacing = 0.0,
  });

  final double fontSize;
  final double lineHeight;
  /// Generic family names supported by the reader's Flutter text renderer.
  final String fontFamily;
  /// The visual EPUB palette, not the device-wide application theme.
  final String palette;
  /// Maximum text-column width in logical pixels (responsive on narrow screens).
  final double contentWidth;
  /// auto: original EPUB justification and TXT/PDF start-alignment.
  final String textAlignment;
  /// Scales existing visual gaps; default 1.0 preserves legacy layout.
  final double paragraphSpacingFactor;
  /// Optional extra spacing in logical pixels; zero preserves Flutter defaults.
  final double letterSpacing;
  final double wordSpacing;

  static const fontFamilies = {'serif', 'sans-serif', 'monospace'};
  static const palettes = {'system', 'sepia', 'night', 'highContrast'};
  static const textAlignments = {'auto', 'start', 'justify'};

  void validate() {
    if (!fontSize.isFinite || fontSize < 14 || fontSize > 32 ||
        !lineHeight.isFinite || lineHeight < 1.2 || lineHeight > 2.4 ||
        !contentWidth.isFinite || contentWidth < 480 || contentWidth > 1000 ||
        !fontFamilies.contains(fontFamily) ||
        !palettes.contains(palette) ||
        !textAlignments.contains(textAlignment) ||
        !paragraphSpacingFactor.isFinite ||
        paragraphSpacingFactor < 0.5 || paragraphSpacingFactor > 2.5 ||
        !letterSpacing.isFinite || letterSpacing < 0 || letterSpacing > 3 ||
        !wordSpacing.isFinite || wordSpacing < 0 || wordSpacing > 8) {
      throw const FormatException('Invalid visual reading preferences');
    }
  }

  ReadingPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    String? palette,
    double? contentWidth,
    String? textAlignment,
    double? paragraphSpacingFactor,
    double? letterSpacing,
    double? wordSpacing,
  }) => ReadingPreferences(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    fontFamily: fontFamily ?? this.fontFamily,
    palette: palette ?? this.palette,
    contentWidth: contentWidth ?? this.contentWidth,
    textAlignment: textAlignment ?? this.textAlignment,
    paragraphSpacingFactor:
        paragraphSpacingFactor ?? this.paragraphSpacingFactor,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    wordSpacing: wordSpacing ?? this.wordSpacing,
  );

  Map<String, Object> toJson() {
    validate();
    return {
      'version': 1,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'fontFamily': fontFamily,
      'palette': palette,
      'contentWidth': contentWidth,
      'textAlignment': textAlignment,
      'paragraphSpacingFactor': paragraphSpacingFactor,
      'letterSpacing': letterSpacing,
      'wordSpacing': wordSpacing,
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
    // Optional v1 fields: earlier installations already store v1 JSON
    // with four display settings. Their existing look must not change.
    final contentWidth = json.containsKey('contentWidth')
        ? json['contentWidth'] : 760;
    final textAlignment = json.containsKey('textAlignment')
        ? json['textAlignment'] : 'auto';
    final paragraphSpacingFactor = json.containsKey('paragraphSpacingFactor')
        ? json['paragraphSpacingFactor'] : 1.0;
    final letterSpacing = json.containsKey('letterSpacing')
        ? json['letterSpacing'] : 0.0;
    final wordSpacing = json.containsKey('wordSpacing')
        ? json['wordSpacing'] : 0.0;
    if (fontSize is! num || lineHeight is! num ||
        fontFamily is! String || palette is! String ||
        contentWidth is! num || textAlignment is! String ||
        paragraphSpacingFactor is! num ||
        letterSpacing is! num || wordSpacing is! num) {
      throw const FormatException('Malformed visual preferences');
    }
    final value = ReadingPreferences(
      fontSize: fontSize.toDouble(),
      lineHeight: lineHeight.toDouble(),
      fontFamily: fontFamily,
      palette: palette,
      contentWidth: contentWidth.toDouble(),
      textAlignment: textAlignment,
      paragraphSpacingFactor: paragraphSpacingFactor.toDouble(),
      letterSpacing: letterSpacing.toDouble(),
      wordSpacing: wordSpacing.toDouble(),
    );
    value.validate();
    return value;
  }
}
