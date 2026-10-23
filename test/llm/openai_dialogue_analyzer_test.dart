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
    return jsonEncode({
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
  final scope = const DialogueAnalysisScope(
    id: 'chapter-one', title: 'First chapter',
    start: 0, end: excerpt.length,
  );
  final window = DialogueAnalysisWindow(
    bookId: 'book', scope: scope,
    segments: [const SpeechSegment(0, excerpt.length, excerpt)],
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
