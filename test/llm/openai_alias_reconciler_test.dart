import 'dart:convert';

import 'package:ereader/audio/secret_vault.dart';
import 'package:ereader/domain/alias_candidate.dart';
import 'package:ereader/domain/llm_analysis_consent.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:ereader/llm/dialogue_analysis_plan.dart';
import 'package:ereader/llm/openai_alias_reconciler.dart';
import 'package:ereader/llm/openai_dialogue_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAliasKey implements SpeechSecretVault {
  String? key = 'test-key';
  @override
  Future<String?> readKey(String providerId) async {
    expect(providerId, OpenAiDialogueAnalyzer.keyNamespace);
    return key;
  }
  @override
  Future<void> saveKey(String providerId, String value) async { key = value; }
  @override
  Future<void> deleteKey(String providerId) async { key = null; }
}

class FakeAliasConsent implements LlmAnalysisAccess {
  bool allowed = false;
  int quota = 25000;
  int used = 0;
  @override
  LlmAnalysisConsent getLlmAnalysisConsent(String bookId) =>
      LlmAnalysisConsent(bookId: bookId,
        allowed: allowed, maxInputCharacters: quota,
        usedInputCharacters: used);
  @override
  Future<void> reserveLlmAnalysisInput(String bookId, int count) async {
    if (!allowed || quota - used < count) {
      throw const LlmAnalysisDenied('Quota denied');
    }
    used += count;
  }
}

class FakeAliasTransport implements DialogueAnalysisTransport {
  int calls = 0;
  String? payload;
  String response = '{"proposals":[]}';
  @override
  Future<String> request({
    required String apiKey,
    required String model,
    required String instructions,
    required String requestJson,
  }) async {
    expect(apiKey, 'test-key');
    expect(instructions, contains('alternative names'));
    calls++;
    payload = requestJson;
    return response;
  }
  @override
  void dispose() {}
}

void main() {
  const source = 'Mira stood nearby. The Captain waved.';
  const previous = 'Mira stood nearby.';
  const target = 'The Captain waved.';
  final start = source.indexOf(target);
  final window = DialogueAnalysisWindow(
    bookId: 'book',
    scope: DialogueAnalysisScope(
      id: 'chapter', title: 'Current chapter',
      start: 0, end: source.length,
    ),
    contextSegments: [
      SpeechSegment(0, previous.length, previous),
    ],
    segments: [
      SpeechSegment(start, source.length, target),
    ],
    spoilerCeiling: source.length,
    cast: const [CastCharacter(
      id: 'mira', bookId: 'book', name: 'Mira',
      aliases: ['The Navigator'],
    )],
  );

  Map<String, Object?> proposal({
    String alias = 'The Captain',
    String speaker = 'mira',
    int segment = 0,
    int? evidenceIndex = 0,
    String? evidence = 'Mira stood nearby.',
  }) => {
    'segment_index': segment,
    'exact_quote': alias,
    'speaker_id': speaker,
    'confidence': 0.8,
    'evidence_segment_index': evidenceIndex,
    'evidence_quote': evidence,
  };

  String response(List<Map<String, Object?>> suggestions) =>
      jsonEncode({'proposals': suggestions});

  test('default-deny privacy blocks key reads and network', () async {
    final policy = FakeAliasConsent();
    final network = FakeAliasTransport();
    final adapter = OpenAiAliasReconciler(
      access: policy, vault: FakeAliasKey(), transport: network);
    await expectLater(adapter.reconcile(
      window: window, source: source, idPrefix: 'review'),
      throwsA(isA<LlmAnalysisDenied>()),
    );
    expect(network.calls, 0);
    expect(policy.used, 0);
    adapter.dispose();
  });

  test('valid exact nickname creates review-only candidate with evidence',
      () async {
    final policy = FakeAliasConsent()..allowed = true;
    final network = FakeAliasTransport()
      ..response = response([proposal()]);
    final adapter = OpenAiAliasReconciler(
      access: policy, vault: FakeAliasKey(), transport: network);
    final candidates = await adapter.reconcile(
      window: window, source: source, idPrefix: 'review',
    );
    expect(candidates, hasLength(1));
    expect(candidates.single.alias, 'The Captain');
    expect(candidates.single.status, AliasCandidateStatus.proposed);
    expect(candidates.single.targetCharacterId, 'mira');
    expect(candidates.single.evidence?.matchesSource(source), isTrue);
    expect(policy.used, adapter.requestedCharacters(window));
    expect(network.calls, 1);
    expect(network.payload, contains('The Captain waved'));
    adapter.dispose();
  });

  test('same alias proposed for two targets is dropped as ambiguous', () {
    const two = DialogueAnalysisWindow(
      bookId: 'book',
      scope: DialogueAnalysisScope(
        id: 's', title: 's', start: 0, end: 40),
      segments: [SpeechSegment(0, 11, 'The Captain')],
      cast: [
        CastCharacter(id: 'mira', bookId: 'book', name: 'Mira'),
        CastCharacter(id: 'anna', bookId: 'book', name: 'Anna'),
      ],
    );
    final result = OpenAiAliasReconciler.parseCandidates(
      jsonResponse: response([
        proposal(evidenceIndex: null, evidence: null),
        proposal(speaker: 'anna', evidenceIndex: null, evidence: null),
      ]),
      window: two,
      source: 'The Captain',
      idPrefix: 'ambiguous',
    );
    expect(result, isEmpty);
  });

  test('invented target, nonexistent alias and future evidence rejected', () {
    for (final p in [
      proposal(speaker: 'invented'),
      proposal(alias: 'Admiral'),
      proposal(evidenceIndex: 4),
      proposal(evidence: 'Unmentioned historical event'),
    ]) {
      expect(() => OpenAiAliasReconciler.parseCandidates(
        jsonResponse: response([p]),
        window: window, source: source, idPrefix: 'bad',
      ), throwsFormatException);
    }
  });

  test('known name and existing alias are not suggested again', () {
    final result = OpenAiAliasReconciler.parseCandidates(
      jsonResponse: response([
        proposal(alias: 'Mira', evidenceIndex: null, evidence: null),
      ]),
      window: window, source: source, idPrefix: 'skip',
    );
    expect(result, isEmpty);
  });

  test('missing key keeps budget untouched', () async {
    final policy = FakeAliasConsent()..allowed = true;
    final key = FakeAliasKey()..key = null;
    final network = FakeAliasTransport();
    final adapter = OpenAiAliasReconciler(
      access: policy, vault: key, transport: network);
    await expectLater(adapter.reconcile(
      window: window, source: source, idPrefix: 'no-key'),
      throwsA(isA<LlmAnalysisDenied>()));
    expect(network.calls, 0);
    expect(policy.used, 0);
    adapter.dispose();
  });

  test('no future text can enter the request after spoiler ceiling', () {
    final bad = DialogueAnalysisWindow(
      bookId: 'book',
      scope: window.scope,
      contextSegments: window.contextSegments,
      segments: window.segments,
      cast: window.cast,
      spoilerCeiling: start + 4,
    );
    final adapter = OpenAiAliasReconciler(
      access: FakeAliasConsent(), vault: FakeAliasKey(),
      transport: FakeAliasTransport());
    expect(() => adapter.requestedCharacters(bad), throwsFormatException);
    adapter.dispose();
  });
}
