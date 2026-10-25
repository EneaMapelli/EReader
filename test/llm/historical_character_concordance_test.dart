import 'dart:convert';

import 'package:ereader/audio/secret_vault.dart';
import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/domain/llm_analysis_consent.dart';
import 'package:ereader/domain/cast_span.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:ereader/llm/dialogue_analysis_plan.dart';
import 'package:ereader/llm/historical_character_concordance.dart';
import 'package:ereader/llm/historical_character_mention.dart';
import 'package:ereader/llm/openai_dialogue_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = HistoricalCharacterConcordance();
  const planner = DialogueAnalysisPlanner();
  const first = 'Mira entered the hall. Captain Mira closed the gate.';
  const second = 'Anna spoke to the Captain. «Hello!»';
  const future = 'Future chapter reveals Mira was the queen.';
  final full = '$first\n\n$second\n\n$future';
  final firstStart = full.indexOf(first);
  final secondStart = full.indexOf(second);
  final futureStart = full.indexOf(future);
  final ranges = <DialogueAnalysisScope>[
    DialogueAnalysisScope(
      id: 'epub:one', title: 'First chapter',
      start: firstStart, end: firstStart + first.length,
    ),
    DialogueAnalysisScope(
      id: 'epub:two', title: 'Second chapter',
      start: secondStart, end: secondStart + second.length,
    ),
    DialogueAnalysisScope(
      id: 'epub:three', title: 'Third chapter',
      start: futureStart, end: futureStart + future.length,
    ),
  ];
  const mira = CastCharacter(
    id: 'mira', bookId: 'book-1', name: 'Mira',
    aliases: ['Captain Mira'],
  );
  final document = DocumentContent(title: 'Test', text: full);

  DialogueAnalysisWindow target({
    List<CastCharacter> cast = const [mira],
    int? ceiling,
  }) => DialogueAnalysisWindow(
    bookId: 'book-1',
    scope: ranges[1],
    segments: [
      SpeechSegment(secondStart, secondStart + second.length, second),
    ],
    cast: cast,
    spoilerCeiling: ceiling ?? secondStart + second.length,
  );

  test('earlier-chapter mentions contain exact verified book offsets only', () {
    final w = target();
    final history = service.build(
      bookId: w.bookId,
      document: document,
      scopes: ranges,
      window: w,
    );
    expect(history, hasLength(1));
    final mention = history.single;
    expect(mention.characterId, 'mira');
    expect(mention.scopeId, 'epub:one');
    expect(mention.scopeEnd, lessThanOrEqualTo(w.scope.start));
    expect(mention.matchesOriginal(full), isTrue);
    expect(mention.isValidFor(
      selectedScopeId: w.scope.id,
      selectedScopeStart: w.scope.start,
      spoilerCeiling: w.effectiveCeiling,
      allowedCast: w.cast,
    ), isTrue);
    expect(mention.excerpt, isNot(contains('Future chapter')));
    expect(mention.excerpt, isNot(contains('Anna spoke')));
  });

  test('no chosen cast means zero historical data or leaked name', () {
    final w = target(cast: const []);
    expect(service.build(
      bookId: 'book-1', document: document, scopes: ranges, window: w,
    ), isEmpty);
  });

  test('a future chapter and the current chapter can never be history', () {
    final w = target();
    final result = service.build(
      bookId: 'book-1',
      document: document,
      scopes: [ranges[2], ranges[1]],
      window: w,
    );
    expect(result, isEmpty);
  });

  test('source snippet with an emoji never splits a surrogate pair', () {
    const earlier = '😀 Mira was already known. 🐉';
    const now = '«Welcome», said Mira.';
    final source = '$earlier\n\n$now';
    final currentStart = source.indexOf(now);
    final scopes = [
      DialogueAnalysisScope(
        id: 'first', title: 'First',
        start: 0, end: earlier.length,
      ),
      DialogueAnalysisScope(
        id: 'second', title: 'Second',
        start: currentStart, end: source.length,
      ),
    ];
    final w = DialogueAnalysisWindow(
      bookId: 'book-1', scope: scopes[1],
      cast: const [mira],
      segments: [SpeechSegment(currentStart, source.length, now)],
    );
    final history = service.build(
      bookId: 'book-1',
      document: DocumentContent(title: 'Unicode', text: source),
      scopes: scopes, window: w,
    );
    expect(history, hasLength(1));
    final mention = history.single;
    expect(CastSpan.validUtf16Range(
        source, mention.excerptStart, mention.excerptEnd), isTrue);
    expect(mention.matchesOriginal(source), isTrue);
  });

  test('word-boundaries prevent Amira from being misidentified as Mira', () {
    const earlier = 'Amira met someone.';
    const now = 'Mira arrives.';
    final source = '$earlier\n\n$now';
    final start = source.indexOf(now);
    final scopes = [
      DialogueAnalysisScope(
        id: 'earlier', title: 'earlier',
        start: 0, end: earlier.length,
      ),
      DialogueAnalysisScope(
        id: 'current', title: 'current',
        start: start, end: source.length,
      ),
    ];
    final w = DialogueAnalysisWindow(
      bookId: 'book-1',
      scope: scopes.last,
      segments: [SpeechSegment(start, source.length, now)],
      cast: const [mira],
    );
    expect(service.build(
      bookId: 'book-1',
      document: DocumentContent(title: 'Names', text: source),
      scopes: scopes,
      window: w,
    ), isEmpty);
  });

  test('history is bounded in scopes, matches and transmitted characters',
      () {
    final chapters = [for (var i = 0; i < 12; i++)
      'Mira visited site $i. Captain Mira returned.'];
    final source = chapters.join('\n\n');
    var start = 0;
    final scopes = <DialogueAnalysisScope>[];
    for (var i = 0; i < chapters.length; i++) {
      scopes.add(DialogueAnalysisScope(
        id: 'chapter:$i', title: 'Chapter $i',
        start: start, end: start + chapters[i].length,
      ));
      start += chapters[i].length + 2;
    }
    final last = scopes.last;
    final w = DialogueAnalysisWindow(
      bookId: 'book-1', scope: last, cast: const [mira],
      segments: [SpeechSegment(
        last.start, last.end, source.substring(last.start, last.end),
      )],
    );
    final history = service.build(
      bookId: 'book-1',
      document: DocumentContent(title: 'Long', text: source),
      scopes: scopes,
      window: w,
    );
    expect(history.length, lessThanOrEqualTo(
        HistoricalCharacterConcordance.maxMentionsPerPerson));
    expect(history.fold<int>(0, (sum, part) => sum + part.excerpt.length),
      lessThanOrEqualTo(HistoricalCharacterConcordance.maxSentCharacters));
    expect(history.every((part) => part.scopeEnd <= last.start), isTrue);
  });

  test('request contains only selected validated history, with distinct ID',
      () {
    final w = target();
    final mentions = service.build(
      bookId: w.bookId, document: document, scopes: ranges, window: w,
    );
    final selected = DialogueAnalysisWindow(
      bookId: w.bookId, scope: w.scope,
      segments: w.segments, cast: w.cast,
      historicalMentions: mentions,
      spoilerCeiling: w.spoilerCeiling,
    );
    final adapter = OpenAiDialogueAnalyzer(
      access: _NoUseAccess(), vault: _NoUseKey(),
      transport: _NoUseTransport(),
    );
    final request = jsonDecode(adapter.createRequest(selected)) as Map;
    final snippets = request['historical_mentions'] as List;
    expect(snippets, hasLength(1));
    expect(snippets.single['character_id'], 'mira');
    expect(snippets.single['excerpt'], mentions.single.excerpt);
    expect(adapter.createRequest(selected), isNot(contains('queen')));
    expect(adapter.requestedCharacters(selected),
        greaterThan(adapter.requestedCharacters(w)));
    adapter.dispose();
  });

  test('forged previous-chapter excerpt is rejected before HTTP', () {
    final w = target();
    final legitimate = service.build(
      bookId: w.bookId, document: document, scopes: ranges, window: w,
    ).single;
    final forged = HistoricalCharacterMention(
      scopeId: w.scope.id,
      scopeStart: w.scope.start,
      scopeEnd: w.scope.end,
      characterId: legitimate.characterId,
      matchedName: legitimate.matchedName,
      mentionStart: w.scope.start,
      mentionEnd: w.scope.start + 4,
      excerptStart: w.scope.start,
      excerpt: 'Mira',
      sourceDigest: CastSpan.digest('Mira'),
    );
    final bad = DialogueAnalysisWindow(
      bookId: w.bookId, scope: w.scope, cast: w.cast,
      segments: w.segments,
      historicalMentions: [forged],
    );
    final adapter = OpenAiDialogueAnalyzer(
      access: _NoUseAccess(), vault: _NoUseKey(),
      transport: _NoUseTransport(),
    );
    expect(() => adapter.createRequest(bad), throwsFormatException);
    adapter.dispose();
  });

  test('historical passages cannot become dialogue proposal target segments',
      () {
    final w = target();
    final past = service.build(
      bookId: w.bookId, document: document, scopes: ranges, window: w,
    );
    final withHistory = DialogueAnalysisWindow(
      bookId: w.bookId, scope: w.scope,
      segments: w.segments, cast: w.cast,
      historicalMentions: past,
    );
    expect(() => planner.materializeProposals(
      bookId: w.bookId,
      source: full,
      window: withHistory,
      proposals: const [DialogueModelProposal(
        segmentIndex: 1, exactQuote: 'Mira', speakerId: 'mira',
        confidence: 0.8,
      )],
      idPrefix: 'unsafe',
    ), throwsFormatException);
  });
}

/// No network, credential or quota path is executed in these unit tests.
class _NoUseAccess implements LlmAnalysisAccess {
  @override
  LlmAnalysisConsent getLlmAnalysisConsent(String bookId) =>
      LlmAnalysisConsent(
          bookId: bookId, allowed: false, maxInputCharacters: 0,
          usedInputCharacters: 0);
  @override
  Future<void> reserveLlmAnalysisInput(String bookId, int count) =>
      throw StateError('must not debit in a local-only test');
}

class _NoUseKey implements SpeechSecretVault {
  @override
  Future<String?> readKey(String providerId) =>
      throw StateError('must not use credentials');
  @override
  Future<void> saveKey(String providerId, String value) =>
      throw StateError('must not write credentials');
  @override
  Future<void> deleteKey(String providerId) =>
      throw StateError('must not delete credentials');
}

class _NoUseTransport implements DialogueAnalysisTransport {
  @override
  Future<String> request({
    required String apiKey, required String model,
    required String instructions, required String requestJson,
  }) => throw StateError('no network allowed');
  @override
  void dispose() {}
}
