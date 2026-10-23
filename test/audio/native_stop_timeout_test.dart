import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:ereader/audio/reader_media_handler.dart';
import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:flutter_test/flutter_test.dart';

class _HeldStopEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? stopGate;
  Completer<void>? utterance;
  int nativeStops = 0;
  bool throwOnStop = false;

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
    utterance = Completer<void>();
    return utterance!.future;
  }

  @override
  Future<void> stop() async {
    nativeStops++;
    if (stopGate != null) await stopGate!.future;
    if (throwOnStop) throw StateError('native Stop refused');
    completeSpeech();
  }

  void completeSpeech() {
    if (utterance != null && !utterance!.isCompleted) utterance!.complete();
  }

  @override
  Future<void> dispose() async {
    // Disposal must not depend on a simulated plugin method channel hang.
    completeSpeech();
  }
}

ReaderPlayer _player(_HeldStopEngine engine) => ReaderPlayer(
  engine: engine,
  segments: const [
    SpeechSegment(0, 5, 'First'),
    SpeechSegment(6, 12, 'Second'),
  ],
  nativeStopTimeout: const Duration(milliseconds: 15),
  onSegmentStarted: (_) async {},
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('timeout is bounded but cannot authorize another speech stream',
      () async {
    final engine = _HeldStopEngine();
    final player = _player(engine);
    final original = player.play();
    await _settle();
    expect(engine.spoken, ['First']);

    engine.stopGate = Completer<void>();
    await expectLater(player.pause(), throwsA(isA<SpeechStopTimeout>()));
    expect(player.isPlaying, isFalse);
    expect(player.nativeStopUnconfirmed, isTrue);
    expect(player.isSettledIdle, isFalse);
    expect(player.lastError, isA<SpeechStopTimeout>());
    await expectLater(player.play(), throwsStateError);
    expect(engine.spoken, ['First']);
    expect(engine.nativeStops, 1);

    engine.stopGate!.complete();
    await original;
    await _settle();
    expect(player.nativeStopUnconfirmed, isFalse,
      reason: 'A late, successful Stop is a genuine confirmation');
    expect(player.isPlaying, isFalse,
      reason: 'A late Stop completion must NEVER auto-resume');
    expect(engine.spoken, ['First']);

    final resumed = player.play(); // explicit user action after recovery
    await _settle();
    expect(engine.spoken, ['First', 'First']);
    engine.completeSpeech();
    await _settle();
    engine.completeSpeech();
    await resumed;
    player.dispose();
  });

  test('timed-out Seek cannot resume a newer segment after late Stop',
      () async {
    final engine = _HeldStopEngine();
    final player = _player(engine);
    final initial = player.play();
    await _settle();
    engine.stopGate = Completer<void>();

    await expectLater(player.seekTo(1), throwsA(isA<SpeechStopTimeout>()));
    expect(player.currentIndex, 0);
    expect(engine.spoken, ['First']);
    expect(player.nativeStopUnconfirmed, isTrue);
    engine.stopGate!.complete();
    await initial;
    await _settle();
    expect(engine.spoken, ['First']);
    expect(player.isPlaying, isFalse);
    player.dispose();
  });

  test('repeated Pause while Stop hangs does not spawn another native Stop',
      () async {
    final engine = _HeldStopEngine();
    final player = _player(engine);
    final reading = player.play();
    await _settle();
    engine.stopGate = Completer<void>();
    await expectLater(player.pause(), throwsA(isA<SpeechStopTimeout>()));
    await expectLater(player.pause(), throwsStateError);
    expect(engine.nativeStops, 1);
    engine.stopGate!.complete();
    await reading;
    await _settle();
    expect(player.isSettledIdle, isTrue);
    expect(engine.spoken, ['First']);
    player.dispose();
  });

  test('failed native Stop remains unsafe even after error completes',
      () async {
    final engine = _HeldStopEngine()..throwOnStop = true;
    final player = _player(engine);
    final reading = player.play();
    await _settle();
    await expectLater(player.pause(), throwsStateError);
    expect(player.nativeStopUnconfirmed, isTrue);
    expect(player.isSettledIdle, isFalse);
    await expectLater(player.play(), throwsStateError);
    expect(engine.spoken, ['First']);
    engine.completeSpeech();
    await reading;
    player.dispose();
  });

  test('late native Stop failure after timeout must not unlock playback',
      () async {
    final engine = _HeldStopEngine()..throwOnStop = true;
    final player = _player(engine);
    final reading = player.play();
    await _settle();
    engine.stopGate = Completer<void>();
    await expectLater(player.pause(), throwsA(isA<SpeechStopTimeout>()));
    engine.stopGate!.complete();
    await _settle();
    expect(player.nativeStopUnconfirmed, isTrue);
    await expectLater(player.play(), throwsStateError);
    engine.completeSpeech();
    await reading;
    player.dispose();
  });

  test('Android remote Play refuses uncertain Stop without acquiring focus',
      () async {
    final engine = _HeldStopEngine();
    final player = _player(engine);
    var focusRequests = 0;
    var releases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async { focusRequests++; return true; },
      releaseFocus: () async { releases++; },
    );
    handler.attach(player, bookId: 'book', title: 'Book');
    await handler.play();
    await _settle();
    expect(focusRequests, 1);
    engine.stopGate = Completer<void>();
    await expectLater(handler.pause(), throwsA(isA<SpeechStopTimeout>()));
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.error);
    expect(player.nativeStopUnconfirmed, isTrue);
    expect(releases, 0,
      reason: 'Native output is not confirmed stopped; focus stays held');
    await expectLater(handler.play(), throwsStateError);
    expect(focusRequests, 1);
    expect(engine.spoken, ['First']);

    engine.stopGate!.complete();
    await _settle();
    expect(player.isSettledIdle, isTrue);
    expect(releases, 1);
    await handler.close();
    player.dispose();
  });

  test('positive timeout is required', () {
    final engine = _HeldStopEngine();
    expect(
      () => ReaderPlayer(
        engine: engine,
        segments: const [],
        nativeStopTimeout: Duration.zero,
        onSegmentStarted: (_) async {},
      ),
      throwsAssertionError,
    );
  });
}
