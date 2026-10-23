import 'dart:convert';

import 'cast_span.dart';

/// The parser prepares local review candidates ONLY. It does not make an LLM
/// request, approve an attribution, alter a book or invoke a TTS provider.
/// The JSON is untrusted data and must match the current text and known cast.
class CastProposalParser {
  const CastProposalParser();

  List<CastSpan> parse({
    required String jsonPayload,
    required String bookId,
    required String sourceText,
    required Set<String> knownSpeakerIds,
    int maxSuggestions = 300,
  }) {
    if (jsonPayload.length > 256 * 1024) {
      throw const FormatException('LLM suggestion response too large');
    }
    final decoded = jsonDecode(jsonPayload);
    if (decoded is! Map || decoded['schema_version'] != 1 ||
        decoded['book_id'] != bookId ||
        decoded['proposals'] is! List) {
      throw const FormatException('Unexpected dialogue annotation schema');
    }
    final suggestions = decoded['proposals'] as List;
    if (suggestions.length > maxSuggestions) {
      throw const FormatException('Too many dialogue proposals');
    }
    final result = <CastSpan>[];
    final identifiers = <String>{};
    for (final item in suggestions) {
      if (item is! Map) {
        throw const FormatException('Invalid dialogue proposal entry');
      }
      final id = item['id'];
      final start = item['start'];
      final end = item['end'];
      final hash = item['source_sha256'];
      final speaker = item['speaker_id'];
      final confidence = item['confidence'];
      if (id is! String || start is! int || end is! int ||
          hash is! String || confidence is! num ||
          (speaker != null && speaker is! String)) {
        throw const FormatException('Invalid suggestion fields');
      }
      if (start < 0 || end <= start || end > sourceText.length) {
        throw const FormatException('Suggestion points outside the book');
      }
      if (speaker != null && !knownSpeakerIds.contains(speaker)) {
        throw const FormatException('LLM invented a speaker ID');
      }
      if (!identifiers.add(id)) {
        throw const FormatException('Duplicate LLM proposal ID');
      }
      final candidate = CastSpan(
        id: id,
        bookId: bookId,
        start: start,
        end: end,
        sourceDigest: hash,
        speakerId: speaker,
        confidence: confidence.toDouble(),
        origin: CastSpanOrigin.llm,
        status: CastSpanStatus.proposed,
        lockedByUser: false,
      );
      candidate.validate();
      if (!candidate.matchesSource(sourceText, (_) => null)) {
        throw const FormatException('Suggestion text fingerprint mismatch');
      }
      result.add(candidate);
    }
    return List.unmodifiable(result);
  }
}
