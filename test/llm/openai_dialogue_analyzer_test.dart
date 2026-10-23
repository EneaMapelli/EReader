import 'dart:convert';
import 'package:ereader/audio/secret_vault.dart';
import 'package:ereader/domain/llm_analysis_consent.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:ereader/llm/dialogue_analysis_plan.dart';
import 'package:ereader/llm/openai_dialogue_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class TestVault implements SpeechSecretVault {
  String? key = 'private-test-key';
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

class TestAccess implements LlmAnalysisAccess {
  bool allowed = false;
  int limit = 30000;
  int used = 0;
  @override
  LlmAnalysisConsent getLlmAnalysisConsent(String bookId) =>
      LlmAnalysisConsent(bookId: bookId, allowed: allowed,
        maxInputCharacters: limit, usedInputCharacters: used);
  @override
  Future<void> reserveLlmAnalysisInput(String bookId, int count) async {
    if (!allowed || used + count > limit) {
      throw const LlmAnalysisDenied('No budget');
    }
    used += count;
  }
}

class TestTransport implements DialogueAnalysisTransport {
  int calls = 0;
  String? requestBody;
  String? responseOverride;
  int status = 0;
  @override
  Future<String> request({
    required String apiKey,
    required String model,
    required String instructions,
    required String requestJson,
  }) async {
    calls++;
    expect(apiKey, 'private-test-key');
    expect(model, 'gpt-5.4-mini');
    requestBody = requestJson;
    return responseOverride ?? jsonEncode({
      'proposals': [
        {'segment_index': 0, 'exact_quote': '«Ciao!»',
          'speaker_id': 'actor', 'confidence': 0.9},
      ]
    });
  }
  @override
  void dispose() {}
}

void main() {
  const excerpt = '«Ciao!»';
  final scope = DialogueAnalysisScope(
    id: 'chapter-one', title: 'First chapter',
    start: 0, end: excerpt.length,
  );
  final window = DialogueAnalysisWindow(
    bookId: 'book', scope: scope,
    segments: [SpeechSegment(0, excerpt.length, excerpt)],
    cast: [const CastCharacter(
        id: 'actor', bookId: 'book', name: 'Anna')],
  );

  test('no network, key read or budget consumption without consent',
      () async {
    final access = TestAccess();
    final transport = TestTransport();
    final analyzer = OpenAiDialogueAnalyzer(
      access: access, vault: TestVault(), transport: transport,
    );
    await expectLater(analyzer.analyze(window), throwsA(
        isA<LlmAnalysisDenied>()));
    expect(transport.calls, 0);
    expect(access.used, 0);
    analyzer.dispose();
  });

  test('approved single window is sent; no other book passages', () async {
    final access = TestAccess()..allowed = true;
    final transport = TestTransport();
    final analyzer = OpenAiDialogueAnalyzer(
      access: access, vault: TestVault(), transport: transport,
    );
    final proposals = await analyzer.analyze(window);
    expect(proposals.single.speakerId, 'actor');
    expect(transport.calls, 1);
    expect(transport.requestBody, contains('«Ciao!»'));
    expect(transport.requestBody, isNot(contains('Other chapter')));
    expect(access.used, analyzer.requestedCharacters(window));
    analyzer.dispose();
  });

  test('missing key forbids requests and leaves input budget untouched',
      () async {
    final access = TestAccess()..allowed = true;
    final vault = TestVault()..key = null;
    final transport = TestTransport();
    final analyzer = OpenAiDialogueAnalyzer(
      access: access, vault: vault, transport: transport);
    await expectLater(analyzer.analyze(window),
        throwsA(isA<LlmAnalysisDenied>()));
    expect(access.used, 0);
    expect(transport.calls, 0);
    analyzer.dispose();
  });

  test('quota is reserved before request; second call can be denied',
      () async {
    final access = TestAccess()..allowed = true;
    final transport = TestTransport();
    final analyzer = OpenAiDialogueAnalyzer(
      access: access, vault: TestVault(), transport: transport);
    access.limit = analyzer.requestedCharacters(window);
    await analyzer.analyze(window);
    await expectLater(analyzer.analyze(window),
        throwsA(isA<LlmAnalysisDenied>()));
    expect(transport.calls, 1);
    analyzer.dispose();
  });

  test('approved prior context is visible and later spoilers never transmitted',
      () async {
    final analyzer = OpenAiDialogueAnalyzer(
      access: TestAccess(), vault: TestVault(),
      transport: TestTransport(),
    );
    const intro = 'Anna spoke earlier';
    const target = '«Ciao!»';
    final begin = intro.length + 1;
    final scoped = DialogueAnalysisWindow(
      bookId: 'book',
      scope: DialogueAnalysisScope(
        id: 'chapter-two', title: 'Chapter two',
        start: 0, end: begin + target.length,
      ),
      segments: [SpeechSegment(begin, begin + target.length, target)],
      contextSegments: [
        SpeechSegment(0, intro.length, intro),
      ],
      cast: [const CastCharacter(id: 'actor',
          bookId: 'book', name: 'Anna')],
      spoilerCeiling: begin + target.length,
    );
    final request = jsonDecode(analyzer.createRequest(scoped)) as Map;
    expect((request['context_segments'] as List).single['text'], intro);
    expect((request['segments'] as List).single['text'], target);
    expect(analyzer.createRequest(scoped), isNot(contains('future secret')));
    analyzer.dispose();
  });

  test('forged later context is rejected before a network call', () {
    final analyzer = OpenAiDialogueAnalyzer(
      access: TestAccess(), vault: TestVault(),
      transport: TestTransport(),
    );
    final bad = DialogueAnalysisWindow(
      bookId: 'book',
      scope: const DialogueAnalysisScope(
          id: 'book', title: 'Selected', start: 0, end: 100),
      segments: [const SpeechSegment(20, 27, '«Ciao!»')],
      contextSegments: [const SpeechSegment(30, 44, 'Future chapter')],
      cast: const [],
      spoilerCeiling: 27,
    );
    expect(() => analyzer.createRequest(bad), throwsFormatException);
    analyzer.dispose();
  });

  test('structured response parses optional evidence fields', () async {
    final access = TestAccess()..allowed = true;
    final fake = TestTransport()
      ..responseOverride = jsonEncode({
        'proposals': [{
          'segment_index': 0,
          'exact_quote': '«Ciao!»',
          'speaker_id': 'actor',
          'confidence': 0.75,
          'evidence_segment_index': 0,
          'evidence_quote': 'Anna spoke earlier',
        }]
      });
    final analyzer = OpenAiDialogueAnalyzer(
        access: access, vault: TestVault(), transport: fake);
    final proposals = await analyzer.analyze(window);
    expect(proposals.single.evidenceSegmentIndex, 0);
    expect(proposals.single.evidenceQuote, 'Anna spoke earlier');
    expect(proposals.single.confidence, 0.75);
    analyzer.dispose();
  });

  test('transport adapter rejects a segment outside approved scope', () {
    final analyzer = OpenAiDialogueAnalyzer(
      access: TestAccess(), vault: TestVault(),
      transport: TestTransport(),
    );
    final invalid = DialogueAnalysisWindow(
      bookId: 'book',
      scope: const DialogueAnalysisScope(
        id: 'first', title: 'Only first chapter',
        start: 0, end: 6,
      ),
      segments: [
        const SpeechSegment(0, 8, '«Ciao!»'),
      ],
      cast: const [],
    );
    expect(() => analyzer.createRequest(invalid), throwsFormatException);
    analyzer.dispose();
  });

  test('Responses API uses store=false and strict JSON schema without tools',
      () async {
    final httpClient = MockClient((request) async {
      expect(request.url.toString(),
          'https://api.openai.com/v1/responses');
      expect(request.headers['authorization'], 'Bearer private-test-key');
      expect(request.body, isNot(contains('private-test-key')));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-5.4-mini');
      expect(body['store'], isFalse);
      expect(body.containsKey('tools'), isFalse);
      final format = (body['text'] as Map)['format'] as Map;
      expect(format['type'], 'json_schema');
      expect(format['strict'], isTrue);
      return http.Response(jsonEncode({
        'status': 'completed',
        'output': [
          {'type': 'message', 'content': [
            {'type': 'output_text', 'text': '{"proposals":[]}'},
          ]}
        ]
      }), 200);
    });
    final client = OpenAiDialogueTransport(client: httpClient);
    final actual = await client.request(
      apiKey: 'private-test-key',
      model: 'gpt-5.4-mini',
      instructions: 'Test system prompt',
      requestJson: '{"segments":[]}',
    );
    expect(jsonDecode(actual), {'proposals': []});
    client.dispose();
    httpClient.close();
  });
}
