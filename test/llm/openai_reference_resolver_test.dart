import 'dart:convert';

import 'package:ereader/audio/secret_vault.dart';
import 'package:ereader/domain/llm_analysis_consent.dart';
import 'package:ereader/domain/narrative_reference.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:ereader/llm/dialogue_analysis_plan.dart';
import 'package:ereader/llm/openai_dialogue_analyzer.dart';
import 'package:ereader/llm/openai_reference_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

class _Key implements SpeechSecretVault {
  String? value = 'test-key';
  @override
  Future<String?> readKey(String id) async {
    expect(id, OpenAiDialogueAnalyzer.keyNamespace);
    return value;
  }
  @override
  Future<void> saveKey(String id, String value) async { this.value = value; }
  @override
  Future<void> deleteKey(String id) async { value = null; }
}

class _Consent implements LlmAnalysisAccess {
  bool granted = false;
  int count = 0;
  int cap = 30000;
  @override
  LlmAnalysisConsent getLlmAnalysisConsent(String id) =>
      LlmAnalysisConsent(bookId: id, allowed: granted,
        maxInputCharacters: cap, usedInputCharacters: count);
  @override
  Future<void> reserveLlmAnalysisInput(String id, int n) async {
    if (!granted || n > cap - count) {
      throw const LlmAnalysisDenied('Permission denied');
    }
    count += n;
  }
}

class _Transport implements DialogueAnalysisTransport {
  int calls = 0;
  String? sent;
  String json = '{"proposals":[]}';
  @override
  Future<String> request({
    required String apiKey,
    required String model,
    required String instructions,
    required String requestJson,
  }) async {
    expect(apiKey, 'test-key');
    expect(instructions, contains('indirect'));
    calls++;
    sent = requestJson;
    return json;
  }
  @override
  void dispose() {}
}

void main() {
  const source = 'Mira entered. She looked around. The commander waited.';
  const before = 'Mira entered.';
  const target = 'She looked around. The commander waited.';
  final offset = source.indexOf(target);
  const selected = [
    CastCharacter(id: 'mira', bookId: 'book', name: 'Mira'),
    CastCharacter(id: 'anna', bookId: 'book', name: 'Anna'),
  ];
  final scope = DialogueAnalysisScope(
    id: 'scene', title: 'Scene',
    start: 0, end: source.length,
  );
  final window = DialogueAnalysisWindow(
    bookId: 'book', scope: scope,
    contextSegments: [
      SpeechSegment(0, before.length, before),
    ],
    segments: [
      SpeechSegment(offset, source.length, target),
    ],
    cast: selected,
  );

  Map<String, Object?> suggestion(
      String quote, String? who, {int? context = 0,
        String? proof = before}) => {
    'segment_index': 0,
    'exact_quote': quote,
    'speaker_id': who,
    'confidence': 0.66,
    'evidence_segment_index': context,
    'evidence_quote': proof,
  };
  String output(List<Map<String, Object?>> items) =>
      jsonEncode({'proposals': items});

  test('pronoun is exact and review-only, with optional earlier proof', () {
    final items = OpenAiReferenceResolver.parseCandidates(
      jsonResponse: output([suggestion('She', 'mira')]),
      window: window, source: source, idPrefix: 'ref',
    );
    expect(items, hasLength(1));
    expect(items.single.kind, NarrativeReferenceKind.pronoun);
    expect(items.single.start, source.indexOf('She'));
    expect(items.single.proposedCharacterId, 'mira');
    expect(items.single.status, NarrativeReferenceStatus.proposed);
    expect(items.single.approvedCharacterId, isNull);
    expect(items.single.evidence!.matchesSource(source), isTrue);
  });

  test('descriptive reference is not a new alias or speaker label', () {
    final items = OpenAiReferenceResolver.parseCandidates(
      jsonResponse: output([suggestion(
        'The commander', 'anna', context: null, proof: null)]),
      window: window, source: source, idPrefix: 'role',
    );
    expect(items.single.kind, NarrativeReferenceKind.titleOrDescription);
    expect(items.single.referenceText, 'The commander');
    expect(items.single.approvedCharacterId, isNull);
  });

  test('conflicting cast IDs for same pronoun produce unresolved record', () {
    final items = OpenAiReferenceResolver.parseCandidates(
      jsonResponse: output([
        suggestion('She', 'anna'),
        suggestion('She', 'mira'),
      ]),
      window: window, source: source, idPrefix: 'dispute',
    );
    expect(items, hasLength(1));
    expect(items.single.ambiguous, isTrue);
    expect(items.single.proposedCharacterId, isNull);
    expect(items.single.confidence, 0);
    expect(items.single.evidence, isNull);
  });

  test('model cannot invent speaker IDs or quoted source text', () {
    for (final bad in [
      suggestion('She', 'invented'),
      suggestion('She is a queen', 'mira'),
      suggestion('She', 'mira', context: 9),
      suggestion('She', 'mira', proof: 'Future queen'),
    ]) {
      expect(() => OpenAiReferenceResolver.parseCandidates(
        jsonResponse: output([bad]),
        window: window, source: source, idPrefix: 'invalid',
      ), throwsFormatException);
    }
  });

  test('direct names are ignored and repeated target quote is unsafe', () {
    expect(OpenAiReferenceResolver.parseCandidates(
      jsonResponse: output([
        suggestion('Mira', 'mira', context: null, proof: null),
      ]),
      window: window, source: source, idPrefix: 'named',
    ), isEmpty);
    const two = 'She told She that it was over.';
    final w = DialogueAnalysisWindow(
      bookId: 'book',
      scope: const DialogueAnalysisScope(
        id: 'many', title: 'many', start: 0, end: two.length),
      segments: [SpeechSegment(0, two.length, two)],
      cast: selected,
    );
    expect(() => OpenAiReferenceResolver.parseCandidates(
      jsonResponse: output([suggestion(
        'She', 'mira', context: null, proof: null)]),
      window: w, source: two, idPrefix: 'ambiguous',
    ), throwsFormatException);
  });

  test('no consent or credential means no HTTP and no quota', () async {
    final consent = _Consent();
    final transport = _Transport();
    final vault = _Key();
    final resolver = OpenAiReferenceResolver(
      access: consent, vault: vault, transport: transport,
    );
    await expectLater(resolver.resolve(
      window: window, source: source, idPrefix: 'no-consent'),
      throwsA(isA<LlmAnalysisDenied>()));
    expect(transport.calls, 0);
    expect(consent.count, 0);
    consent.granted = true;
    vault.value = null;
    await expectLater(resolver.resolve(
      window: window, source: source, idPrefix: 'no-key'),
      throwsA(isA<LlmAnalysisDenied>()));
    expect(transport.calls, 0);
    expect(consent.count, 0);
    resolver.dispose();
  });

  test('source spoof is rejected before quota reservation', () async {
    final consent = _Consent()..granted = true;
    final network = _Transport();
    final resolver = OpenAiReferenceResolver(
      access: consent, vault: _Key(), transport: network);
    await expectLater(resolver.resolve(
      window: window,
      source: source.replaceFirst('She', 'Her'),
      idPrefix: 'spoof'), throwsFormatException);
    expect(consent.count, 0);
    expect(network.calls, 0);
    resolver.dispose();
  });

  test('single approved window uses existing transport and input budget',
      () async {
    final consent = _Consent()..granted = true;
    final network = _Transport()
      ..json = output([suggestion('She', 'mira')]);
    final resolver = OpenAiReferenceResolver(
      access: consent, vault: _Key(), transport: network);
    final result = await resolver.resolve(
      window: window, source: source, idPrefix: 'ok');
    expect(result.single.referenceText, 'She');
    expect(network.calls, 1);
    expect(network.sent, contains('She looked around'));
    expect(network.sent, isNot(contains('Future chapter')));
    expect(consent.count, resolver.requestedCharacters(window));
    resolver.dispose();
  });
}
