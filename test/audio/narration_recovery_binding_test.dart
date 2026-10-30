import 'dart:async';
import 'dart:io';

import 'package:ereader/audio/narration_recovery_binding.dart';
import 'package:ereader/data/book_decoder.dart';
import 'package:ereader/data/epub_text_extractor.dart';
import 'package:ereader/features/reader/epub_chapter_navigation.dart';
import 'package:ereader/audio/reader_media_handler.dart';
import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _SpeechEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? _active;
  Completer<void>? stopGate;
  bool failNext = false;

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
    if (failNext) {
      failNext = false;
      return Future<void>.error(StateError('Speech engine failure'));
    }
    _active = Completer<void>();
    return _active!.future;
  }

  void finish() {
    if (_active != null && !_active!.isCompleted) _active!.complete();
  }

  @override
  Future<void> stop() async {
    if (stopGate != null) await stopGate!.future;
    finish();
  }

  @override
  Future<void> dispose() async => finish();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late LibraryStore store;
  late String bookId;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-binding-');
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
    final source = File(p.join(root.path, 'one.txt'));
    await source.writeAsString('First. Second. Third.');
    bookId = (await store.importFile(source.path)).id;
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  NarrationRecoveryBinding binding() => NarrationRecoveryBinding(
    store: store,
    bookId: bookId,
    anchorFor: (segment) => ReadingAnchor(
      kind: AnchorKind.text,
      sourceId: 'body',
      localOffset: segment.start,
    ),
    anchorAtOffset: (offset) => ReadingAnchor(
      kind: AnchorKind.text,
      sourceId: 'body',
      localOffset: offset,
    ),
  );

  ReaderPlayer playerFor(_SpeechEngine engine,
      NarrationRecoveryBinding recovery, {
      Duration nativeStopTimeout = const Duration(seconds: 8),
      }) {
    final player = ReaderPlayer(
      engine: engine,
      nativeStopTimeout: nativeStopTimeout,
      segments: const [
        SpeechSegment(0, 6, 'First.'),
        SpeechSegment(7, 14, 'Second.'),
      ],
      onSegmentStarted: recovery.onSegmentStarted,
      onSegmentCompleted: recovery.onSegmentCompleted,
    );
    recovery.attach(player);
    return player;
  }

  Future<void> restartStore() async {
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  }

  int activeCheckpoints() {
    final db = sqlite3.open(p.join(root.path, 'library.sqlite'));
    try {
      final rows = db.select('SELECT book_id FROM speech_recovery_marker');
      expect(rows.every((row) => row['book_id'] == bookId), isTrue);
      return rows.length;
    } finally {
      db.dispose();
    }
  }

  test('silent EPUB appendix remote EOF bookmark survives SQLite restart',
      () async {
    const source = 'First. Second. Third.';
    const document = DocumentContent(
      title: 'Illustrated ending',
      text: source,
      epubSpineRanges: [
        EpubSpineRange(idref: 'story', href: 'story.xhtml',
            start: 0, end: source.length),
        EpubSpineRange(idref: 'art-first', href: 'art-a.xhtml',
            start: source.length, end: source.length),
        EpubSpineRange(idref: 'art-second', href: 'art-b.xhtml',
            start: source.length, end: source.length),
      ],
    );
    const clips = [SpeechSegment(0, source.length, source)];
    final chapters = buildEpubChapters(document, clips);
    final targets = buildEpubMediaChapterTargets(
        chapters, clips.length, source.length);
    final eof = targets[clips.length]!;
    expect(eof.silentSpineIdref, 'art-first');
    expect(eof.sourceOffset, source.length);
    final anchor = ReadingAnchor(
      kind: AnchorKind.epubSpine,
      sourceId: eof.silentSpineIdref!,
      localOffset: 0,
    );

    // This is the same persistent source pair that ReaderScreen writes
    // after a *paused* remote media skip. It is not a speech checkpoint
    // and must not set the crash-only narration marker.
    await store.savePosition(bookId, eof.sourceOffset, anchor: anchor);
    expect(activeCheckpoints(), 0);
    await restartStore();
    final restored = store.getBook(bookId)!;
    expect(restored.progressOffset, source.length);
    expect(restored.progressAnchor?.kind, AnchorKind.epubSpine);
    expect(restored.progressAnchor?.sourceId, 'art-first');
    expect(document.offsetOf(restored.progressAnchor!), source.length);
    expect(speechResumeIndexForOffset(
        clips, restored.progressOffset), clips.length,
        reason: 'A silent final appendix cannot replay the last clip');
    expect(store.interruptedNarrationBook, isNull);
  });

  test('real ReaderPlayer checkpoints before speech and pause clears it',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    final running = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First.']);
    expect(store.getBook(bookId)!.progressAnchor?.localOffset, 0);
    await player.pause();
    await running;
    expect(player.isPlaying, isFalse);
    recovery.dispose();
    player.dispose();
    await restartStore();
    expect(store.interruptedNarrationBook, isNull);
  });

  test('running player left alive when SQLite closes yields recovery hint',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    final running = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First.']);
    // Abrupt process exit simulation: no ReaderPlayer.pause / binding.dispose.
    // In the fixture only the database is closed; real process termination
    // would also destroy the Dart objects.
    await restartStore();
    expect(store.interruptedNarrationBook?.id, bookId);
    expect(store.interruptedNarrationBook?.progressOffset, 0);
    // A real killed process has no in-memory player to clean up. Simulate
    // that by disposing it without notifying the binding (which refers to
    // the old, deliberately closed database).
    player.dispose();
    await running;
  });

  test('book completion and engine failure both clear active checkpoint',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    final running = player.play();
    await Future<void>.delayed(Duration.zero);
    engine.finish();
    await Future<void>.delayed(Duration.zero);
    engine.finish();
    await running;
    recovery.dispose();
    player.dispose();
    await restartStore();
    expect(store.interruptedNarrationBook, isNull);

    final failing = _SpeechEngine()..failNext = true;
    final retry = binding();
    final badPlayer = playerFor(failing, retry);
    await expectLater(badPlayer.play(), throwsStateError);
    expect(badPlayer.isPlaying, isFalse);
    retry.dispose();
    badPlayer.dispose();
    await restartStore();
    expect(store.interruptedNarrationBook, isNull);
  });

  test('naturally completed clip persists next source anchor', () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    final running = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(store.getBook(bookId)!.progressOffset, 0);
    engine.finish();
    // The second utterance is in progress: the first finished successfully,
    // so an abrupt process exit must restore to the next segment.
    for (var i = 0; i < 100 && engine.spoken.length < 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(engine.spoken, ['First.', 'Second.']);
    expect(store.getBook(bookId)!.progressOffset, 7);
    expect(store.getBook(bookId)!.progressAnchor?.localOffset, 7);
    await player.pause();
    await running;
    recovery.dispose();
    player.dispose();
    await restartStore();
    expect(store.getBook(bookId)!.progressOffset, 7);
    expect(store.interruptedNarrationBook, isNull);
  });

  test('Android focus loss retains active checkpoint until native Stop',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    var focusReleases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async => true,
      releaseFocus: () async { focusReleases++; },
    );
    handler.attach(player, bookId: bookId, title: 'Book');
    await handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First.']);
    expect(store.getBook(bookId)!.progressOffset, 0);
    expect(activeCheckpoints(), 1);
    engine.stopGate = Completer<void>();
    final losingFocus = handler.pauseForSystemInterruption();
    final duplicateEvent = handler.pauseForSystemInterruption();
    expect(identical(losingFocus, duplicateEvent), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(activeCheckpoints(), 1,
        reason: 'Native Stop has not confirmed silence');
    expect(player.isSettledIdle, isFalse);
    expect(focusReleases, 0);
    engine.stopGate!.complete();
    await losingFocus;
    expect(activeCheckpoints(), 0);
    expect(store.getBook(bookId)!.progressOffset, 0);
    expect(focusReleases, 1);
    expect(engine.spoken, ['First.']);
    await handler.close();
    recovery.dispose();
    player.dispose();
    await restartStore();
    expect(store.interruptedNarrationBook, isNull);
  });

  test('interruption midway through first clip never advances progress',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    final running = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First.']);
    expect(store.getBook(bookId)!.progressOffset, 0);
    await player.pause();
    await running;
    expect(store.getBook(bookId)!.progressOffset, 0,
        reason: 'Never skip a partially heard utterance');
    recovery.dispose();
    player.dispose();
    await restartStore();
    expect(store.getBook(bookId)!.progressOffset, 0);
  });

  test('completed passage jumps ahead of silent EPUB-like note chunks',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 6, 'First.'),
        SpeechSegment(7, 14, 'Second.'),
        SpeechSegment(15, 21, 'Third.'),
      ],
      onSegmentStarted: recovery.onSegmentStarted,
      onSegmentCompleted: recovery.onSegmentCompleted,
    );
    player.shouldSkipSegment = (chunk) => chunk.start == 7;
    recovery.attach(player);
    final running = player.play();
    await Future<void>.delayed(Duration.zero);
    engine.finish();
    for (var i = 0; i < 100 && engine.spoken.length < 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(engine.spoken, ['First.', 'Third.']);
    expect(store.getBook(bookId)!.progressOffset, 15);
    expect(store.getBook(bookId)!.progressAnchor?.localOffset, 15);
    await player.pause();
    await running;
    recovery.dispose();
    player.dispose();
  });

  test('full completion saves the end position and clears crash marker',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    final running = player.play();
    await Future<void>.delayed(Duration.zero);
    engine.finish();
    for (var i = 0; i < 100 && engine.spoken.length < 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(engine.spoken, ['First.', 'Second.']);
    engine.finish();
    await running;
    expect(store.getBook(bookId)!.progressOffset, 14);
    expect(store.getBook(bookId)!.progressAnchor?.localOffset, 14);
    expect(player.isSettledIdle, isTrue);
    recovery.dispose();
    player.dispose();
    await restartStore();
    expect(store.interruptedNarrationBook, isNull);
  });

  test('seek preserves crash checkpoint while native stop is pending',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    final firstRun = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(activeCheckpoints(), 1);
    engine.stopGate = Completer<void>();
    final seeking = player.seekTo(1);
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    expect(player.isSettledIdle, isFalse);
    expect(activeCheckpoints(), 1,
        reason: 'Navigation must not erase a crash recovery marker');

    engine.stopGate!.complete();
    await seeking;
    await firstRun;
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken.last, 'Second.');
    expect(activeCheckpoints(), 1);
    expect(store.getBook(bookId)!.progressAnchor?.localOffset, 7);
    await player.pause();
    expect(activeCheckpoints(), 0);
    recovery.dispose();
    player.dispose();
  });

  test('paused completed audio retains SQLite progress until delayed '
      'checkpoint commits', () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final ack = Completer<void>();
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 6, 'First.'),
        SpeechSegment(7, 14, 'Second.'),
      ],
      onSegmentStarted: recovery.onSegmentStarted,
      onSegmentCompleted: (finished, next) async {
        await ack.future;
        await recovery.onSegmentCompleted(finished, next);
      },
    );
    recovery.attach(player);
    final speaking = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(store.getBook(bookId)!.progressOffset, 0);
    engine.finish();
    for (var i = 0; i < 100 && !player.isCommittingSpeechSegment; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(player.isCommittingSpeechSegment, isTrue);
    final pausing = player.pause();
    await Future<void>.delayed(Duration.zero);
    expect(activeCheckpoints(), 1);
    expect(player.isSettledIdle, isFalse);
    expect(store.getBook(bookId)!.progressOffset, 0);
    ack.complete();
    await pausing;
    await speaking;
    expect(store.getBook(bookId)!.progressOffset, 7,
        reason: 'Fully heard audio must not be repeated after Pause');
    expect(store.getBook(bookId)!.progressAnchor?.localOffset, 7);
    expect(player.currentIndex, 1);
    expect(activeCheckpoints(), 0);
    recovery.dispose();
    player.dispose();
    await restartStore();
    expect(store.getBook(bookId)!.progressOffset, 7);
    expect(store.interruptedNarrationBook, isNull);
  });

  test('pause preserves marker until native stop completes, then clears',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    final running = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(activeCheckpoints(), 1);
    engine.stopGate = Completer<void>();
    final pausing = player.pause();
    await Future<void>.delayed(Duration.zero);
    expect(player.isSettledIdle, isFalse);
    expect(activeCheckpoints(), 1);
    engine.stopGate!.complete();
    await pausing;
    await running;
    expect(player.isSettledIdle, isTrue);
    expect(activeCheckpoints(), 0);
    recovery.dispose();
    player.dispose();
  });

  test('voice change keeps marker across stop and resumed narration',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    final running = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(activeCheckpoints(), 1);
    engine.stopGate = Completer<void>();
    final switching = player.selectVoice(
      const SpeechVoice(name: 'test-voice', locale: 'it-IT'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(player.isSettledIdle, isFalse);
    expect(activeCheckpoints(), 1);
    engine.stopGate!.complete();
    await switching;
    await running;
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isTrue);
    expect(activeCheckpoints(), 1);
    await player.pause();
    expect(activeCheckpoints(), 0);
    recovery.dispose();
    player.dispose();
  });

  test('uncertain native Stop retains recovery checkpoint after dispose',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery,
      nativeStopTimeout: const Duration(milliseconds: 15));
    final reading = player.play();
    await Future<void>.delayed(Duration.zero);
    engine.stopGate = Completer<void>();

    await expectLater(player.pause(), throwsA(isA<SpeechStopTimeout>()));
    expect(player.nativeStopUnconfirmed, isTrue);
    recovery.dispose();
    // Reader teardown is not proof that a hung plugin stopped outputting.
    await restartStore();
    expect(store.interruptedNarrationBook?.id, bookId);
    expect(store.interruptedNarrationBook?.progressAnchor?.localOffset, 0);
    engine.stopGate!.complete();
    await reading;
    player.dispose();
  });

  test('closing a reader while narration is live retains recovery hint',
      () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    final speaking = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First.']);
    expect(activeCheckpoints(), 1);

    // ReaderScreen may detach before native disposal has finished.
    // It must never claim a clean interruption solely because the
    // checkpoint listener is being removed.
    recovery.dispose();
    await restartStore();
    expect(store.interruptedNarrationBook?.id, bookId);
    expect(store.interruptedNarrationBook?.progressAnchor?.localOffset, 0);

    // Simulate native cleanup after the UI was already destroyed.
    await player.pause();
    await speaking;
    player.dispose();
  });

  test('binding can only attach once and dispose is idempotent', () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    expect(() => recovery.attach(player), throwsStateError);
    recovery.dispose();
    recovery.dispose();
    // play() intentionally resolves at the END of the whole book. Start
    // without awaiting and explicitly stop the mock utterance, otherwise
    // this test hangs forever before reaching the pause assertion.
    final speaking = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['First.']);
    // Without an attached checkpoint owner, playback does not produce a
    // persisted crash marker. The audio engine itself remains functional.
    await player.pause();
    await speaking;
    player.dispose();
    await restartStore();
    expect(store.interruptedNarrationBook, isNull);
  });
}
