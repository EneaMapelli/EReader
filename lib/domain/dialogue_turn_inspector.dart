import 'cast_span.dart';
import 'reading_anchor.dart';
import 'voice_cast.dart';

enum DialogueTurnFlag {
  unclosedQuote,
  multilineQuote,
  interruptedUtterance,
  adjacentTurn,
  missingAttribution,
  partialAttribution,
  conflictingAttributions,
  explicitNarrator,
  scanBoundary,
}

enum DialogueAttributionState {
  none,
  partial,
  confirmed,
  conflicting,
  narrator,
}

/// Read-only source diagnosis. The inspector never changes the TTS cast.
class DialogueTurnCheck {
  const DialogueTurnCheck({
    required this.start,
    required this.end,
    required this.text,
    required this.closed,
    required this.flags,
    required this.attribution,
    this.speakerId,
  });

  final int start;
  final int end;
  final String text;
  final bool closed;
  final List<DialogueTurnFlag> flags;
  final DialogueAttributionState attribution;
  /// Non-null only when ONE verified speaker covers the whole quoted span.
  final String? speakerId;

  bool matchesSource(String source) =>
      CastSpan.validUtf16Range(source, start, end) &&
      source.substring(start, end) == text;

  bool get needsReview => flags.isNotEmpty;
}

class DialogueTurnReport {
  const DialogueTurnReport({
    required this.turns,
    required this.scannedStart,
    required this.scannedEnd,
    required this.truncated,
  });

  final List<DialogueTurnCheck> turns;
  final int scannedStart;
  final int scannedEnd;
  /// True means a longer scope was deliberately not all inspected.
  final bool truncated;
  int get issues => turns.where((t) => t.needsReview).length;
}

/// Conservative punctuation parser for manual multi-speaker correction.
/// Keeps UTF-16 offsets and recognizes quote boundaries only; it NEVER
/// assumes alternate speakers or propagates a voice to an adjacent turn.
class DialogueTurnInspector {
  const DialogueTurnInspector();

  static const maxScanChars = 24000;
  static const maxTurns = 140;

  DialogueTurnReport inspect({
    required String bookId,
    required String source,
    required int scopeStart,
    required int scopeEnd,
    required List<CastCharacter> characters,
    required List<CastSpan> fineLabels,
    required List<SegmentCastAssignment> legacyLabels,
    required int? Function(ReadingAnchor) offsetFromAnchor,
  }) {
    if (bookId.isEmpty || scopeStart < 0 || scopeEnd > source.length ||
        !CastSpan.validUtf16Range(source, scopeStart, scopeEnd)) {
      throw const FormatException('Invalid dialogue inspection scope');
    }
    final identities = <String>{};
    for (final person in characters) {
      person.validate();
      if (person.bookId != bookId || !identities.add(person.id)) {
        throw const FormatException('Unknown/duplicate cast in inspection');
      }
    }

    var end = scopeEnd;
    var truncated = false;
    if (end - scopeStart > maxScanChars) {
      end = scopeStart + maxScanChars;
      if (end < scopeEnd && end > scopeStart &&
          source.codeUnitAt(end - 1) >= 0xD800 &&
          source.codeUnitAt(end - 1) <= 0xDBFF &&
          source.codeUnitAt(end) >= 0xDC00 &&
          source.codeUnitAt(end) <= 0xDFFF) end--;
      truncated = true;
    }

    // Only existing human-approved, source-exact labels are diagnostic
    // evidence. A pending or stale LLM suggestion is never authoritative.
    final attributions = <({int start, int end, String? speaker})>[];
    void addLabel(int from, int to, String? speaker) {
      if (from < scopeStart || to > end ||
          !CastSpan.validUtf16Range(source, from, to) ||
          (speaker != null && !identities.contains(speaker))) return;
      attributions.add((start: from, end: to, speaker: speaker));
    }
    for (final label in fineLabels) {
      if (label.bookId != bookId ||
          label.status != CastSpanStatus.accepted ||
          !label.lockedByUser ||
          !label.matchesSource(source, offsetFromAnchor)) continue;
      final start = label.resolvedStart(offsetFromAnchor);
      if (start == null) continue;
      addLabel(start, start + label.length, label.speakerId);
    }
    for (final label in legacyLabels) {
      if (label.bookId != bookId ||
          !identities.contains(label.characterId)) continue;
      final start = label.anchor == null
          ? label.start : offsetFromAnchor(label.anchor!);
      if (start == null) continue;
      final to = start + (label.end - label.start);
      if (!CastSpan.validUtf16Range(source, start, to) ||
          SegmentCastAssignment.fingerprint(
              source.substring(start, to)) != label.sourceDigest) continue;
      addLabel(start, to, label.characterId);
    }

    final locations = <({int start, int end, bool closed, bool multiline})>[];
    int? opened;
    int? expectedClose;
    var sawNewline = false;
    var examinedEnd = end;
    for (var i = scopeStart; i < end; i++) {
      if (locations.length >= maxTurns) {
        truncated = true;
        examinedEnd = i;
        break;
      }
      final ch = source.codeUnitAt(i);
      if (expectedClose == null) {
        final closer = _closeFor(ch);
        if (closer == null) continue;
        opened = i;
        expectedClose = closer;
        sawNewline = false;
      } else {
        if (ch == 10 || ch == 13) sawNewline = true;
        if (ch == expectedClose) {
          locations.add((
            start: opened!, end: i + 1,
            closed: true, multiline: sawNewline,
          ));
          opened = null;
          expectedClose = null;
        }
      }
    }
    if (opened != null && locations.length < maxTurns &&
        examinedEnd > opened) {
      locations.add((
        start: opened, end: examinedEnd, closed: false,
        multiline: sawNewline,
      ));
    }

    final results = <DialogueTurnCheck>[];
    for (var i = 0; i < locations.length; i++) {
      final quote = locations[i];
      final flags = <DialogueTurnFlag>[];
      if (!quote.closed) {
        flags.add(truncated
            ? DialogueTurnFlag.scanBoundary
            : DialogueTurnFlag.unclosedQuote);
      }
      if (quote.multiline) flags.add(DialogueTurnFlag.multilineQuote);
      if (_endsInterrupted(source, quote.start, quote.end, quote.closed)) {
        flags.add(DialogueTurnFlag.interruptedUtterance);
      }
      if (i > 0 && quote.start - locations[i - 1].end <= 120) {
        // Review changing turns; even equal/unknown speech labels here
        // cannot make ownership of the next line automatic.
        flags.add(DialogueTurnFlag.adjacentTurn);
      }

      final intersections = <({int start, int end, String? speaker})>[];
      for (final label in attributions) {
        if (label.start >= quote.end || label.end <= quote.start) continue;
        intersections.add((
          start: label.start < quote.start ? quote.start : label.start,
          end: label.end > quote.end ? quote.end : label.end,
          speaker: label.speaker,
        ));
      }
      final kinds = intersections.map((x) => x.speaker).toSet();
      final knownSpeakers = kinds.whereType<String>().toSet();
      final contested = kinds.length > 1;
      final covered = _unionLength([
        for (final label in intersections)
          (start: label.start, end: label.end),
      ]);
      final length = quote.end - quote.start;

      DialogueAttributionState state;
      String? confirmed;
      if (contested) {
        state = DialogueAttributionState.conflicting;
        flags.add(DialogueTurnFlag.conflictingAttributions);
      } else if (intersections.isEmpty) {
        state = DialogueAttributionState.none;
        flags.add(DialogueTurnFlag.missingAttribution);
      } else if (covered < length) {
        state = DialogueAttributionState.partial;
        flags.add(DialogueTurnFlag.partialAttribution);
      } else if (knownSpeakers.isEmpty) {
        state = DialogueAttributionState.narrator;
        flags.add(DialogueTurnFlag.explicitNarrator);
      } else {
        state = DialogueAttributionState.confirmed;
        confirmed = knownSpeakers.single;
      }
      results.add(DialogueTurnCheck(
        start: quote.start, end: quote.end,
        text: source.substring(quote.start, quote.end),
        closed: quote.closed,
        flags: List.unmodifiable(flags),
        attribution: state,
        speakerId: confirmed,
      ));
    }
    return DialogueTurnReport(
      turns: List.unmodifiable(results),
      scannedStart: scopeStart,
      scannedEnd: examinedEnd,
      truncated: truncated,
    );
  }
}

int? _closeFor(int unit) {
  switch (unit) {
    case 0x00ab: return 0x00bb;
    case 0x201c: return 0x201d;
    case 0x0022: return 0x0022;
    default: return null;
  }
}

bool _endsInterrupted(String text, int start, int end, bool closed) {
  final content = text.substring(
    start + 1, closed ? end - 1 : end,
  ).trimRight();
  return content.endsWith('—') || content.endsWith('–') ||
      content.endsWith('…') || content.endsWith('...');
}

int _unionLength(List<({int start, int end})> ranges) {
  if (ranges.isEmpty) return 0;
  ranges.sort((a, b) => a.start.compareTo(b.start));
  var from = ranges.first.start;
  var to = ranges.first.end;
  var total = 0;
  for (var i = 1; i < ranges.length; i++) {
    final next = ranges[i];
    if (next.start > to) {
      total += to - from;
      from = next.start;
      to = next.end;
    } else if (next.end > to) {
      to = next.end;
    }
  }
  return total + to - from;
}
