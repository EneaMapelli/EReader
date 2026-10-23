import '../domain/cast_span.dart';
import '../domain/reading_anchor.dart';
import '../domain/voice_cast.dart';

enum DialogueDelimiter { guillemets, curlyQuotes, doubleQuotes, dashLine }
enum DialogueEnd { complete, interrupted, openOrTruncated }
enum DialogueLabelState { unknown, confirmed, narrator, conflict }

/// A source-exact subspan; unknown is NEVER an inferred character.
class DialogueLabelPiece {
  const DialogueLabelPiece(this.start, this.end, this.speakerId, this.state);

  final int start;
  final int end;
  final String? speakerId;
  final DialogueLabelState state;
}

/// Review-only unit. Does not affect the player until a separate, explicitly
/// user-approved cast attribution has been saved through the existing editor.
class DialogueReviewTurn {
  const DialogueReviewTurn({
    required this.start,
    required this.end,
    required this.text,
    required this.delimiter,
    required this.ending,
    required this.labels,
  });
  final int start;
  final int end;
  final String text;
  final DialogueDelimiter delimiter;
  final DialogueEnd ending;
  final List<DialogueLabelPiece> labels;

  bool get hasConflicts =>
      labels.any((p) => p.state == DialogueLabelState.conflict);
  bool get hasUnknown =>
      labels.any((p) => p.state == DialogueLabelState.unknown);
  bool get isPartiallyAttributed =>
      labels.any((p) => p.state == DialogueLabelState.confirmed ||
          p.state == DialogueLabelState.narrator) && hasUnknown;
  bool get hasMultipleConfirmedSpeakers => labels
      .where((p) => p.state == DialogueLabelState.confirmed)
      .map((p) => p.speakerId).toSet().length > 1;
  bool get fullyAttributed => labels.isNotEmpty &&
      labels.every((p) => p.state == DialogueLabelState.confirmed ||
          p.state == DialogueLabelState.narrator);
}

/// Inspect local dialogues, changing turns, interruptions and partial tags.
/// Never guesses a speaker, never modifies text and never makes network calls.
class DialogueTurnReviewPlanner {
  const DialogueTurnReviewPlanner();
  static const maxWindowChars = 12000;
  static const maxTurns = 100;

  List<DialogueReviewTurn> build({
    required String bookId,
    required String source,
    required int from,
    required int to,
    required bool reachesScopeEnd,
    required List<CastSpan> precise,
    required List<SegmentCastAssignment> legacy,
    required int? Function(ReadingAnchor) offsetFromAnchor,
  }) {
    if (bookId.isEmpty || to - from > maxWindowChars ||
        (from < to && !CastSpan.validUtf16Range(source, from, to)) ||
        from < 0 || to < from || to > source.length) {
      throw const FormatException('Invalid dialogue review window');
    }

    final approved = <({int from, int to, String? id})>[];
    for (final span in precise) {
      if (span.bookId != bookId || !span.lockedByUser ||
          span.status != CastSpanStatus.accepted) continue;
      final start = span.resolvedStart(offsetFromAnchor);
      if (start == null || start >= to || start + span.length <= from ||
          !span.matchesSource(source, offsetFromAnchor)) continue;
      approved.add((from: start, to: start + span.length, id: span.speakerId));
    }
    for (final mark in legacy) {
      if (mark.bookId != bookId) continue;
      final start = mark.anchor == null
          ? mark.start : offsetFromAnchor(mark.anchor!);
      if (start == null || start >= to ||
          start + mark.end - mark.start <= from) continue;
      final end = start + mark.end - mark.start;
      if (!CastSpan.validUtf16Range(source, start, end) ||
          SegmentCastAssignment.fingerprint(source.substring(start, end)) !=
              mark.sourceDigest) continue;
      approved.add((from: start, to: end, id: mark.characterId));
    }

    var index = from;
    var atLineStart = from == 0 ||
        source.codeUnitAt(from - 1) == 10 ||
        source.codeUnitAt(from - 1) == 13;
    final result = <DialogueReviewTurn>[];

    while (index < to && result.length < maxTurns) {
      final ch = source.codeUnitAt(index);
      if (ch == 10 || ch == 13) {
        atLineStart = true;
        index++;
        continue;
      }
      if (_spacing(ch)) {
        index++;
        continue; // leading whitespace does not change line start
      }
      final delimiter = _opener(ch);
      if (delimiter != null) {
        final close = _closer(ch);
        var finish = index + 1;
        var closed = false;
        while (finish < to) {
          if (source.codeUnitAt(finish) == close) {
            finish++;
            closed = true;
            break;
          }
          finish++;
        }
        final ending = !closed
            ? DialogueEnd.openOrTruncated
            : _interrupted(source.substring(index + 1, finish - 1))
                ? DialogueEnd.interrupted : DialogueEnd.complete;
        result.add(_turn(
          source, index, finish, delimiter, ending, approved));
        index = finish;
        atLineStart = index > 0 &&
            (source.codeUnitAt(index - 1) == 10 ||
             source.codeUnitAt(index - 1) == 13);
        continue;
      }
      if (atLineStart && (ch == 0x2014 || ch == 0x2013)) {
        var finish = index + 1;
        while (finish < to && source.codeUnitAt(finish) != 10 &&
            source.codeUnitAt(finish) != 13) finish++;
        final body = source.substring(index + 1, finish).trimRight();
        final ending = _interrupted(body)
            ? DialogueEnd.interrupted
            : finish == to && !reachesScopeEnd
                ? DialogueEnd.openOrTruncated : DialogueEnd.complete;
        result.add(_turn(source, index, finish,
            DialogueDelimiter.dashLine, ending, approved));
        index = finish;
        atLineStart = true;
        continue;
      }
      atLineStart = false;
      index++;
    }
    return List.unmodifiable(result);
  }

  DialogueReviewTurn _turn(
    String source, int start, int end, DialogueDelimiter delimiter,
    DialogueEnd ending, List<({int from, int to, String? id})> tags,
  ) {
    final edges = <int>{start, end};
    for (final tag in tags) {
      if (tag.from >= end || tag.to <= start) continue;
      edges.add(tag.from.clamp(start, end).toInt());
      edges.add(tag.to.clamp(start, end).toInt());
    }
    final positions = edges.toList()..sort();
    final pieces = <DialogueLabelPiece>[];
    for (var i = 0; i + 1 < positions.length; i++) {
      var a = positions[i];
      var b = positions[i + 1];
      // Do not present spaces as unattributed dialogue: they do not affect
      // TTS speaker assignment, while source positions remain original.
      while (a < b && _spacing(source.codeUnitAt(a))) a++;
      while (b > a && _spacing(source.codeUnitAt(b - 1))) b--;
      if (a >= b) continue;
      final matching = tags.where(
          (tag) => tag.from <= a && tag.to >= b).toList();
      DialogueLabelState state;
      String? speaker;
      if (matching.isEmpty) {
        state = DialogueLabelState.unknown;
      } else if (matching.map((m) => m.id).toSet().length > 1) {
        state = DialogueLabelState.conflict;
      } else {
        speaker = matching.first.id;
        state = speaker == null
            ? DialogueLabelState.narrator : DialogueLabelState.confirmed;
      }
      final current = DialogueLabelPiece(a, b, speaker, state);
      if (pieces.isNotEmpty &&
          pieces.last.end == current.start &&
          pieces.last.state == current.state &&
          pieces.last.speakerId == current.speakerId) {
        final previous = pieces.removeLast();
        pieces.add(DialogueLabelPiece(previous.start, b, speaker, state));
      } else {
        pieces.add(current);
      }
    }
    return DialogueReviewTurn(
      start: start, end: end, text: source.substring(start, end),
      delimiter: delimiter, ending: ending,
      labels: List.unmodifiable(pieces));
  }

  static bool _spacing(int c) => c == 32 || c == 9 || c == 10 ||
      c == 13 || c == 0xA0;
  static DialogueDelimiter? _opener(int c) {
    if (c == 0x00AB) return DialogueDelimiter.guillemets;
    if (c == 0x201C) return DialogueDelimiter.curlyQuotes;
    if (c == 0x0022) return DialogueDelimiter.doubleQuotes;
    return null;
  }
  static int _closer(int c) => c == 0x00AB ? 0x00BB :
      c == 0x201C ? 0x201D : 0x0022;
  static bool _interrupted(String body) {
    final text = body.trimRight();
    return text.endsWith('—') || text.endsWith('–') ||
        text.endsWith('…') || text.endsWith('...');
  }
}
