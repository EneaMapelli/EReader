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
  Future<void> stop() async => finish();

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bind publishes book and transport; unbind removes orphan controls',
      () async {
    final engine = _FakeSpeechEngine();
    final player = _reader(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'book-A', title: 'A Tale');
    expect(handler.hasActiveBook, isTrue);
    expect(handler.mediaItem.value?.title, 'A Tale');
    expect(handler.queue.value.single.id, 'book-A');
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.controls, contains(MediaControl.play));
    expect(handler.playbackState.value.systemActions, isEmpty,
        reason: 'TTS chunks have no trustworthy timing for a seek bar');

    handler.detach(player);
    expect(handler.hasActiveBook, isFalse);
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
    await pending.pause();
    focusGate.complete(true);
    await remotePlay;
    expect(engine.spoken, isEmpty,
        reason: 'A late focus grant must not reverse a newer Pause');
    await pending.close();
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
    final pendingPlay = handler.play();
    await Future<void>.delayed(Duration.zero);
    expect(focusRequests, 0);
    expect(engine.spoken, isEmpty);

    releaseGate.complete();
    await pendingPlay;
    await Future<void>.delayed(Duration.zero);
    expect(focusRequests, 1);
    expect(engine.spoken, ['First']);
    await handler.pause();
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
