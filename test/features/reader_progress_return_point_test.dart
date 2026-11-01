import 'package:ereader/features/reader/reader_progress_return_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts empty and only successful, meaningful jumps are recorded', () {
    final history = ReaderProgressReturnPoint();
    expect(history.canReturn, isFalse);
    expect(history.origin, isNull);

    expect(history.recordCommittedJump(
      fromOffset: 250,
      toOffset: 750,
      sourceLength: 1000,
    ), isTrue);
    expect(history.canReturn, isTrue);
    expect(history.origin, 250);

    // Invalid, no-op, and canceled jumps cannot remove an earlier point.
    for (final values in [
      [-1, 750, 1000],
      [250, 1001, 1000],
      [250, 750, 0],
      [250, 250, 1000],
    ]) {
      expect(history.recordCommittedJump(
        fromOffset: values[0],
        toOffset: values[1],
        sourceLength: values[2],
      ), isFalse);
      expect(history.origin, 250);
    }
  });

  test('new confirmed jump replaces earlier return point, never stacks', () {
    final history = ReaderProgressReturnPoint();
    history.recordCommittedJump(
      fromOffset: 100, toOffset: 450, sourceLength: 1000);
    final staleRevision = history.revision;
    history.recordCommittedJump(
      fromOffset: 450, toOffset: 900, sourceLength: 1000);
    expect(history.origin, 450);
    expect(history.consumeIfOrigin(100), isFalse,
        reason: 'A stale async return cannot consume the newer jump');
    expect(history.origin, 450);
    expect(history.consumeIfOrigin(450, expectedRevision: staleRevision), isFalse,
        reason: 'Even the same origin needs a matching jump revision');
    expect(history.consumeIfOrigin(450,
        expectedRevision: history.revision), isTrue);
    expect(history.canReturn, isFalse);
    expect(history.consumeIfOrigin(450), isFalse);
  });

  test('same-origin newer jump defeats a stale return callback', () {
    final history = ReaderProgressReturnPoint();
    history.recordCommittedJump(
      fromOffset: 100, toOffset: 350, sourceLength: 1000);
    final oldRevision = history.revision;
    history.recordCommittedJump(
      fromOffset: 100, toOffset: 750, sourceLength: 1000);
    expect(history.consumeIfOrigin(
        100, expectedRevision: oldRevision), isFalse);
    expect(history.canReturn, isTrue);
    expect(history.consumeIfOrigin(
        100, expectedRevision: history.revision), isTrue);
  });

  test('silent EPUB spine identity survives a percentage jump and return', () {
    final history = ReaderProgressReturnPoint();
    // A cover and a first spoken chapter can both start at UTF-16 offset 0.
    expect(history.recordCommittedJump(
      fromOffset: 0,
      toOffset: 0,
      sourceLength: 100,
      originSpineIdref: 'cover',
      destinationSpineIdref: 'main',
    ), isTrue);
    expect(history.origin, 0);
    expect(history.originSpineIdref, 'cover');
    final revision = history.revision;
    expect(history.consumeIfOrigin(0, expectedRevision: revision), isTrue);
    expect(history.originSpineIdref, isNull);
    expect(history.canReturn, isFalse);
  });

  test('unchanged EPUB destination does not overwrite a prior return', () {
    final history = ReaderProgressReturnPoint();
    expect(history.recordCommittedJump(
      fromOffset: 10,
      toOffset: 40,
      sourceLength: 100,
      originSpineIdref: 'illustration',
    ), isTrue);
    final revision = history.revision;
    expect(history.recordCommittedJump(
      fromOffset: 10,
      toOffset: 10,
      sourceLength: 100,
      originSpineIdref: 'illustration',
      destinationSpineIdref: 'illustration',
    ), isFalse);
    expect(history.origin, 10);
    expect(history.originSpineIdref, 'illustration');
    expect(history.revision, revision);
    expect(history.recordCommittedJump(
      fromOffset: 10,
      toOffset: 20,
      sourceLength: 100,
      originSpineIdref: '',
    ), isFalse);
    history.clear();
    expect(history.originSpineIdref, isNull);
    expect(history.canReturn, isFalse);
  });

  test('a newer visual origin cannot be cleared by stale same-offset return',
      () {
    final history = ReaderProgressReturnPoint();
    history.recordCommittedJump(fromOffset: 0, toOffset: 70,
      sourceLength: 100, originSpineIdref: 'cover');
    final originalRevision = history.revision;
    history.recordCommittedJump(fromOffset: 0, toOffset: 70,
      sourceLength: 100, originSpineIdref: 'illustration');
    expect(history.consumeIfOrigin(0,
      expectedRevision: originalRevision), isFalse);
    expect(history.originSpineIdref, 'illustration');
    expect(history.consumeIfOrigin(0,
      expectedRevision: history.revision), isTrue);
  });

  test('beginning and exact source EOF are valid navigation points', () {
    final history = ReaderProgressReturnPoint();
    expect(history.recordCommittedJump(
      fromOffset: 0, toOffset: 500, sourceLength: 500), isTrue);
    expect(history.consumeIfOrigin(0), isTrue);
    expect(history.recordCommittedJump(
      fromOffset: 500, toOffset: 0, sourceLength: 500), isTrue);
    expect(history.origin, 500);
    history.clear();
    expect(history.origin, isNull);
  });
}
