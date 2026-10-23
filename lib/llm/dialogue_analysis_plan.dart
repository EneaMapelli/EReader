import '../data/book_decoder.dart';
import '../domain/book.dart';
import '../domain/cast_span.dart';
import '../domain/speech_segment.dart';
import '../domain/voice_cast.dart';

/// A deliberate, local-only choice of source region. Never selects past the
/// chosen EPUB chapter, PDF page or TXT window. Book-wide scans require an
/// explicit higher-level user action and are not enabled by this API.
class DialogueAnalysisScope {
  const DialogueAnalysisScope({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
  });

  final String id;
  final String title;
  final int start;
  final int end;

  int get length => end - start;
}

class DialogueAnalysisWindow {
  const DialogueAnalysisWindow({
    required this.bookId,
    required this.scope,
    required this.segments,
    required this.cast,
  });

  final String bookId;
  final DialogueAnalysisScope scope;
  final List<SpeechSegment> segments;
  final List<CastCharacter> cast;

  String get excerpt => segments.map((s) => s.text).join('\n');
}

class DialogueAnalysisPlanner {
  const DialogueAnalysisPlanner();

  static const maxWindowCharacters = 4200;
  static const maxRosterCharacters = 2400;
  static const maxSegments = 80;

  List<DialogueAnalysisScope> scopes(
      BookFormat format, DocumentContent content) {
    final scopes = <DialogueAnalysisScope>[];
    if (format == BookFormat.epub && content.epubSpineRanges.isNotEmpty) {
      for (final range in content.epubSpineRanges) {
        scopes.add(DialogueAnalysisScope(
          id: 'epub:' + range.idref,
          title: 'Chapter: ' + range.idref,
          start: range.start, end: range.end,
        ));
      }
    } else if (format == BookFormat.pdf &&
        content.pdfPageRanges.isNotEmpty) {
      for (final page in content.pdfPageRanges) {
        scopes.add(DialogueAnalysisScope(
          id: 'pdf:' + page.pageNumber.toString(),
          title: 'Page ' + page.pageNumber.toString(),
          start: page.start, end: page.end,
        ));
      }
    } else {
      for (var start = 0; start < content.text.length;
          start += maxWindowCharacters) {
        final end = (start + maxWindowCharacters)
            .clamp(0, content.text.length).toInt();
        scopes.add(DialogueAnalysisScope(
          id: 'txt:' + start.toString(),
          title: 'Text range ' + (start + 1).toString() + '–' +
              end.toString(),
          start: start, end: end,
        ));
      }
    }
    return scopes.where((scope) =>
        scope.start >= 0 && scope.end > scope.start &&
        scope.end <= content.text.length).toList();
  }

  /// Analyse only the first window within the selected scope at a time.
  /// The UI explicitly shows and advances the chosen window, never
  /// silently sends the rest of a long chapter.
  DialogueAnalysisWindow makeWindow({
    required String bookId,
    required DocumentContent content,
    required DialogueAnalysisScope scope,
    required List<SpeechSegment> segments,
    required List<CastCharacter> cast,
    required int from,
  }) {
    if (from < scope.start || from >= scope.end ||
        scope.end > content.text.length) {
      throw const FormatException('Analysis window outside selected scope');
    }
    final included = <SpeechSegment>[];
    var length = 0;
    for (final segment in segments) {
      if (segment.start < from || segment.end > scope.end) continue;
      if (segment.end <= segment.start) continue;
      if (content.text.substring(segment.start, segment.end) != segment.text) {
        throw const FormatException('Unaligned source segment');
      }
      if (segment.text.length > maxWindowCharacters) {
        throw const FormatException('A source passage exceeds analysis limit');
      }
      final nextLength = length + segment.text.length + 1;
      if (included.length >= maxSegments ||
          (included.isNotEmpty && nextLength > maxWindowCharacters)) {
        break;
      }
      included.add(segment);
      length = nextLength;
    }
    if (included.isEmpty) {
      throw const FormatException('No extracted passages in this scope');
    }
    if (cast.length > 100) {
      throw const FormatException('Cast has too many characters for one request');
    }
    final rosterLength = cast.fold<int>(0, (sum, member) =>
        sum + member.id.length + member.name.length +
            member.aliases.join(', ').length + 4);
    if (rosterLength > maxRosterCharacters) {
      throw const FormatException('Cast roster too large for selected model');
    }
    return DialogueAnalysisWindow(
      bookId: bookId, scope: scope, cast: List.unmodifiable(cast),
      segments: List.unmodifiable(included),
    );
  }

  /// A response can only cite a locally supplied segment ID and a verbatim
  /// substring. Repeated or invented text is rejected, not guessed.
  List<CastSpan> materializeProposals({
    required String bookId,
    required String source,
    required DialogueAnalysisWindow window,
    required List<DialogueModelProposal> proposals,
    required String idPrefix,
  }) {
    final known = {for (final person in window.cast) person.id};
    final result = <CastSpan>[];
    if (proposals.length > 80) {
      throw const FormatException('Too many model speaker suggestions');
    }
    for (var i = 0; i < proposals.length; i++) {
      final candidate = proposals[i];
      if (candidate.segmentIndex < 0 ||
          candidate.segmentIndex >= window.segments.length ||
          candidate.exactQuote.isEmpty || candidate.confidence < 0 ||
          !candidate.confidence.isFinite || candidate.confidence > 1) {
        throw const FormatException('Invalid model segment selection');
      }
      if (candidate.speakerId != null &&
          !known.contains(candidate.speakerId)) {
        throw const FormatException('Unknown speaker proposed by model');
      }
      final segment = window.segments[candidate.segmentIndex];
      final local = segment.text.indexOf(candidate.exactQuote);
      if (local < 0 ||
          segment.text.indexOf(candidate.exactQuote, local + 1) >= 0) {
        throw const FormatException('Model excerpt missing or ambiguous');
      }
      final start = segment.start + local;
      final end = start + candidate.exactQuote.length;
      if (!CastSpan.validUtf16Range(source, start, end) ||
          source.substring(start, end) != candidate.exactQuote) {
        throw const FormatException('Model excerpt is not original text');
      }
      final span = CastSpan(
        id: idPrefix + '-' + i.toString(),
        bookId: bookId,
        start: start, end: end,
        sourceDigest: CastSpan.digest(candidate.exactQuote),
        speakerId: candidate.speakerId,
        confidence: candidate.confidence,
        origin: CastSpanOrigin.llm,
        status: CastSpanStatus.proposed,
        lockedByUser: false,
      );
      span.validate();
      result.add(span);
    }
    return List.unmodifiable(result);
  }
}

/// Internal LLM response; has no authority to change the saved cast.
class DialogueModelProposal {
  const DialogueModelProposal({
    required this.segmentIndex,
    required this.exactQuote,
    required this.speakerId,
    required this.confidence,
  });
  final int segmentIndex;
  final String exactQuote;
  final String? speakerId;
  final double confidence;
}
