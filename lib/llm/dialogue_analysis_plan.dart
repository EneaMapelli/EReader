import '../data/book_decoder.dart';
import '../domain/book.dart';
import '../domain/cast_span.dart';
import '../domain/speech_segment.dart';
import '../domain/voice_cast.dart';

/// A user-selected chapter, page or bounded TXT range.
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

/// An immutable request plan. Context is *previous text in the same scope*,
/// never a later chapter or text after the explicit spoiler ceiling.
/// Context text is not a target for model-generated character voice labels.
class DialogueAnalysisWindow {
  const DialogueAnalysisWindow({
    required this.bookId,
    required this.scope,
    required this.segments,
    required this.cast,
    this.contextSegments = const [],
    this.spoilerCeiling,
  });

  final String bookId;
  final DialogueAnalysisScope scope;
  final List<SpeechSegment> segments;
  final List<SpeechSegment> contextSegments;
  final List<CastCharacter> cast;
  final int? spoilerCeiling;

  String get excerpt => segments.map((s) => s.text).join('\n');
  String get contextExcerpt =>
      contextSegments.map((s) => s.text).join('\n');
  int get effectiveCeiling => spoilerCeiling ?? scope.end;
}

class DialogueAnalysisPlanner {
  const DialogueAnalysisPlanner();

  static const maxWindowCharacters = 4200;
  static const maxContextCharacters = 900;
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

  /// Selection always remains within the scope AND user-selected spoiler cap.
  /// Optional context contains only earlier complete source-aligned segments
  /// from this same scope, bounded by maxContextCharacters.
  ///
  /// The caller must consciously advance to the next window; no automatic
  /// full-chapter scan or lookahead occurs here.
  DialogueAnalysisWindow makeWindow({
    required String bookId,
    required DocumentContent content,
    required DialogueAnalysisScope scope,
    required List<SpeechSegment> segments,
    required List<CastCharacter> cast,
    required int from,
    int? spoilerCeiling,
    int contextChars = 0,
  }) {
    final ceiling = spoilerCeiling ?? scope.end;
    if (scope.start < 0 || scope.end > content.text.length ||
        scope.end <= scope.start ||
        ceiling > scope.end || ceiling <= scope.start ||
        from < scope.start || from >= ceiling) {
      throw const FormatException(
          'Analysis window exceeds chosen scope or spoiler limit');
    }
    if (contextChars < 0 || contextChars > maxContextCharacters) {
      throw const FormatException('Previous context exceeds privacy limit');
    }
    if (cast.length > 100) {
      throw const FormatException('Cast has too many characters');
    }
    final rosterLength = cast.fold<int>(0, (sum, member) =>
        sum + member.id.length + member.name.length +
            member.aliases.join(', ').length + 4);
    if (rosterLength > maxRosterCharacters) {
      throw const FormatException('Cast roster exceeds request limit');
    }

    // Reject out-of-order or forged input before sending anything.
    var lastEnd = 0;
    for (final segment in segments) {
      if (segment.start < lastEnd || segment.end > content.text.length ||
          !CastSpan.validUtf16Range(
              content.text, segment.start, segment.end) ||
          content.text.substring(segment.start, segment.end) != segment.text) {
        throw const FormatException('Unaligned or unordered source passage');
      }
      lastEnd = segment.end;
    }

    final included = <SpeechSegment>[];
    var total = 0;
    for (final segment in segments) {
      if (segment.end <= from || segment.start < from) continue;
      if (segment.start >= ceiling || segment.end > ceiling) break;
      if (segment.text.length > maxWindowCharacters) {
        throw const FormatException('A passage exceeds analysis limit');
      }
      final next = total + segment.text.length + 1;
      if (included.length >= maxSegments ||
          (included.isNotEmpty && next > maxWindowCharacters)) break;
      included.add(segment);
      total = next;
    }
    if (included.isEmpty) {
      throw const FormatException('No passages before the spoiler cutoff');
    }

    final earlier = <SpeechSegment>[];
    if (contextChars > 0) {
      var previousSize = 0;
      for (final segment in segments.reversed) {
        if (segment.start < scope.start ||
            segment.end > included.first.start ||
            segment.end > ceiling) continue;
        final next = previousSize + segment.text.length +
            (earlier.isEmpty ? 0 : 1);
        if (next > contextChars) break;
        earlier.add(segment);
        previousSize = next;
      }
      // Restore original book order for context provenance.
      earlier.reverse();
    }
    return DialogueAnalysisWindow(
      bookId: bookId, scope: scope, cast: List.unmodifiable(cast),
      segments: List.unmodifiable(included),
      contextSegments: List.unmodifiable(earlier),
      spoilerCeiling: ceiling,
    );
  }

  /// Model proposes a segment index and an exact quote; app computes offsets.
  /// Evidence is optional but, when supplied, must uniquely match a *prior*
  /// source-aligned context segment from the authorized window.
  List<CastSpan> materializeProposals({
    required String bookId,
    required String source,
    required DialogueAnalysisWindow window,
    required List<DialogueModelProposal> proposals,
    required String idPrefix,
  }) {
    if (window.bookId != bookId) {
      throw const FormatException('Cross-book model proposals rejected');
    }
    final known = {for (final person in window.cast) person.id};
    final result = <CastSpan>[];
    if (proposals.length > 80) {
      throw const FormatException('Too many speaker suggestions');
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
      if (end > window.effectiveCeiling ||
          !CastSpan.validUtf16Range(source, start, end) ||
          source.substring(start, end) != candidate.exactQuote) {
        throw const FormatException('Quoted text is not current source');
      }

      CastSpanEvidence? evidence;
      if (candidate.evidenceSegmentIndex != null ||
          candidate.evidenceQuote != null) {
        final index = candidate.evidenceSegmentIndex;
        final quote = candidate.evidenceQuote;
        if (index == null || quote == null || quote.isEmpty ||
            quote.length > maxContextCharacters ||
            index < 0 || index >= window.contextSegments.length) {
          throw const FormatException('Invalid provenance evidence');
        }
        final prior = window.contextSegments[index];
        final inside = prior.text.indexOf(quote);
        if (inside < 0 || prior.text.indexOf(quote, inside + 1) >= 0) {
          throw const FormatException('Evidence is absent or ambiguous');
        }
        final evidenceStart = prior.start + inside;
        final evidenceEnd = evidenceStart + quote.length;
        if (evidenceEnd > start ||
            !CastSpan.validUtf16Range(source, evidenceStart, evidenceEnd) ||
            source.substring(evidenceStart, evidenceEnd) != quote) {
          throw const FormatException('Evidence is outside previous context');
        }
        evidence = CastSpanEvidence(
          start: evidenceStart,
          end: evidenceEnd,
          sourceDigest: CastSpan.digest(quote),
        );
      }

      final span = CastSpan(
        id: idPrefix + '-' + i.toString(),
        bookId: bookId,
        start: start, end: end,
        sourceDigest: CastSpan.digest(candidate.exactQuote),
        speakerId: candidate.speakerId,
        confidence: candidate.confidence,
        evidence: evidence,
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

class DialogueModelProposal {
  const DialogueModelProposal({
    required this.segmentIndex,
    required this.exactQuote,
    required this.speakerId,
    required this.confidence,
    this.evidenceSegmentIndex,
    this.evidenceQuote,
  });
  final int segmentIndex;
  final String exactQuote;
  final String? speakerId;
  final double confidence;
  final int? evidenceSegmentIndex;
  final String? evidenceQuote;
}
