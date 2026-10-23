import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/domain/book.dart';
import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:ereader/llm/dialogue_analysis_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const planner = DialogueAnalysisPlanner();
  const text = 'Chapter one. «Hello!»\n\nChapter two. «Hello!»';
  const content = DocumentContent(
    title: 'Book',
    text: text,
    epubSpineRanges: [
      EpubSpineRange(idref: 'first', href: 'one.xhtml', start: 0, end: 21),
      EpubSpineRange(idref: 'second', href: 'two.xhtml', start: 23, end: 44),
    ],
  );
  const known = [
    CastCharacter(id: 'speaker-1', bookId: 'book', name: 'Anna'),
  ];
  final first = const SpeechSegment(0, 12, 'Chapter one.');
  final dialogue = SpeechSegment(
    text.indexOf('«'), text.indexOf('»') + 1, '«Hello!»',
  );

  test('EPUB scopes stay within source spine bounds', () {
    final scopes = planner.scopes(BookFormat.epub, content);
    expect(scopes.map((s) => s.id), ['epub:first', 'epub:second']);
    final window = planner.makeWindow(
      bookId: 'book', content: content,
      scope: scopes.first, segments: [first, dialogue],
      cast: known, from: 0,
    );
    expect(window.segments, hasLength(2));
    expect(window.excerpt.contains('Chapter two'), isFalse);
  });

  test('model quote must be exact, unambiguous and within selected window',
      () {
    final scope = planner.scopes(BookFormat.epub, content).first;
    final window = planner.makeWindow(
      bookId: 'book', content: content, scope: scope,
      segments: [first, dialogue], cast: known, from: 0,
    );
    final suggestions = planner.materializeProposals(
      bookId: 'book',
      source: text,
      window: window,
      idPrefix: 'unique',
      proposals: [
        const DialogueModelProposal(
          segmentIndex: 1,
          exactQuote: '«Hello!»',
          speakerId: 'speaker-1',
          confidence: 0.8,
        ),
      ],
    );
    expect(suggestions, hasLength(1));
    expect(suggestions.first.status, CastSpanStatus.proposed);
    expect(suggestions.first.lockedByUser, isFalse);
    expect(suggestions.first.start, text.indexOf('«'));
    expect(suggestions.first.sourceDigest, CastSpan.digest('«Hello!»'));

    expect(() => planner.materializeProposals(
      bookId: 'book', source: text,
      window: window, idPrefix: 'bad',
      proposals: [
        const DialogueModelProposal(
          segmentIndex: 1, exactQuote: 'Invented dialogue',
          speakerId: 'speaker-1', confidence: 1,
        ),
      ],
    ), throwsFormatException);
  });

  test('model cannot invent cast member or source segment', () {
    final window = planner.makeWindow(
      bookId: 'book', content: content,
      scope: planner.scopes(BookFormat.epub, content).first,
      segments: [first, dialogue], cast: known, from: 0,
    );
    for (final suggestion in [
      const DialogueModelProposal(
        segmentIndex: 7, exactQuote: '«Hello!»',
        speakerId: 'speaker-1', confidence: 0.4),
      const DialogueModelProposal(
        segmentIndex: 1, exactQuote: '«Hello!»',
        speakerId: 'invented', confidence: 0.4),
    ]) {
      expect(() => planner.materializeProposals(
        bookId: 'book', source: text, window: window,
        idPrefix: 'bad', proposals: [suggestion],
      ), throwsFormatException);
    }
  });

  test('never chooses a window outside the selected chapter', () {
    final scope = planner.scopes(BookFormat.epub, content).first;
    expect(() => planner.makeWindow(
      bookId: 'book', content: content,
      scope: scope, segments: [first],
      cast: known, from: scope.end,
    ), throwsFormatException);
  });

  test('repeated quote within one segment is rejected as ambiguous', () {
    const duplicate = '«Yes» and «Yes»';
    const duplicateContent = DocumentContent(
        title: 'Two quotes', text: duplicate);
    final scope = planner.scopes(BookFormat.txt, duplicateContent).first;
    final window = planner.makeWindow(
      bookId: 'book', content: duplicateContent, scope: scope,
      segments: [SpeechSegment(0, duplicate.length, duplicate)],
      cast: known, from: 0,
    );
    expect(() => planner.materializeProposals(
      bookId: 'book', source: duplicate, window: window,
      proposals: [const DialogueModelProposal(
        segmentIndex: 0, exactQuote: '«Yes»',
        speakerId: 'speaker-1', confidence: 0.5)],
      idPrefix: 'ambiguous',
    ), throwsFormatException);
  });

  test('backward context never includes previous or later chapters', () {
    const source =
        'EARLIER SECRET. Anna entered. «Hello!» FUTURE REVEAL.';
    const earlier = 'EARLIER SECRET.';
    const setup = 'Anna entered.';
    const speech = '«Hello!»';
    final start = source.indexOf(setup);
    final spokenStart = source.indexOf(speech);
    final spokenEnd = spokenStart + speech.length;
    final scope = DialogueAnalysisScope(
      id: 'chapter-2', title: 'Chapter two',
      start: start, end: source.indexOf(' FUTURE REVEAL'),
    );
    final input = [
      const SpeechSegment(0, earlier.length, earlier),
      SpeechSegment(start, start + setup.length, setup),
      SpeechSegment(spokenStart, spokenEnd, speech),
      SpeechSegment(source.indexOf('FUTURE'), source.length, 'FUTURE REVEAL.'),
    ];
    final window = planner.makeWindow(
      bookId: 'book',
      content: const DocumentContent(title: 'Safe', text: source),
      scope: scope,
      segments: input,
      cast: known,
      from: spokenStart,
      spoilerCeiling: spokenEnd,
      contextChars: 400,
    );
    expect(window.segments.single.text, speech);
    expect(window.contextExcerpt, setup);
    expect(window.contextExcerpt.contains(earlier), isFalse);
    expect(window.excerpt.contains('FUTURE'), isFalse);
    expect(window.effectiveCeiling, spokenEnd);
  });

  test('reading position cap blocks future incomplete dialogue segment', () {
    const source = 'Anna entered. «Hello!»';
    const intro = 'Anna entered.';
    const quote = '«Hello!»';
    final q = source.indexOf(quote);
    final scope = DialogueAnalysisScope(
      id: 'chapter', title: 'Chapter',
      start: 0, end: source.length,
    );
    expect(() => planner.makeWindow(
      bookId: 'book',
      content: const DocumentContent(title: 'Cutoff', text: source),
      scope: scope,
      segments: [
        const SpeechSegment(0, intro.length, intro),
        SpeechSegment(q, source.length, quote),
      ],
      cast: known,
      from: q,
      spoilerCeiling: q + 3,
      contextChars: 400,
    ), throwsFormatException);
  });

  test('LLM evidence is tied to an exact earlier source substring', () {
    const source = 'Anna entered. «Hello!»';
    const intro = 'Anna entered.';
    const quote = '«Hello!»';
    final q = source.indexOf(quote);
    final window = planner.makeWindow(
      bookId: 'book',
      content: const DocumentContent(title: 'Evidence', text: source),
      scope: DialogueAnalysisScope(
        id: 'scene', title: 'Scene', start: 0, end: source.length,
      ),
      segments: [
        const SpeechSegment(0, intro.length, intro),
        SpeechSegment(q, source.length, quote),
      ],
      cast: known,
      from: q,
      spoilerCeiling: source.length,
      contextChars: 400,
    );
    final sourceGrounded = planner.materializeProposals(
      bookId: 'book', source: source, window: window,
      idPrefix: 'evidence',
      proposals: [const DialogueModelProposal(
        segmentIndex: 0, exactQuote: quote,
        speakerId: 'speaker-1', confidence: 0.86,
        evidenceSegmentIndex: 0, evidenceQuote: intro,
      )],
    );
    expect(sourceGrounded.single.evidence?.start, 0);
    expect(sourceGrounded.single.evidence?.matchesSource(source), isTrue);
    expect(sourceGrounded.single.status, CastSpanStatus.proposed);

    expect(() => planner.materializeProposals(
      bookId: 'book', source: source, window: window,
      idPrefix: 'wrong',
      proposals: [const DialogueModelProposal(
        segmentIndex: 0, exactQuote: quote,
        speakerId: 'speaker-1', confidence: 0.9,
        evidenceSegmentIndex: 0, evidenceQuote: 'Later revelation',
      )],
    ), throwsFormatException);

    expect(() => planner.materializeProposals(
      bookId: 'book', source: source, window: window,
      idPrefix: 'outside',
      proposals: [const DialogueModelProposal(
        segmentIndex: 0, exactQuote: quote,
        speakerId: 'speaker-1', confidence: 0.9,
        evidenceSegmentIndex: 3, evidenceQuote: intro,
      )],
    ), throwsFormatException);
  });

}
