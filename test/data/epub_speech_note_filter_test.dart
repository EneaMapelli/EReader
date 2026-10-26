import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_speech_note_filter.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImmediateEngine implements SpeechEngine {
  final spoken = <String>[];

  @override
  Future<List<SpeechVoice>> listVoices() async => const [];
  @override
  Future<void> chooseVoice(SpeechVoice voice) async {}
  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    spoken.add(text);
  }
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

Uint8List _book(String chapter, {String? footnotes}) {
  final other = footnotes == null ? '' :
      '<item id="notes" href="notes.xhtml" '
      'media-type="application/xhtml+xml"/>';
  final spineNotes = footnotes == null ? '' : '<itemref idref="notes"/>';
  final zip = Archive()
    ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..add(ArchiveFile.string('META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="OPS/book.opf"/>'
        '</rootfiles></container>'))
    ..add(ArchiveFile.string('OPS/book.opf',
        '<package><metadata><title>Notes</title></metadata>'
        '<manifest><item id="body" href="body.xhtml" '
        'media-type="application/xhtml+xml"/>$other</manifest>'
        '<spine><itemref idref="body"/>'
        '$spineNotes'
        '</spine></package>'))
    ..add(ArchiveFile.string('OPS/body.xhtml', chapter));
  if (footnotes != null) {
    zip.add(ArchiveFile.string('OPS/notes.xhtml', footnotes));
  }
  return ZipEncoder().encodeBytes(zip);
}

void main() {
  test('exact fully contained note is skipped, but crossing text is spoken', () {
    const source = 'Opening. Note body. Conclusion.';
    final rangeStart = source.indexOf('Note body.');
    final filter = EpubSpeechNoteFilter(source, [
      EpubSpokenNoteRange(rangeStart, rangeStart + 'Note body.'.length),
    ]);
    expect(filter.contains(const SpeechSegment(0, 8, 'Opening.')), isFalse);
    expect(filter.contains(SpeechSegment(rangeStart, rangeStart + 10,
        'Note body.')), isTrue);
    expect(filter.contains(SpeechSegment(rangeStart - 1,
        rangeStart + 10, ' Note body.')), isFalse);
    expect(filter.contains(SpeechSegment(rangeStart, rangeStart + 11,
        'Note body. ')), isFalse);
    expect(filter.contains(SpeechSegment(rangeStart, rangeStart + 10,
        'Wrong text')), isFalse);
    expect(filter.contains(const SpeechSegment(-1, 3, 'abc')), isFalse);
  });

  test('overlapping note regions merge; adjacent normal prose stays audible', () {
    const source = '0123456789abcdefghijkl';
    final filter = EpubSpeechNoteFilter(source, [
      const EpubSpokenNoteRange(6, 12),
      const EpubSpokenNoteRange(3, 9),
      const EpubSpokenNoteRange(14, 17),
    ]);
    expect(filter.contains(const SpeechSegment(5, 11, '56789a')), isTrue);
    expect(filter.contains(const SpeechSegment(11, 15, 'bcde')), isFalse);
    expect(filter.contains(const SpeechSegment(14, 17, 'efg')), isTrue);
  });

  test('malformed note offsets fail closed, including UTF-16 splits', () {
    const source = 'A📖BC';
    expect(() => EpubSpeechNoteFilter(source,
        [const EpubSpokenNoteRange(2, 4)]), throwsFormatException);
    expect(() => EpubSpeechNoteFilter(source,
        [const EpubSpokenNoteRange(0, 99)]), throwsFormatException);
    expect(() => EpubSpeechNoteFilter(source,
        [const EpubSpokenNoteRange(3, 3)]), throwsFormatException);
  });

  test('extractor carries same verified note boundaries into DocumentContent',
      () {
    const chapter = '<html><body>'
        '<p>A normal narrative sentence.</p>'
        '<p><a epub:type="noteref" href="notes.xhtml#f1">[1]</a></p>'
        '</body></html>';
    const note = '<html><body><aside id="f1" epub:type="footnote">'
        'A verified note to skip.</aside></body></html>';
    final result = const EpubTextExtractor().extract(
        _book(chapter, footnotes: note));
    final doc = documentFromExtractedEpub(result);
    expect(result.spokenNoteRanges, hasLength(1));
    expect(doc.epubSpokenNoteRanges, hasLength(1));
    final range = doc.epubSpokenNoteRanges.single;
    expect(doc.text.substring(range.start, range.end),
        'A verified note to skip.');
    final filter = EpubSpeechNoteFilter(doc.text, doc.epubSpokenNoteRanges);
    expect(filter.contains(SpeechSegment(range.start, range.end,
        doc.text.substring(range.start, range.end))), isTrue);
    expect(doc.text, contains('A normal narrative sentence.'));
  });

  test('ordinary spine links and auxiliary notes are not silently skipped',
      () {
    const chapter = '<html><body><p>See <a href="notes.xhtml#f1">'
        'ordinary destination</a>.</p></body></html>';
    const note = '<html><body><p id="f1">Ordinary paragraph.</p>'
        '</body></html>';
    final result = const EpubTextExtractor().extract(
        _book(chapter, footnotes: note));
    expect(result.spokenNoteRanges, isEmpty);
    expect(EpubSpeechNoteFilter(result.text, result.spokenNoteRanges).hasNotes,
        isFalse);
  });

  test('player skips before checkpoint, voice or billing-boundary speak',
      () async {
    const text = 'Start. Note text. End.';
    final filter = EpubSpeechNoteFilter(text,
        [const EpubSpokenNoteRange(7, 17)]);
    final engine = _ImmediateEngine();
    final checkpoints = <int>[];
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 6, 'Start.'),
        SpeechSegment(7, 17, 'Note text.'),
        SpeechSegment(18, 22, 'End.'),
      ],
      onSegmentStarted: (segment) async => checkpoints.add(segment.start),
    );
    player.shouldSkipSegment = filter.contains;
    await player.play();
    expect(engine.spoken, ['Start.', 'End.']);
    expect(checkpoints, [0, 18]);
    expect(player.currentIndex, 3);

    // Turning skipping off restores normal narration on a future replay.
    player.shouldSkipSegment = null;
    await player.play();
    expect(engine.spoken, [
      'Start.', 'End.', 'Start.', 'Note text.', 'End.',
    ]);
    player.dispose();
  });

  test('skip-all session finishes without a speech request or checkpoint',
      () async {
    final engine = _ImmediateEngine();
    var checkpoints = 0;
    final player = ReaderPlayer(
      engine: engine,
      segments: const [SpeechSegment(0, 5, 'Note.')],
      onSegmentStarted: (_) async { checkpoints++; },
    );
    player.shouldSkipSegment = (_) => true;
    await player.play();
    expect(engine.spoken, isEmpty);
    expect(checkpoints, 0);
    expect(player.currentIndex, 1);
    expect(player.isPlaying, false);
    player.dispose();
  });
}
