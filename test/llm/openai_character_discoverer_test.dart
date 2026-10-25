import 'dart:convert';

import 'package:ereader/audio/secret_vault.dart';
import 'package:ereader/domain/character_candidate.dart';
import 'package:ereader/domain/llm_analysis_consent.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:ereader/llm/dialogue_analysis_plan.dart';
import 'package:ereader/llm/openai_character_discoverer.dart';
import 'package:ereader/llm/openai_dialogue_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeKeyStore implements SpeechSecretVault {
  String? key = 'test-only-key';
  @override
  Future<String?> readKey(String id) async {
    expect(id, OpenAiDialogueAnalyzer.keyNamespace);
    return key;
  }
  @override
  Future<void> saveKey(String id, String value) async { key = value; }
  @override
  Future<void> deleteKey(String id) async { key = null; }
}

class FakePermission implements LlmAnalysisAccess {
  bool enabled = false;
  int limit = 20000;
  int used = 0;
  @override
  LlmAnalysisConsent getLlmAnalysisConsent(String bookId) =>
      LlmAnalysisConsent(
        bookId: bookId,
        allowed: enabled,
        maxInputCharacters: limit,
        usedInputCharacters: used,
      );
  @override
  Future<void> reserveLlmAnalysisInput(String bookId, int count) async {
    if (!enabled || count > limit - used) {
      throw const LlmAnalysisDenied('No quota');
    }
    used += count;
  }
}

class FakeDiscoveryTransport implements DialogueAnalysisTransport {
  int calls = 0;
  String? instructions;
  String? payload;
  String response = jsonEncode({'proposals': []});

  @override
  Future<String> request({
    required String apiKey,
    required String model,
    required String instructions,
    required String requestJson,
  }) async {
    calls++;
    expect(apiKey, 'test-only-key');
    this.instructions = instructions;
    payload = requestJson;
    return response;
  }
  @override
  void dispose() {}
}

void main() {
  const text = 'Anna saw Mira entering the room. Mira smiled.';
  final scope = DialogueAnalysisScope(
    id: 'book:1', title: 'Selected chapter',
    start: 0, end: text.length,
  );
  final window = DialogueAnalysisWindow(
    bookId: 'book-1',
    scope: scope,
    segments: [
      SpeechSegment(0, 'Anna saw Mira entering the room.'.length,
          'Anna saw Mira entering the room.'),
      SpeechSegment('Anna saw Mira entering the room. '.length,
          text.length, 'Mira smiled.'),
    ],
    cast: const [CastCharacter(id: 'known',
      bookId: 'book-1', name: 'Anna')],
  );

  Map<String, Object?> proposal(
      String name, int segment, {double confidence = 0.8}) => {
    'segment_index': segment,
    'exact_quote': name,
    'speaker_id': null,
    'evidence_segment_index': null,
    'evidence_quote': null,
    'confidence': confidence,
  };

  test('no permission means zero secret reads, quotas or HTTP calls',
      () async {
    final policy = FakePermission();
    final transport = FakeDiscoveryTransport();
    final discoverer = OpenAiCharacterDiscoverer(
      access: policy, vault: FakeKeyStore(), transport: transport);
    await expectLater(discoverer.discover(
      window: window, source: text, idPrefix: 'candidate'),
      throwsA(isA<LlmAnalysisDenied>()),
    );
    expect(transport.calls, 0);
    expect(policy.used, 0);
    discoverer.dispose();
  });

  test('exact source mention creates only a pending candidate', () async {
    final policy = FakePermission()..enabled = true;
    final transport = FakeDiscoveryTransport()
      ..response = jsonEncode({'proposals': [proposal('Mira', 0)]});
    final discoverer = OpenAiCharacterDiscoverer(
      access: policy, vault: FakeKeyStore(), transport: transport);
    final candidates = await discoverer.discover(
      window: window, source: text, idPrefix: 'candidate');
    expect(candidates.single.name, 'Mira');
    expect(candidates.single.status, CharacterCandidateStatus.proposed);
    expect(candidates.single.start, text.indexOf('Mira'));
    expect(candidates.single.matchesSource(text), isTrue);
    expect(transport.calls, 1);
    expect(policy.used, discoverer.requestedCharacters(window));
    expect(transport.instructions, contains('TARGET'));
    discoverer.dispose();
  });

  test('existing names and repeated candidates are skipped', () {
    final result = OpenAiCharacterDiscoverer.parseCandidates(
      jsonResponse: jsonEncode({'proposals': [
        proposal('Anna', 0),
        proposal('Mira', 0),
        proposal('Mira', 1),
      ]}),
      window: window, source: text, idPrefix: 'new',
    );
    expect(result.map((p) => p.name), ['Mira']);
  });

  test('model cannot invent names or insert a speaker assignment', () {
    for (final bad in [
      proposal('Completely Fictional', 0),
      {...proposal('Mira', 0), 'speaker_id': 'new'},
      {...proposal('Mira', 0), 'evidence_quote': 'some context'},
    ]) {
      expect(() => OpenAiCharacterDiscoverer.parseCandidates(
        jsonResponse: jsonEncode({'proposals': [bad]}),
        window: window, source: text, idPrefix: 'new',
      ), throwsFormatException);
    }
  });

  test('missing key does not debit input or issue network calls', () async {
    final policy = FakePermission()..enabled = true;
    final vault = FakeKeyStore()..key = null;
    final transport = FakeDiscoveryTransport();
    final discoverer = OpenAiCharacterDiscoverer(
      access: policy, vault: vault, transport: transport);
    await expectLater(discoverer.discover(
        window: window, source: text, idPrefix: 'new'),
      throwsA(isA<LlmAnalysisDenied>()));
    expect(policy.used, 0);
    expect(transport.calls, 0);
    discoverer.dispose();
  });

  test('source range/cap enforced before sending any text', () {
    final discoverer = OpenAiCharacterDiscoverer(
      access: FakePermission(), vault: FakeKeyStore(),
      transport: FakeDiscoveryTransport());
    final invalidWindow = DialogueAnalysisWindow(
      bookId: 'book-1',
      scope: DialogueAnalysisScope(
        id: 'private', title: 'Partial', start: 0, end: text.length),
      spoilerCeiling: 5,
      segments: window.segments,
      cast: const [],
    );
    expect(() => discoverer.requestedCharacters(invalidWindow),
        throwsFormatException);
    discoverer.dispose();
  });
}
