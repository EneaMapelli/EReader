import 'package:ereader/domain/reading_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default visual style is independent from speech preferences', () {
    const original = ReadingPreferences();
    expect(original.fontSize, 19);
    expect(original.lineHeight, 1.75);
    expect(original.fontFamily, 'serif');
    expect(original.palette, 'system');
    expect(original.contentWidth, 760);
    expect(original.textAlignment, 'auto');
    expect(original.paragraphSpacingFactor, 1.0);
    expect(original.letterSpacing, 0.0);
    expect(original.wordSpacing, 0.0);
    expect(original.toJson()['version'], 1);
  });

  test('round-trip all visual fields, including night and accessible spacing',
      () {
    const original = ReadingPreferences(
      fontSize: 26, lineHeight: 2.2,
      fontFamily: 'sans-serif', palette: 'night',
      contentWidth: 920, textAlignment: 'start',
      paragraphSpacingFactor: 2.0,
      letterSpacing: 1.5, wordSpacing: 4,
    );
    expect(ReadingPreferences.fromJson(original.toJson()).toJson(),
        original.toJson());
    expect(original.copyWith(
      fontSize: 16, palette: 'sepia',
      contentWidth: 520, textAlignment: 'justify',
    ).toJson()['fontFamily'], 'sans-serif');
  });

  test('reject malformed, unsupported or non-finite visual preferences', () {
    const valid = ReadingPreferences();
    final cases = <ReadingPreferences>[
      valid.copyWith(fontSize: 13),
      valid.copyWith(fontSize: 33),
      valid.copyWith(lineHeight: 1.1),
      valid.copyWith(lineHeight: 2.5),
      valid.copyWith(lineHeight: double.nan),
      valid.copyWith(fontSize: double.infinity),
      valid.copyWith(fontFamily: 'remote://font'),
      valid.copyWith(palette: 'not-real'),
      valid.copyWith(contentWidth: 479),
      valid.copyWith(contentWidth: 1001),
      valid.copyWith(contentWidth: double.nan),
      valid.copyWith(textAlignment: 'center'),
      valid.copyWith(paragraphSpacingFactor: 0.49),
      valid.copyWith(paragraphSpacingFactor: 2.51),
      valid.copyWith(paragraphSpacingFactor: double.nan),
      valid.copyWith(paragraphSpacingFactor: double.infinity),
      valid.copyWith(letterSpacing: -0.1),
      valid.copyWith(letterSpacing: 3.1),
      valid.copyWith(letterSpacing: double.nan),
      valid.copyWith(letterSpacing: double.infinity),
      valid.copyWith(wordSpacing: -1),
      valid.copyWith(wordSpacing: 8.1),
      valid.copyWith(wordSpacing: double.nan),
      valid.copyWith(wordSpacing: double.negativeInfinity),
    ];
    for (final item in cases) {
      expect(item.validate, throwsFormatException);
    }
    final broken = <Map<String, dynamic>>[
      {'version': 2, 'fontSize': 19, 'lineHeight': 1.75,
        'fontFamily': 'serif', 'palette': 'system'},
      {'version': 1, 'fontSize': '19', 'lineHeight': 1.75,
        'fontFamily': 'serif', 'palette': 'system'},
      {'version': 1, 'fontSize': 19, 'lineHeight': null,
        'fontFamily': 'serif', 'palette': 'system'},
      {'version': 1, 'fontSize': 19, 'lineHeight': 1.75,
        'fontFamily': 'serif', 'palette': 'xx'},
      {'version': 1, 'fontSize': 19, 'lineHeight': 1.75,
        'fontFamily': 'serif', 'palette': 'night', 'contentWidth': null},
      {'version': 1, 'fontSize': 19, 'lineHeight': 1.75,
        'fontFamily': 'serif', 'palette': 'night', 'textAlignment': null},
      {'version': 1, 'fontSize': 19, 'lineHeight': 1.75,
        'fontFamily': 'serif', 'palette': 'night',
        'paragraphSpacingFactor': null},
      {'version': 1, 'fontSize': 19, 'lineHeight': 1.75,
        'fontFamily': 'serif', 'palette': 'system', 'letterSpacing': null},
      {'version': 1, 'fontSize': 19, 'lineHeight': 1.75,
        'fontFamily': 'serif', 'palette': 'system', 'wordSpacing': '3.0'},
    ];
    for (final item in broken) {
      expect(() => ReadingPreferences.fromJson(item), throwsFormatException);
    }
  });

  test('legacy v1 SQLite JSON retains original appearance defaults', () {
    final old = ReadingPreferences.fromJson({
      'version': 1, 'fontSize': 25, 'lineHeight': 1.5,
      'fontFamily': 'serif', 'palette': 'sepia',
    });
    expect(old.contentWidth, 760);
    expect(old.textAlignment, 'auto');
    expect(old.paragraphSpacingFactor, 1.0);
    expect(old.letterSpacing, 0.0);
    expect(old.wordSpacing, 0.0);
    expect(old.fontSize, 25);
    expect(old.palette, 'sepia');
    expect(old.toJson()['contentWidth'], 760);
  });

  test('high-contrast appearance and narrow-width choices round-trip', () {
    const profile = ReadingPreferences(
      palette: 'highContrast', contentWidth: 480,
      textAlignment: 'start',
    );
    profile.validate();
    expect(ReadingPreferences.fromJson(profile.toJson()).toJson(),
        profile.toJson());
  });

  test('paragraph spacing survives legacy JSON without migration', () {
    final legacy = ReadingPreferences.fromJson({
      'version': 1, 'fontSize': 19, 'lineHeight': 1.75,
      'fontFamily': 'serif', 'palette': 'system',
    });
    expect(legacy.paragraphSpacingFactor, 1.0);
    final adjusted = legacy.copyWith(paragraphSpacingFactor: 0.5);
    expect(adjusted.toJson()['paragraphSpacingFactor'], 0.5);
    expect(ReadingPreferences.fromJson(adjusted.toJson())
        .paragraphSpacingFactor, 0.5);
  });

  test('optional spacing survives old v1 JSON and round trips', () {
    final legacy = ReadingPreferences.fromJson({
      'version': 1,
      'fontSize': 19,
      'lineHeight': 1.75,
      'fontFamily': 'serif',
      'palette': 'system',
    });
    expect(legacy.letterSpacing, 0);
    expect(legacy.wordSpacing, 0);
    final custom = legacy.copyWith(letterSpacing: 2.25, wordSpacing: 6.5);
    expect(custom.toJson()['letterSpacing'], 2.25);
    expect(custom.toJson()['wordSpacing'], 6.5);
    final restored = ReadingPreferences.fromJson(custom.toJson());
    expect(restored.letterSpacing, 2.25);
    expect(restored.wordSpacing, 6.5);
    expect(restored.paragraphSpacingFactor, 1.0);
  });

  test('values on the supported bounds are valid', () {
    const ReadingPreferences(
      fontSize: 14, lineHeight: 1.2,
      fontFamily: 'monospace', palette: 'sepia',
    ).validate();
    const ReadingPreferences(
      fontSize: 32, lineHeight: 2.4,
      fontFamily: 'sans-serif', palette: 'highContrast',
      contentWidth: 1000, textAlignment: 'justify',
      paragraphSpacingFactor: 2.5,
      letterSpacing: 3, wordSpacing: 8,
    ).validate();
  });
}
