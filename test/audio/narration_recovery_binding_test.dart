import 'dart:async';
import 'dart:io';

import 'package:ereader/audio/narration_recovery_binding.dart';
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
  );

  ReaderPlayer playerFor(_SpeechEngine engine,
      NarrationRecoveryBinding recovery) {
    final player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 6, 'First.'),
        SpeechSegment(7, 14, 'Second.'),
      ],
      onSegmentStarted: recovery.onSegmentStarted,
    );
    recovery.attach(player);
    return player;
  }

  Future<void> restartStore() async {
    store.dispose();
    store = LibraryStore(homeDirectory: root);
    await store.initialize();
  }

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

  test('binding can only attach once and dispose is idempotent', () async {
    final engine = _SpeechEngine();
    final recovery = binding();
    final player = playerFor(engine, recovery);
    expect(() => recovery.attach(player), throwsStateError);
    recovery.dispose();
    recovery.dispose();
    await player.play();
    await Future<void>.delayed(Duration.zero);
    // Without an attached checkpoint owner, playback does not produce a
    // persisted crash marker. The audio engine itself remains functional.
    await player.pause();
    player.dispose();
    await restartStore();
    expect(store.interruptedNarrationBook, isNull);
  });
}
