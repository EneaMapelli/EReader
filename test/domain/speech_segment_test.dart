import 'package:flutter_test/flutter_test.dart';
import 'package:ereader/domain/speech_segment.dart';

void main() {
  test('splits sentences without changing spoken tokens', () {
    const input = ' Ciao mondo!  Come stai?\nBenissimo.';
    final chunks = segmentSpeech(input, maxChars: 24);
    expect(chunks.map((s) => s.text).toList(),
        ['Ciao mondo!', 'Come stai?', 'Benissimo.']);
    for (final chunk in chunks) {
      expect(input.substring(chunk.start, chunk.end), chunk.text);
    }
  });

  test('does not split utf16 surrogate pairs at a hard limit', () {
    final input = 'a' * 18 + '😀' + 'b' * 20;
    final chunks = segmentSpeech(input, maxChars: 19);
    expect(chunks.first.text, 'a' * 18);
    expect(chunks.skip(1).map((s) => s.text).join(), '😀' + 'b' * 20);
  });

  test('hard TTS boundaries do not cut decomposed accents or ZWJ emoji',
      () {
    final samples = [
      'a' * 17 + 'e\u0301' + 'b' * 36,
      'a' * 15 + '👩‍🚀' + 'b' * 36,
      'a' * 16 + '🇮🇹' + 'b' * 36,
      'a' * 15 + '👍🏽' + 'b' * 36,
    ];
    for (final source in samples) {
      final chunks = segmentSpeech(source, maxChars: 18);
      expect(chunks, isNotEmpty);
      expect(chunks.map((s) => s.text).join(), source,
          reason: 'Hard chunk boundaries must never lose source characters');
      expect(chunks.every((s) => s.text.length <= 18), isTrue);
      for (final segment in chunks) {
        expect(source.substring(segment.start, segment.end), segment.text);
      }
      expect(chunks.first.text.endsWith('a'), isTrue,
          reason: 'The first hard split must precede the joined cluster');
    }
  });

  test('overlong single emoji cluster fails closed rather than dropping text',
      () {
    final combined = 'e' + List.filled(20, '\u0301').join();
    expect(() => segmentSpeech(combined, maxChars: 16),
        throwsFormatException);
  });

  test('handles empty and whitespace-only books', () {
    expect(segmentSpeech(''), isEmpty);
    expect(segmentSpeech('   \n\t  '), isEmpty);
  });

  test('sentence-ending punctuation keeps closing dialogue quotes', () {
    const sources = <String, List<String>>{
      'Anna disse: «Ciao!» Poi sorrise.':
          ['Anna disse: «Ciao!»', 'Poi sorrise.'],
      'He asked: “Really?” Then left.':
          ['He asked: “Really?”', 'Then left.'],
      'She said: "Why?!" and paused.':
          ['She said: "Why?!"', 'and paused.'],
      'He replied ("Done.") After that he left.':
          ['He replied ("Done.")', 'After that he left.'],
      'The note [ends here.] Next sentence.':
          ['The note [ends here.]', 'Next sentence.'],
    };
    for (final entry in sources.entries) {
      final result = segmentSpeech(entry.key, maxChars: 100);
      expect(result.map((segment) => segment.text).toList(),
          entry.value, reason: entry.key);
      for (final segment in result) {
        expect(entry.key.substring(segment.start, segment.end),
            segment.text);
      }
    }
  });

  test('bounded quoted sentence never crosses the provider input cap',
      () {
    const source = '«Hello 🐉 friend!» This continues after the quotation.';
    final chunks = segmentSpeech(source, maxChars: 23);
    expect(chunks, isNotEmpty);
    expect(chunks.first.text, '«Hello 🐉 friend!»');
    expect(chunks.every((segment) => segment.text.length <= 23), isTrue);
    for (final segment in chunks) {
      expect(source.substring(segment.start, segment.end), segment.text);
      if (segment.end < source.length) {
        final last = source.codeUnitAt(segment.end - 1);
        final next = source.codeUnitAt(segment.end);
        expect(last >= 0xD800 && last <= 0xDBFF &&
            next >= 0xDC00 && next <= 0xDFFF, isFalse,
            reason: 'Never split an emoji surrogate pair');
      }
    }
  });

  test('keeps title abbreviations inside one complete spoken sentence', () {
    const source =
        'Il Dott. Rossi parlò. Poi arrivò Mr. Darcy. Fine.';
    final pieces = segmentSpeech(source, maxChars: 100);
    expect(pieces.map((s) => s.text).toList(), [
      'Il Dott. Rossi parlò.',
      'Poi arrivò Mr. Darcy.',
      'Fine.',
    ]);
    for (final part in pieces) {
      expect(source.substring(part.start, part.end), part.text);
    }
  });

  test('does not split author initials or accented capitalized names', () {
    const source =
        'J. R. R. Tolkien incontrò la Dott. Émile. Poi uscirono.';
    final pieces = segmentSpeech(source, maxChars: 100);
    expect(pieces.map((s) => s.text).toList(), [
      'J. R. R. Tolkien incontrò la Dott. Émile.',
      'Poi uscirono.',
    ]);
  });

  test('ordinary periods and chapter-limited abbreviations stay distinct',
      () {
    expect(segmentSpeech('Prima frase. Poi un’altra.').map((s) => s.text),
        ['Prima frase.', 'Poi un’altra.']);
    expect(segmentSpeech('È arrivato il dott.').map((s) => s.text),
        ['È arrivato il dott.']);
    const source = 'Il Dott.\nRossi arrivò. Poi uscì.';
    expect(segmentSpeech(source).map((s) => s.text), [
      'Il Dott.', 'Rossi arrivò.', 'Poi uscì.',
    ]);

    // A range ending at an abbreviation's dot cannot peek into a
    // different OPF spine/chapter and merge a visual-only section.
    const separate = 'Il Dott. Rossi arrivò.';
    final beforeName = separate.indexOf(' Rossi');
    final bounded = segmentSpeechRange(
      separate, start: 0, end: beforeName, maxChars: 100);
    expect(bounded.map((s) => s.text), ['Il Dott.']);
  });

  test('hard input limit and source offsets still constrain abbreviations',
      () {
    const text = 'Il Dott. Rossi camminò a lungo senza alcuna pausa.';
    final pieces = segmentSpeech(text, maxChars: 16);
    expect(pieces.every((s) => s.text.length <= 16), isTrue);
    for (final piece in pieces) {
      expect(text.substring(piece.start, piece.end), piece.text);
    }
  });

  test('keeps decimal numbers in one utterance', () {
    const text = 'La cifra è 3.14 e non 3.15. Seconda frase.';
    final chunks = segmentSpeech(text, maxChars: 100);
    expect(chunks.map((s) => s.text).toList(),
        ['La cifra è 3.14 e non 3.15.', 'Seconda frase.']);
  });

  test('splits paragraphs at newlines even below the limit', () {
    final chunks = segmentSpeech('Paragrafo uno.\nParagrafo due.',
        maxChars: 120);
    expect(chunks.map((s) => s.text).toList(),
        ['Paragrafo uno.', 'Paragrafo due.']);
  });

  test('all spoken spans point to exact source substrings', () {
    const text = 'A  😀  parola lunga senza punteggiatura  Fine.';
    final chunks = segmentSpeech(text, maxChars: 18);
    expect(chunks, isNotEmpty);
    for (final chunk in chunks) {
      expect(chunk.start, greaterThanOrEqualTo(0));
      expect(chunk.end, lessThanOrEqualTo(text.length));
      expect(chunk.start, lessThan(chunk.end));
      expect(text.substring(chunk.start, chunk.end), chunk.text);
    }
  });

  test('global source range matches legacy chapter-local segmentation', () {
    const first = 'Header. This first chapter is done.';
    const second = 'Chapter 📖 second. Price 3.14! '
        'A longer passage with many words and line breaks.\nNext line.';
    const third = 'The final chapter. End.';
    final full = '$first\n\n$second\n\n$third';
    final start = first.length + 2;
    final end = start + second.length;
    final global = segmentSpeechRange(
        full, start: start, end: end, maxChars: 24);
    final local = segmentSpeech(
        full.substring(start, end), maxChars: 24);
    expect(global.length, local.length);
    for (var i = 0; i < global.length; i++) {
      expect(global[i].start, local[i].start + start);
      expect(global[i].end, local[i].end + start);
      expect(global[i].text, local[i].text);
      expect(full.substring(global[i].start, global[i].end),
          global[i].text);
    }
  });

  test('source-range splitting enforces chapter and Unicode boundaries', () {
    const content = 'Prelude.\n\n📖 Ending 2.71!\n\nAfter.';
    final start = content.indexOf('📖');
    final end = content.indexOf('\n\nAfter.');
    final ranged = segmentSpeechRange(
        content, start: start, end: end, maxChars: 16);
    expect(ranged, isNotEmpty);
    expect(ranged.every((s) => s.start >= start && s.end <= end), isTrue);
    expect(ranged.first.start, start);
    expect(() => segmentSpeechRange(content,
        start: start + 1, end: end), throwsFormatException);
    expect(() => segmentSpeechRange(content,
        start: start, end: start + 1), throwsFormatException);
    expect(() => segmentSpeechRange(content,
        start: -1, end: end), throwsRangeError);
  });

  test('large single chapter yields exact globally indexed TTS spans', () {
    final preface = List.filled(120, 'Preface text. ').join();
    final chapter = List.filled(16000, 'Long chapter sentence. ').join();
    final combined = '$preface\n\n$chapter';
    final start = preface.length + 2;
    final segments = segmentSpeechRange(
        combined, start: start, end: combined.length);
    expect(segments.length, greaterThan(1000));
    expect(segments.first.start, start);
    expect(segments.last.end, lessThanOrEqualTo(combined.length));
    for (final index in [0, 1, segments.length ~/ 2, segments.length - 1]) {
      final chunk = segments[index];
      expect(combined.substring(chunk.start, chunk.end), chunk.text);
      expect(chunk.start, greaterThanOrEqualTo(start));
    }
  });

  test('rejects too-small chunk sizes', () {
    expect(() => segmentSpeech('hello', maxChars: 2), throwsArgumentError);
  });
}
