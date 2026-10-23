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

class _SpeechEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? _active;
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
  Future<void> stop() async => finish();

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
