import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:ereader/audio/reader_media_handler.dart';
import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSpeechEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? waiting;
  Completer<void>? stopGate;
  bool failStop = false;
  int stopCalls = 0;

  @override
  Future<List<SpeechVoice>> listVoices() async => const [];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {}

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) {
    spoken.add(text);
    waiting = Completer<void>();
    return waiting!.future;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (stopGate != null) await stopGate!.future;
    if (failStop) throw StateError('native stop failed');
    finish();
  }

  void finish() {
    if (waiting != null && !waiting!.isCompleted) waiting!.complete();
  }

  @override
  Future<void> dispose() => stop();
}

ReaderPlayer _reader(_FakeSpeechEngine engine) => ReaderPlayer(
  engine: engine,
  segments: const [
    SpeechSegment(0, 5, 'First'),
    SpeechSegment(6, 12, 'Second'),
  ],
  onSegmentStarted: (_) async {},
);

/// Audio transport dispatch is intentionally asynchronous: observe the
/// actual mock-engine call rather than trusting a single microtask turn.
Future<void> _waitForSpoken(_FakeSpeechEngine engine, int length) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (engine.spoken.length >= length) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Expected at least $length spoken clips, got ${engine.spoken}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bind publishes book and transport; unbind removes orphan controls',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book-A', title: 'A Tale');
    expect(handler.hasActiveBook, isTrue);
    expect(handler.ownsPlayer(player), isTrue);
    expect(handler.mediaItem.value?.title, 'A Tale');
    expect(handler.queue.value.single.id, 'book-A');
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.controls, contains(MediaControl.play));
    expect(handler.playbackState.value.systemActions, isEmpty,
        reason: 'TTS chunks have no trustworthy timing for a seek bar');

    handler.detach(player);
    expect(handler.hasActiveBook, isFalse);
    expect(handler.ownsPlayer(player), isFalse);
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.idle);
    expect(handler.playbackState.value.controls, isEmpty);
    await handler.close();
    player.dispose();
  });

  test('remote play returns before book completion and seeks one segment',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    var focused = 0;
    var released = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async { focused++; return true; },
      releaseFocus: () async { released++; },
    );
    handler.attach(player, bookId: 'book', title: 'Book');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First']);
    expect(player.isPlaying, isTrue);
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.controls, contains(MediaControl.pause));

    await handler.skipToNext();
    await Future<void>.delayed(Duration.zero);
    expect(player.currentIndex, 1);
    expect(engine.spoken.last, 'Second');
    await handler.pause();
    expect(player.isPlaying, isFalse);
    expect(focused, 1);
    expect(released, greaterThanOrEqualTo(1));
    await handler.close();
    player.dispose();
  });

  test('Next on final audible segment reaches silent source EOF',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    var focusReleased = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async => true,
      releaseFocus: () async { focusReleased++; },
    );
    handler.attach(player, bookId: 'book', title: 'Book');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    await handler.skipToNext();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First', 'Second']);
    expect(player.currentIndex, 1);

    await handler.skipToNext();
    expect(player.currentIndex, 2);
    expect(player.isPlaying, isFalse);
    expect(player.isSettledIdle, isTrue);
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.completed);
    expect(engine.spoken, ['First', 'Second'],
        reason: 'Last segment must not be replayed when pressing Next');
    await Future<void>.delayed(Duration.zero);
    expect(focusReleased, 1);
    final stopCount = engine.stopCalls;
    await handler.skipToNext();
    expect(player.currentIndex, 2);
    expect(engine.stopCalls, stopCount,
        reason: 'Next at exact EOF requires no additional native Stop');

    // Only an explicit Play restarts the whole book from silent EOF.
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First', 'Second', 'First']);
    expect(player.currentIndex, 0);
    await handler.pause();
    await handler.close();
    player.dispose();
  });

  test('Previous at source EOF selects last audible segment', () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book', title: 'Book');
    await handler.play();
    await _waitForSpoken(engine, 1);
    await handler.skipToNext();
    await _waitForSpoken(engine, 2);
    await handler.skipToNext();
    expect(player.currentIndex, 2);
    expect(player.isSettledIdle, isTrue);
    final stopsAtEof = engine.stopCalls;
    await handler.skipToPrevious();
    expect(player.currentIndex, 1);
    expect(player.isPlaying, isFalse);
    expect(engine.stopCalls, stopsAtEof,
        reason: 'Returning from settled EOF must not send an idle native Stop');
    expect(engine.spoken, ['First', 'Second'],
        reason: 'Moving backwards while idle is not a new Play');
    await handler.play();
    await _waitForSpoken(engine, 3);
    expect(engine.spoken, ['First', 'Second', 'Second']);
    await handler.pause();
    await handler.close();
    player.dispose();
  });

  test('idle source seeks and source EOF do not issue native Stop or Play',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book', title: 'Book');
    expect(player.isSettledIdle, isTrue);
    await player.seekTo(1);
    expect(player.currentIndex, 1);
    await player.seekToSourceEnd();
    expect(player.currentIndex, 2);
    await handler.skipToPrevious();
    expect(player.currentIndex, 1);
    expect(engine.spoken, isEmpty);
    expect(engine.stopCalls, 0,
        reason: 'Unstarted speech must not need native Stop to seek');
    await handler.play();
    await _waitForSpoken(engine, 1);
    expect(engine.spoken.single, 'Second');
    await handler.pause();
    expect(engine.stopCalls, greaterThan(0),
        reason: 'Active audio still must use the real native Stop barrier');
    await handler.close();
    player.dispose();
  });

  test('rapid Next commands accumulate while native Stop is pending',
      () async {
    final engine = _FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 3, 'One'),
        SpeechSegment(4, 7, 'Two'),
        SpeechSegment(8, 13, 'Three'),
        SpeechSegment(14, 18, 'Four'),
      ],
      onSegmentStarted: (_) async {},
    );
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book', title: 'Book');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['One']);
    engine.stopGate = Completer<void>();
    final first = handler.skipToNext();
    final second = handler.skipToNext();
    final third = handler.skipToNext();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['One'],
        reason: 'No new speech before native Stop confirmation');
    engine.stopGate!.complete();
    await Future.wait([first, second, third]);
    await Future<void>.delayed(Duration.zero);
    expect(player.currentIndex, 3);
    expect(engine.spoken, ['One', 'Four']);
    await handler.pause();
    await handler.close();
    player.dispose();
  });

  test('rapid opposing media steps leave only their final target',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book', title: 'Book');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    engine.stopGate = Completer<void>();
    final next = handler.skipToNext();
    final previous = handler.skipToPrevious();
    engine.stopGate!.complete();
    await Future.wait([next, previous]);
    await Future<void>.delayed(Duration.zero);
    expect(player.currentIndex, 0);
    expect(engine.spoken, ['First', 'First']);
    await handler.pause();
    await handler.close();
    player.dispose();
  });

  test('direct reader navigation supersedes pending remote skip target',
      () async {
    final engine = _FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 3, 'One'),
        SpeechSegment(4, 7, 'Two'),
        SpeechSegment(8, 13, 'Three'),
        SpeechSegment(14, 18, 'Four'),
      ],
      onSegmentStarted: (_) async {},
    );
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book', title: 'Book');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    engine.stopGate = Completer<void>();
    final firstRemote = handler.skipToNext();
    final directSeek = player.seekTo(3);
    final secondRemote = handler.skipToPrevious();
    engine.stopGate!.complete();
    await Future.wait([firstRemote, directSeek, secondRemote]);
    await Future<void>.delayed(Duration.zero);
    expect(player.currentIndex, 2);
    expect(engine.spoken, ['One', 'Three'],
        reason: 'A remote press after direct Seek uses direct target intent');
    await handler.pause();
    await handler.close();
    player.dispose();
  });

  test('EPUB transport Next jumps real spine chapters, not sentences',
      () async {
    final engine = _FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 3, 'A1'),
        SpeechSegment(4, 7, 'A2'),
        SpeechSegment(8, 11, 'B1'),
        SpeechSegment(12, 15, 'B2'),
        SpeechSegment(16, 19, 'C1'),
      ],
      onSegmentStarted: (_) async {},
    );
    final visited = <int>[];
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'epub', title: 'EPUB',
        chapterSegmentStarts: [0, 2, 4],
        onRemoteNavigation: visited.add);
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['A1']);

    await handler.skipToNext();
    await Future<void>.delayed(Duration.zero);
    expect(player.currentIndex, 2);
    expect(engine.spoken, ['A1', 'B1']);
    await handler.skipToNext();
    await Future<void>.delayed(Duration.zero);
    expect(player.currentIndex, 4);
    expect(engine.spoken.last, 'C1');
    await handler.skipToNext();
    expect(player.currentIndex, player.segments.length);
    expect(player.isPlaying, isFalse);
    expect(engine.spoken, ['A1', 'B1', 'C1']);
    expect(visited, [2, 4, 5]);
    await handler.close();
    player.dispose();
  });

  test('EPUB Previous restarts current chapter before earlier one',
      () async {
    final engine = _FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 3, 'A1'),
        SpeechSegment(4, 7, 'A2'),
        SpeechSegment(8, 11, 'B1'),
        SpeechSegment(12, 15, 'B2'),
        SpeechSegment(16, 19, 'C1'),
      ],
      onSegmentStarted: (_) async {},
    );
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'epub', title: 'EPUB',
        chapterSegmentStarts: [0, 2, 4]);
    player.currentIndex = 3; // In the middle of the second chapter.
    await handler.skipToPrevious();
    expect(player.currentIndex, 2);
    await handler.skipToPrevious();
    expect(player.currentIndex, 0);
    expect(engine.spoken, isEmpty,
        reason: 'Remote navigation while paused never starts TTS');
    await handler.close();
    player.dispose();
  });

  test('rapid chapter skips compose and silent spine items are omitted',
      () async {
    final engine = _FakeSpeechEngine();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 3, 'A1'),
        SpeechSegment(4, 7, 'A2'),
        SpeechSegment(8, 11, 'B1'),
        SpeechSegment(12, 15, 'B2'),
        SpeechSegment(16, 19, 'C1'),
      ],
      onSegmentStarted: (_) async {},
    );
    final visited = <int>[];
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    // Duplicates represent silent OPF entries pointing to the next
    // audible segment; invalid indices are discarded.
    handler.attach(player, bookId: 'epub', title: 'EPUB',
        chapterSegmentStarts: [4, 2, 2, -1, 6, 0],
        onRemoteNavigation: visited.add);
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    engine.stopGate = Completer<void>();
    final first = handler.skipToNext();
    final next = handler.skipToNext();
    final previous = handler.skipToPrevious();
    engine.stopGate!.complete();
    await Future.wait([first, next, previous]);
    await Future<void>.delayed(Duration.zero);
    expect(player.currentIndex, 2);
    expect(engine.spoken, ['A1', 'B1']);
    expect(visited, [2],
        reason: 'Only the winning remote chapter position is published');
    await handler.pause();
    await handler.close();
    player.dispose();
  });

  test('reopening a TXT book clears previous EPUB chapter navigation',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'epub', title: 'EPUB',
        chapterSegmentStarts: [0, 1]);
    handler.detach(player);
    handler.attach(player, bookId: 'txt', title: 'Plain text');
    await handler.skipToNext();
    expect(player.currentIndex, 1);
    await handler.skipToPrevious();
    expect(player.currentIndex, 0);
    expect(engine.spoken, isEmpty);
    await handler.close();
    player.dispose();
  });

  test('lock-screen Play cannot bypass book cloud consent', () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    var focusRequested = false;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusRequested = true;
      return true;
    });
    handler.attach(player,
      bookId: 'private', title: 'Private book',
      canStart: () async => false,
    );
    await expectLater(handler.play(), throwsStateError);
    expect(focusRequested, isFalse);
    expect(engine.spoken, isEmpty);
    expect(player.isPlaying, isFalse);
    await handler.close();
    player.dispose();
  });

  test('focus denial and pending focus superseded by Pause never speak',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final denied = ReaderMediaHandler(requestFocus: () async => false);
    denied.attach(player, bookId: 'b', title: 'B');
    await expectLater(denied.play(), throwsStateError);
    expect(engine.spoken, isEmpty);
    await denied.close();

    final focusGate = Completer<bool>();
    final pending = ReaderMediaHandler(requestFocus: () => focusGate.future);
    pending.attach(player, bookId: 'b', title: 'B');
    final remotePlay = pending.play();
    await Future<void>.delayed(Duration.zero);
    final pausing = pending.pause();
    focusGate.complete(true);
    await Future.wait([remotePlay, pausing]);
    expect(engine.spoken, isEmpty,
        reason: 'A late focus grant must not reverse a newer Pause');
    await pending.close();
    player.dispose();
  });

  test('old Android focus exception after book handoff is ignored',
      () async {
    final oldEngine = _FakeSpeechEngine();
    final newEngine = _FakeSpeechEngine();
    final old = _reader(oldEngine);
    final next = _reader(newEngine);
    final focusGate = Completer<bool>();
    var requests = 0;
    final handler = ReaderMediaHandler(requestFocus: () {
      requests++;
      return requests == 1
          ? focusGate.future : Future<bool>.value(true);
    });
    handler.attach(old, bookId: 'old', title: 'Previous book');
    final obsolete = handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);

    handler.attach(next, bookId: 'new', title: 'Current book');
    final current = handler.play();
    focusGate.completeError(StateError('obsolete Android focus failure'));
    await Future.wait([obsolete, current]);
    await _waitForSpoken(newEngine, 1);

    expect(oldEngine.spoken, isEmpty);
    expect(newEngine.spoken, ['First']);
    expect(handler.mediaItem.value?.id, 'new');
    expect(handler.ownsPlayer(next), isTrue);
    expect(requests, 2);
    await handler.pause();
    await handler.close();
    old.dispose();
    next.dispose();
  });

  test('a focus exception after a newer Pause does not revive old Play',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final gate = Completer<bool>();
    final handler = ReaderMediaHandler(requestFocus: () => gate.future);
    handler.attach(player, bookId: 'book', title: 'Book');
    final stalePlay = handler.play();
    await Future<void>.delayed(Duration.zero);
    final pausing = handler.pause();
    gate.completeError(StateError('obsolete focus failure'));
    await Future.wait([stalePlay, pausing]);

    expect(engine.spoken, isEmpty);
    expect(player.isSettledIdle, isTrue);
    await handler.close();
    player.dispose();
  });

  test('current Android focus exception still reaches active Play',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async =>
        throw StateError('current Android focus failure'));
    handler.attach(player, bookId: 'book', title: 'Book');
    await expectLater(handler.play(), throwsStateError);
    expect(engine.spoken, isEmpty);
    expect(player.isPlaying, isFalse);
    await handler.close();
    player.dispose();
  });

  test('old remote Seek failure after book replacement is not reported',
      () async {
    final oldEngine = _FakeSpeechEngine();
    final newEngine = _FakeSpeechEngine();
    final old = _reader(oldEngine);
    final next = _reader(newEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(old, bookId: 'old', title: 'Previous book');
    await handler.play();
    await _waitForSpoken(oldEngine, 1);

    oldEngine.stopGate = Completer<void>();
    oldEngine.failStop = true;
    final obsoleteSkip = handler.skipToNext();
    handler.attach(next, bookId: 'new', title: 'Current book');
    oldEngine.stopGate!.complete();
    await obsoleteSkip;

    expect(handler.mediaItem.value?.id, 'new');
    expect(handler.ownsPlayer(next), isTrue);
    expect(newEngine.spoken, isEmpty);
    await expectLater(handler.play(), throwsStateError);
    expect(newEngine.spoken, isEmpty,
        reason: 'An unconfirmed old native Stop blocks the new session');
    oldEngine.failStop = false;
    await handler.close();
    old.dispose();
    next.dispose();
  });

  test('current remote Seek failure is not swallowed', () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book', title: 'Book');
    await handler.play();
    await _waitForSpoken(engine, 1);
    engine.failStop = true;
    await expectLater(handler.skipToNext(), throwsStateError);
    expect(handler.ownsPlayer(player), isTrue);
    expect(player.nativeStopUnconfirmed, isTrue);
    engine.failStop = false;
    await handler.close();
    player.dispose();
  });

  test('focus reacquisition waits for an earlier native release', () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final releaseGate = Completer<void>();
    var releases = 0;
    var focusRequests = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async { focusRequests++; return true; },
      releaseFocus: () {
        releases++;
        if (releases == 1) return releaseGate.future;
        return Future<void>.value();
      },
    );
    handler.attach(player, bookId: 'b', title: 'B');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(focusRequests, 1);
    expect(engine.spoken, ['First']);

    final pausing = handler.pause();
    await Future<void>.delayed(Duration.zero);
    expect(releases, 1);
    final pendingPlay = handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(focusRequests, 1,
        reason: 'New focus cannot be granted before native release finishes');

    releaseGate.complete();
    await Future.wait([pausing, pendingPlay]);
    await Future<void>.delayed(Duration.zero);
    expect(focusRequests, 2);
    expect(engine.spoken.last, 'First');
    await handler.pause();
    await handler.close();
    player.dispose();
  });

  test('late focus grant is released after a superseding Pause', () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final granted = Completer<bool>();
    var released = 0;
    var acquired = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async {
        acquired++;
        return granted.future;
      },
      releaseFocus: () async { released++; },
    );
    handler.attach(player, bookId: 'b', title: 'Book');
    final playing = handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(acquired, 1);
    final stopping = handler.pause();
    granted.complete(true);
    await Future.wait([playing, stopping]);
    expect(player.isPlaying, isFalse);
    expect(engine.spoken, isEmpty);
    expect(released, 1,
        reason: 'A late focus grant must be released exactly once');
    await handler.close();
    player.dispose();
  });

  test('direct reader Pause blocks the replacement book until native Stop',
      () async {
    final firstEngine = _FakeSpeechEngine();
    final secondEngine = _FakeSpeechEngine();
    final first = _reader(firstEngine);
    final second = _reader(secondEngine);
    var focusClaims = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusClaims++;
      return true;
    });
    handler.attach(first, bookId: 'first', title: 'First book');
    await handler.play();
    await _waitForSpoken(firstEngine, 1);
    expect(focusClaims, 1);

    firstEngine.stopGate = Completer<void>();
    // Pause is issued directly by ReaderScreen, bypassing the handler.
    final directPause = first.pause();
    handler.attach(second, bookId: 'second', title: 'Second book');
    final newPlay = handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(secondEngine.spoken, isEmpty);
    expect(focusClaims, 1);

    firstEngine.stopGate!.complete();
    await Future.wait([directPause, newPlay]);
    await _waitForSpoken(secondEngine, 1);
    expect(secondEngine.spoken, ['First']);
    expect(handler.mediaItem.value?.id, 'second');
    await handler.pause();
    await handler.close();
    first.dispose();
    second.dispose();
  });

  test('failed direct Pause cannot be bypassed by replacing the book',
      () async {
    final firstEngine = _FakeSpeechEngine();
    final secondEngine = _FakeSpeechEngine();
    final first = _reader(firstEngine);
    final second = _reader(secondEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(first, bookId: 'first', title: 'First');
    await handler.play();
    await _waitForSpoken(firstEngine, 1);

    firstEngine.stopGate = Completer<void>();
    firstEngine.failStop = true;
    final directPause = first.pause();
    handler.attach(second, bookId: 'second', title: 'Second');
    final attemptedPlay = handler.play();
    firstEngine.stopGate!.complete();

    await expectLater(directPause, throwsStateError);
    await expectLater(attemptedPlay, throwsStateError);
    expect(secondEngine.spoken, isEmpty);
    expect(handler.ownsPlayer(second), isTrue);
    expect(handler.mediaItem.value?.id, 'second');
    firstEngine.failStop = false;
    await handler.close();
    first.dispose();
    second.dispose();
  });

  test('replacing a playing book explicitly stops its previous engine',
      () async {
    final firstEngine = _FakeSpeechEngine();
    final secondEngine = _FakeSpeechEngine();
    final first = _reader(firstEngine);
    final second = _reader(secondEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(first, bookId: 'first', title: 'First');
    await handler.play();
    await _waitForSpoken(firstEngine, 1);
    firstEngine.stopGate = Completer<void>();

    // No explicit Pause: replacing the media binding itself cancels
    // the outgoing player's audio before the new book can speak.
    handler.attach(second, bookId: 'second', title: 'Second');
    expect(first.isPlaying, isFalse);
    final nextPlay = handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(secondEngine.spoken, isEmpty);

    firstEngine.stopGate!.complete();
    await nextPlay;
    await _waitForSpoken(secondEngine, 1);
    expect(secondEngine.spoken, ['First']);
    await handler.pause();
    await handler.close();
    first.dispose();
    second.dispose();
  });

  test('replacing a book cancels a pending direct Seek auto-resume',
      () async {
    final firstEngine = _FakeSpeechEngine();
    final secondEngine = _FakeSpeechEngine();
    final first = _reader(firstEngine);
    final second = _reader(secondEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(first, bookId: 'first', title: 'First');
    await handler.play();
    await _waitForSpoken(firstEngine, 1);

    firstEngine.stopGate = Completer<void>();
    final pendingSeek = first.seekTo(1);
    expect(first.isPlaying, isFalse,
        reason: 'A native Stop can hide a latent Seek auto-resume');
    handler.attach(second, bookId: 'second', title: 'Second');
    final newPlay = handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(secondEngine.spoken, isEmpty);

    firstEngine.stopGate!.complete();
    await Future.wait([pendingSeek, newPlay]);
    await _waitForSpoken(secondEngine, 1);
    expect(firstEngine.spoken, ['First'],
        reason: 'Old reader cannot auto-resume after losing media ownership');
    expect(secondEngine.spoken, ['First']);
    await handler.pause();
    await handler.close();
    first.dispose();
    second.dispose();
  });

  test('new book waits for previous native Stop before requesting focus',
      () async {
    final oldEngine = _FakeSpeechEngine();
    final newEngine = _FakeSpeechEngine();
    final oldPlayer = _reader(oldEngine);
    final newPlayer = _reader(newEngine);
    var focusRequests = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusRequests++;
      return true;
    });
    handler.attach(oldPlayer, bookId: 'old', title: 'Old book');
    await handler.play();
    await _waitForSpoken(oldEngine, 1);
    expect(focusRequests, 1);

    oldEngine.stopGate = Completer<void>();
    final removing = handler.onTaskRemoved();
    handler.attach(newPlayer, bookId: 'new', title: 'New book');
    final newPlay = handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(newEngine.spoken, isEmpty,
        reason: 'Never overlap native TTS across book handoff');
    expect(focusRequests, 1,
        reason: 'Even focus acquisition waits until old Stop is confirmed');

    oldEngine.stopGate!.complete();
    await Future.wait([removing, newPlay]);
    await _waitForSpoken(newEngine, 1);
    expect(newEngine.spoken, ['First']);
    expect(focusRequests, 2);
    expect(handler.mediaItem.value?.id, 'new');
    await handler.pause();
    await handler.close();
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('failed old native Stop blocks playback in replacement book',
      () async {
    final oldEngine = _FakeSpeechEngine();
    final newEngine = _FakeSpeechEngine();
    final oldPlayer = _reader(oldEngine);
    final newPlayer = _reader(newEngine);
    var focusRequests = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusRequests++;
      return true;
    });
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _waitForSpoken(oldEngine, 1);
    oldEngine.stopGate = Completer<void>();
    oldEngine.failStop = true;

    final removing = handler.onTaskRemoved();
    handler.attach(newPlayer, bookId: 'new', title: 'New');
    final newPlay = handler.play();
    oldEngine.stopGate!.complete();

    await expectLater(removing, throwsStateError);
    await expectLater(newPlay, throwsStateError);
    expect(handler.ownsPlayer(newPlayer), isTrue,
        reason: 'Stop failure must not detach the replacement book');
    expect(handler.mediaItem.value?.id, 'new');
    expect(newEngine.spoken, isEmpty);
    expect(focusRequests, 1,
        reason: 'New session cannot acquire focus after unconfirmed Stop');
    oldEngine.failStop = false;
    await handler.close();
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('new Play waits for old remote skip Stop during book handoff',
      () async {
    final oldEngine = _FakeSpeechEngine();
    final newEngine = _FakeSpeechEngine();
    final oldPlayer = _reader(oldEngine);
    final newPlayer = _reader(newEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _waitForSpoken(oldEngine, 1);

    oldEngine.stopGate = Completer<void>();
    final obsoleteSkip = handler.skipToNext();
    handler.attach(newPlayer, bookId: 'new', title: 'New');
    final newPlay = handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(newEngine.spoken, isEmpty);

    oldEngine.stopGate!.complete();
    await Future.wait([obsoleteSkip, newPlay]);
    await _waitForSpoken(newEngine, 1);
    expect(newEngine.spoken, ['First']);
    expect(handler.mediaItem.value?.id, 'new');
    await handler.pause();
    await handler.close();
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('late successful task removal does not detach a newly opened book',
      () async {
    final oldEngine = _FakeSpeechEngine();
    final newEngine = _FakeSpeechEngine();
    final oldPlayer = _reader(oldEngine);
    final newPlayer = _reader(newEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old-book', title: 'Previous book');
    await handler.play();
    await _waitForSpoken(oldEngine, 1);

    // Android task cleanup begins stopping the old book, but the native
    // Stop does not acknowledge completion before another book opens.
    oldEngine.stopGate = Completer<void>();
    final cleanup = handler.onTaskRemoved();
    expect(oldPlayer.isPlaying, isFalse);
    handler.attach(newPlayer, bookId: 'new-book', title: 'Current book');
    oldEngine.stopGate!.complete();
    await cleanup;

    expect(handler.ownsPlayer(oldPlayer), isFalse);
    expect(handler.ownsPlayer(newPlayer), isTrue,
        reason: 'Obsolete cleanup must not detach the new MediaSession');
    expect(handler.mediaItem.value?.id, 'new-book');
    expect(handler.queue.value.single.id, 'new-book');
    expect(newEngine.spoken, isEmpty);
    // The new reader must retain working lock-screen playback controls.
    await handler.play();
    await _waitForSpoken(newEngine, 1);
    expect(newEngine.spoken, ['First']);
    await handler.pause();
    await handler.close();
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('failed old native Stop cannot erase a replacement media session',
      () async {
    final oldEngine = _FakeSpeechEngine();
    final oldPlayer = _reader(oldEngine);
    final newPlayer = _reader(_FakeSpeechEngine());
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _waitForSpoken(oldEngine, 1);
    oldEngine.stopGate = Completer<void>();
    oldEngine.failStop = true;

    final cleanup = handler.onTaskRemoved();
    handler.attach(newPlayer, bookId: 'new', title: 'New');
    oldEngine.stopGate!.complete();
    await expectLater(cleanup, throwsStateError);

    expect(handler.ownsPlayer(newPlayer), isTrue);
    expect(handler.mediaItem.value?.id, 'new');
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.ready,
        reason: 'Old speech failure must not poison a new player');
    oldEngine.failStop = false;
    await handler.close();
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('old task removal does not detach a player rebound during Stop',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'before', title: 'Previous binding');
    await handler.play();
    await _waitForSpoken(engine, 1);
    engine.stopGate = Completer<void>();
    final cleanup = handler.onTaskRemoved();

    // Binding epoch, not only player identity, distinguishes a new
    // attachment of the same player from the old media session.
    handler.attach(player, bookId: 'after', title: 'Reattached binding');
    engine.stopGate!.complete();
    await cleanup;
    expect(handler.ownsPlayer(player), isTrue);
    expect(handler.mediaItem.value?.id, 'after');
    await handler.close();
    player.dispose();
  });

  test('task removal stops and clears the media session', () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book', title: 'Book');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isTrue);
    await handler.onTaskRemoved();
    expect(player.isPlaying, isFalse);
    expect(handler.hasActiveBook, isFalse);
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.idle);
    await handler.close();
    player.dispose();
  });

  test('task removal detaches even if native stop throws', () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'b', title: 'B');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    engine.failStop = true;
    await expectLater(handler.onTaskRemoved(), throwsStateError);
    expect(handler.hasActiveBook, isFalse);
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.controls, isEmpty);
    // A stale reader can no longer start a new book through this handler.
    expect(handler.ownsPlayer(player), isFalse);
    engine.failStop = false;
    await handler.close();
    player.dispose();
  });

  test('notification removal pauses without forcing a new play', () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book', title: 'Book');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    await handler.onNotificationDeleted();
    expect(player.isPlaying, isFalse);
    expect(engine.spoken, ['First']);
    expect(handler.hasActiveBook, isTrue);
    await handler.close();
    player.dispose();
  });

  test('idle interrupted focus acquisition cancels Play without native Stop',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final granted = Completer<bool>();
    var releases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () => granted.future,
      releaseFocus: () async { releases++; },
    );
    handler.attach(player, bookId: 'b', title: 'B');
    final pendingPlay = handler.play();
    await Future<void>.delayed(Duration.zero);
    final interruption = handler.pauseForSystemInterruption();
    // Idle player cannot require native Stop, but focus granted later
    // still has to be relinquished before the interruption resolves.
    granted.complete(true);
    await Future.wait([pendingPlay, interruption]);
    expect(engine.spoken, isEmpty);
    expect(engine.stopCalls, 0);
    expect(releases, 1);
    expect(player.isSettledIdle, isTrue);
    await handler.close();
    player.dispose();
  });

  test('repeated system interruptions share one Stop and preserve cursor',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'b', title: 'B');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First']);
    engine.stopGate = Completer<void>();
    final first = handler.pauseForSystemInterruption();
    final duplicate = handler.pauseForSystemInterruption();
    expect(identical(first, duplicate), isTrue,
        reason: 'Repeated phone/audio focus events share one Stop Future');
    await Future<void>.delayed(Duration.zero);
    expect(engine.stopCalls, 1);
    expect(player.isSettledIdle, isFalse);
    expect(player.currentIndex, 0);
    engine.stopGate!.complete();
    await Future.wait([first, duplicate]);
    expect(engine.stopCalls, 1);
    expect(player.isSettledIdle, isTrue);
    expect(engine.spoken, ['First'],
        reason: 'Focus regained never automatically synthesizes a clip');
    await handler.close();
    player.dispose();
  });

  test('duplicate interruption cancels a newer Play waiting for focus',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final laterFocus = Completer<bool>();
    var focusCalls = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () {
        focusCalls++;
        if (focusCalls == 1) return Future<bool>.value(true);
        return laterFocus.future;
      },
    );
    handler.attach(player, bookId: 'b', title: 'B');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    engine.stopGate = Completer<void>();
    final first = handler.pauseForSystemInterruption();
    // The new Play is queued after focus release, so it is cancellable
    // by a second noisy/phone event while the native Stop still runs.
    final laterPlay = handler.play();
    handler.pauseForSystemInterruption();
    engine.stopGate!.complete();
    laterFocus.complete(true);
    await Future.wait([first, laterPlay]);
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First']);
    expect(engine.stopCalls, 1);
    expect(player.currentIndex, 0);
    await handler.close();
    player.dispose();
  });

  test('repeated interruption cancels direct Play during prior Stop',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'b', title: 'B');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First']);

    // First phone event pauses but native Stop has not confirmed yet.
    engine.stopGate = Completer<void>();
    final first = handler.pauseForSystemInterruption();
    expect(player.isPlaying, isFalse);
    // A direct UI Play can bypass handler._commandEpoch and queue speech
    // after the pending native Stop. A repeated phone event must cancel it.
    final restarted = player.play();
    expect(player.isPlaying, isTrue);
    final second = handler.pauseForSystemInterruption();
    expect(identical(first, second), isFalse,
        reason: 'New direct user action requires a fresh Pause');
    final duplicate = handler.pauseForSystemInterruption();
    expect(identical(second, duplicate), isTrue,
        reason: 'No further control changes: share the new Stop');
    expect(player.isPlaying, isFalse);
    engine.stopGate!.complete();
    await Future.wait([first, second, duplicate, restarted]);
    expect(engine.spoken, ['First'],
        reason: 'An interrupted direct Play must not later synthesize');
    expect(engine.stopCalls, 2,
        reason: 'The second interruption reasserts Stop just once');
    expect(player.isSettledIdle, isTrue);
    await handler.close();
    player.dispose();
  });

  test('repeated interruption cancels direct navigation and Play',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'b', title: 'B');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    engine.stopGate = Completer<void>();
    final first = handler.pauseForSystemInterruption();
    // Start a new UI navigation that will queue a Play when Stop releases.
    final newPlay = player.play();
    final seek = player.seekTo(1);
    expect(player.isPlaying, isFalse);
    final second = handler.pauseForSystemInterruption();
    engine.stopGate!.complete();
    await Future.wait([first, second, newPlay, seek]);
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First']);
    expect(player.isPlaying, isFalse);
    expect(player.isSettledIdle, isTrue);
    await handler.close();
    player.dispose();
  });

  test('system interruption pauses without automatic resume', () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'b', title: 'B');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isTrue);

    handler.handleSystemInterruption();
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    expect(player.currentIndex, 0);
    expect(engine.spoken, ['First']);
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First'],
        reason: 'Audio focus recovery never auto-synthesizes more text');
    await handler.close();
    player.dispose();
  });

  test('incoming call during in-flight seek cancels latent audio resume',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'b', title: 'B');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First']);

    engine.stopGate = Completer<void>();
    final seeking = player.seekTo(1);
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    // The player is already marked paused, but its outstanding seek would
    // otherwise resume once the native stop finishes.
    handler.handleSystemInterruption();
    engine.stopGate!.complete();
    await seeking;
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    expect(engine.spoken, ['First']);
    await handler.close();
    player.dispose();
  });

  test('seek keeps focus during native stop and resumes original session',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    var releases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async => true,
      releaseFocus: () async { releases++; },
    );
    handler.attach(player, bookId: 'b', title: 'B');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    engine.stopGate = Completer<void>();
    final seeking = handler.skipToNext();
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    expect(player.isSettledIdle, isFalse);
    expect(releases, 0,
        reason: 'Do not drop Android focus during an in-flight seek');

    engine.stopGate!.complete();
    await seeking;
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isTrue);
    expect(engine.spoken.last, 'Second');
    expect(releases, 0);
    await handler.pause();
    expect(releases, 1);
    await handler.close();
    player.dispose();
  });

  test('direct player Pause releases Android focus after native stop',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    var releases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async => true,
      releaseFocus: () async { releases++; },
    );
    handler.attach(player, bookId: 'b', title: 'B');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    engine.stopGate = Completer<void>();
    final pausing = player.pause();
    await Future<void>.delayed(Duration.zero);
    expect(player.isSettledIdle, isFalse);
    expect(releases, 0,
        reason: 'Focus must be held until the native speech stop finishes');
    engine.stopGate!.complete();
    await pausing;
    await Future<void>.delayed(Duration.zero);
    expect(player.isSettledIdle, isTrue);
    expect(releases, 1,
        reason: 'UI/sleep timer Pause must release focus without handler.pause');
    await handler.close();
    player.dispose();
  });

  test('sleep timer release works without a media command', () async {
    final engine = _FakeSpeechEngine();
    late void Function() expire;
    final player = ReaderPlayer(
      engine: engine,
      segments: const [SpeechSegment(0, 5, 'First')],
      onSegmentStarted: (_) async {},
      timerScheduler: (duration, callback) {
        expire = callback;
        return Timer(const Duration(days: 1), () {});
      },
    );
    var releases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async => true,
      releaseFocus: () async { releases++; },
    );
    handler.attach(player, bookId: 'timer', title: 'Timer');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isTrue);
    player.setSleepTimer(const Duration(minutes: 10));
    expire();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(player.isPlaying, isFalse);
    expect(player.isSettledIdle, isTrue);
    expect(releases, 1);
    await handler.close();
    player.dispose();
  });

  test('obsolete cloud denial after replacement cannot error or block '
      'the new media session', () async {
    final oldEngine = _FakeSpeechEngine();
    final newEngine = _FakeSpeechEngine();
    final old = _reader(oldEngine);
    final next = _reader(newEngine);
    final gate = Completer<bool>();
    var focusRequests = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusRequests++;
      return true;
    });
    handler.attach(old, bookId: 'old-private', title: 'Previous',
        canStart: () => gate.future);
    final obsolete = handler.play();
    handler.attach(next, bookId: 'next-book', title: 'Current');
    await handler.play();
    await _waitForSpoken(newEngine, 1);
    gate.complete(false);
    await obsolete;

    expect(handler.mediaItem.value?.id, 'next-book');
    expect(handler.ownsPlayer(next), isTrue);
    expect(newEngine.spoken, ['First']);
    expect(oldEngine.spoken, isEmpty);
    expect(focusRequests, 1,
        reason: 'Obsolete consent cannot start or focus the previous book');
    await handler.pause();
    await handler.close();
    old.dispose();
    next.dispose();
  });

  test('an earlier consent denial cannot fail a newer successful Play',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final firstConsent = Completer<bool>();
    var calls = 0;
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book', title: 'Book', canStart: () {
      calls++;
      return calls == 1
          ? firstConsent.future : Future<bool>.value(true);
    });
    final old = handler.play();
    await handler.play();
    await _waitForSpoken(engine, 1);
    firstConsent.complete(false);
    await old;

    expect(engine.spoken, ['First']);
    expect(handler.playbackState.value.playing, isTrue);
    await handler.pause();
    await handler.close();
    player.dispose();
  });

  test('a stale consent exception after Pause is ignored', () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final consent = Completer<bool>();
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book', title: 'Book',
        canStart: () => consent.future);
    final pendingPlay = handler.play();
    await handler.pause();
    consent.completeError(StateError('old consent storage failed'));
    await pendingPlay;

    expect(engine.spoken, isEmpty);
    expect(player.isPlaying, isFalse);
    await handler.close();
    player.dispose();
  });

  test('current cloud consent exception is still surfaced', () async {
    final player = _reader(_FakeSpeechEngine());
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book', title: 'Book',
        canStart: () async => throw StateError('consent storage failed'));
    await expectLater(handler.play(), throwsStateError);
    expect(player.isPlaying, isFalse);
    await handler.close();
    player.dispose();
  });

  test('two Play requests waiting for cloud consent start speech once',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final firstGate = Completer<bool>();
    final secondGate = Completer<bool>();
    var attempts = 0;
    var focusRequests = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async { focusRequests++; return true; },
    );
    handler.attach(player, bookId: 'private', title: 'Private',
      canStart: () {
        attempts++;
        return attempts == 1 ? firstGate.future : secondGate.future;
      });
    final older = handler.play();
    final latest = handler.play();
    secondGate.complete(true);
    await latest;
    await Future<void>.delayed(Duration.zero);
    firstGate.complete(true);
    await older;
    expect(engine.spoken, ['First']);
    expect(focusRequests, 1);
    await handler.pause();
    await handler.close();
    player.dispose();
  });

  test('two Play calls pending on audio focus acquire native focus once',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final gate = Completer<bool>();
    var requests = 0;
    var releases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () { requests++; return gate.future; },
      releaseFocus: () async { releases++; },
    );
    handler.attach(player, bookId: 'b', title: 'B');
    final first = handler.play();
    await Future<void>.delayed(Duration.zero);
    final second = handler.play();
    expect(requests, 1);
    gate.complete(true);
    await Future.wait([first, second]);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1,
        reason: 'A granted focus lease is reused within one active book');
    expect(engine.spoken, ['First']);
    await handler.pause();
    expect(releases, 1);
    await handler.close();
    player.dispose();
  });

  test('failed native Stop keeps focus until reader teardown',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    var releases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async => true,
      releaseFocus: () async { releases++; },
    );
    handler.attach(player, bookId: 'b', title: 'B');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    engine.failStop = true;
    await expectLater(player.pause(), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    expect(player.nativeStopUnconfirmed, isTrue);
    expect(player.isSettledIdle, isFalse,
        reason: 'A failed Stop is not evidence of silent native output');
    expect(releases, 0,
        reason: 'Focus must not be released while speech may remain active');
    await expectLater(handler.play(), throwsStateError);
    engine.failStop = false;
    await handler.close();
    expect(releases, 1,
        reason: 'Detaching the failed player explicitly releases focus');
    player.dispose();
  });

  test('concurrent close callers share native Stop and focus release',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final nativeStop = Completer<void>();
    final focusRelease = Completer<void>();
    var focusClaims = 0;
    var releases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async { focusClaims++; return true; },
      releaseFocus: () {
        releases++;
        return focusRelease.future;
      },
    );
    handler.attach(player, bookId: 'old', title: 'Old');
    await handler.play();
    await _waitForSpoken(engine, 1);
    engine.stopGate = nativeStop;

    final firstClose = handler.close();
    final secondClose = handler.close();
    expect(identical(firstClose, secondClose), isTrue,
        reason: 'The second caller must await full shutdown');
    var finished = false;
    firstClose.then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(handler.hasActiveBook, isFalse);
    expect(handler.mediaItem.value, isNull);
    expect(engine.stopCalls, 1,
        reason: 'Concurrent close must not issue duplicate native Stops');
    expect(focusClaims, 1);
    expect(releases, 1);

    nativeStop.complete();
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse,
        reason: 'Native Stop alone cannot complete close before focus release');
    focusRelease.complete();
    await Future.wait([firstClose, secondClose]);
    expect(finished, isTrue);
    expect(releases, 1);
    await handler.close(); // idempotent after completed shutdown
    expect(engine.stopCalls, 1);
    player.dispose();
  });

  test('close during pending Play permission cannot launch late audio',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final permission = Completer<bool>();
    var focusClaims = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusClaims++;
      return true;
    });
    handler.attach(player, bookId: 'private', title: 'Private',
        canStart: () => permission.future);
    final pendingPlay = handler.play();
    final closing = handler.close();
    expect(identical(handler.close(), closing), isTrue);
    await closing;
    permission.complete(true);
    await pendingPlay;

    expect(engine.spoken, isEmpty);
    expect(focusClaims, 0);
    expect(handler.mediaItem.value, isNull);
    await handler.close();
    player.dispose();
  });

  test('concurrent close tolerates a failing focus release', () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final releaseGate = Completer<void>();
    var releases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async => true,
      releaseFocus: () {
        releases++;
        return releaseGate.future;
      },
    );
    handler.attach(player, bookId: 'book', title: 'Book');
    await handler.play();
    await _waitForSpoken(engine, 1);
    await handler.pause();
    // Idle player still has a pending native focus release.
    final firstClose = handler.close();
    final secondClose = handler.close();
    expect(identical(firstClose, secondClose), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(releases, 1);
    releaseGate.completeError(StateError('Android session disposed'));
    await Future.wait([firstClose, secondClose]);
    expect(handler.hasActiveBook, isFalse);
    expect(releases, 1);
    player.dispose();
  });

  test('detached reader cannot hijack a newly attached book', () async {
    final older = _reader(_FakeSpeechEngine());
    final newer = _reader(_FakeSpeechEngine());
    final gate = Completer<bool>();
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(older, bookId: 'old', title: 'Old',
        canStart: () => gate.future);
    final oldPlay = handler.play();
    handler.attach(newer, bookId: 'new', title: 'New');
    gate.complete(true);
    await oldPlay;
    handler.detach(older); // obsolete view's dispose must be ignored
    expect(handler.mediaItem.value?.id, 'new');
    expect(handler.hasActiveBook, isTrue);
    await handler.close();
    older.dispose();
    newer.dispose();
  });
}
