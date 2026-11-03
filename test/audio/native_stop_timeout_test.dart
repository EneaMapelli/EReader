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

  test('queued Play before timeout is cancelled rather than resumed late',
      () async {
    final engine = _HeldStopEngine();
    final player = _player(engine);
    final first = player.play();
    await _settle();
    engine.stopGate = Completer<void>();
    final pausing = player.pause();
    final queuedPlay = player.play();
    await expectLater(pausing, throwsA(isA<SpeechStopTimeout>()));
    expect(player.nativeStopUnconfirmed, isTrue);
    expect(engine.spoken, ['First']);

    engine.stopGate!.complete();
    await Future.wait([first, queuedPlay]);
    await _settle();
    expect(engine.spoken, ['First'],
      reason: 'A previously queued Play is not fresh consent after timeout');
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

  test('native Stop confirmation snapshot has a finite deadline',
      () async {
    final engine = _HeldStopEngine();
    final player = _player(engine);
    final reading = player.play();
    await _settle();
    expect(engine.spoken, ['First']);
    engine.stopGate = Completer<void>();

    final pausing = player.pause();
    // Snapshot is taken while the original native plugin Stop hangs.
    final confirmation = player.waitForNativeStopConfirmation();
    await expectLater(pausing, throwsA(isA<SpeechStopTimeout>()));
    expect(await confirmation, isFalse,
        reason: 'The confirmation fence must not wait indefinitely');
    expect(player.nativeStopUnconfirmed, isTrue);
    await expectLater(player.play(), throwsStateError);

    engine.stopGate!.complete();
    await reading;
    player.dispose();
  });

  test('Android handler close completes after an unacknowledged native Stop',
      () async {
    final engine = _HeldStopEngine();
    final player = _player(engine);
    var released = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async => true,
      releaseFocus: () async { released++; },
    );
    handler.attach(player, bookId: 'old', title: 'Old book');
    await handler.play();
    await _settle();
    expect(engine.spoken, ['First']);
    engine.stopGate = Completer<void>();

    // Direct reader shutdown starts the native Stop during detach.
    // close() must finish once the deadline says this Stop is unsafe,
    // without assuming silence or waiting on the stuck platform Future.
    final closing = handler.close();
    final concurrentClose = handler.close();
    expect(identical(closing, concurrentClose), isTrue,
        reason: 'Concurrent close also waits for bounded Stop confirmation');
    await Future.wait([closing, concurrentClose])
        .timeout(const Duration(seconds: 1));
    expect(handler.hasActiveBook, isFalse);
    expect(player.nativeStopUnconfirmed, isTrue);
    expect(released, 1);
    expect(engine.nativeStops, 1);

    engine.stopGate!.complete();
    await _settle();
    player.dispose();
  });

  test('new book Play fails closed after old unacknowledged Stop',
      () async {
    final oldEngine = _HeldStopEngine();
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    var focusRequests = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusRequests++;
      return true;
    });
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _settle();
    expect(oldEngine.spoken, ['First']);
    expect(focusRequests, 1);
    oldEngine.stopGate = Completer<void>();

    handler.attach(newPlayer, bookId: 'new', title: 'New');
    await expectLater(
      handler.play().timeout(const Duration(seconds: 1)),
      throwsStateError,
    );
    expect(handler.ownsPlayer(newPlayer), isTrue,
        reason: 'Old Stop timeout does not remove new media metadata');
    expect(handler.mediaItem.value?.id, 'new');
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.error);
    expect(handler.playbackState.value.controls, isEmpty,
        reason: 'Never advertise playback while old native Stop is unsafe');
    expect(newEngine.spoken, isEmpty,
        reason: 'Never assume native silence after a Stop timeout');
    expect(focusRequests, 1,
        reason: 'Unconfirmed Stop must not claim focus for new narration');

    await handler.close().timeout(const Duration(seconds: 1));
    oldEngine.stopGate!.complete();
    await _settle();
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('late confirmed native Stop recovers on explicit Play, not by itself',
      () async {
    final oldEngine = _HeldStopEngine();
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    var focusRequests = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusRequests++;
      return true;
    });
    handler.attach(oldPlayer, bookId: 'old', title: 'Previous');
    await handler.play();
    await _settle();
    expect(oldEngine.spoken, ['First']);
    oldEngine.stopGate = Completer<void>();

    // Outgoing Stop is still pending when the new reader attaches.
    handler.attach(newPlayer, bookId: 'new', title: 'Current');
    await expectLater(handler.play().timeout(const Duration(seconds: 1)),
        throwsStateError);
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.error);
    expect(newEngine.spoken, isEmpty);
    expect(focusRequests, 1);
    expect(await handler.tryRecoverAfterConfirmedNativeStops(), isFalse,
        reason: 'The old plugin has not acknowledged Stop yet');

    // A late native confirmation is positive evidence of silence, but
    // must NEVER automatically trigger Play or claim Android focus.
    oldEngine.stopGate!.complete();
    await _settle();
    expect(await oldPlayer.waitForNativeStopConfirmation(), isTrue);
    expect(newEngine.spoken, isEmpty);
    expect(focusRequests, 1);

    // A fresh user-requested Play is permitted to re-arm this handler
    // after verifying the exact unsafe native engine's acknowledgment.
    await handler.play();
    await _settle();
    expect(handler.requiresFreshAudioSession, isFalse);
    expect(handler.mediaItem.value?.id, 'new');
    expect(newEngine.spoken, ['First']);
    expect(focusRequests, 2);
    expect(handler.playbackState.value.playing, isTrue);
    await handler.pause();
    await handler.close();
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('genuine native Stop failure cannot be rearmed on same handler',
      () async {
    final oldEngine = _HeldStopEngine()..throwOnStop = true;
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    var focusRequests = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusRequests++;
      return true;
    });
    handler.attach(oldPlayer, bookId: 'old', title: 'Previous');
    await handler.play();
    await _settle();

    handler.attach(newPlayer, bookId: 'new', title: 'Current');
    await expectLater(handler.play(), throwsStateError);
    expect(await handler.tryRecoverAfterConfirmedNativeStops(), isFalse);
    // Fixing the underlying fake engine after a failed Stop does not
    // rewrite the player's recorded native failure as confirmed silence.
    oldEngine.throwOnStop = false;
    expect(await handler.tryRecoverAfterConfirmedNativeStops(), isFalse);
    await expectLater(handler.play(), throwsStateError);
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(handler.playbackState.value.controls, isEmpty);
    expect(newEngine.spoken, isEmpty);
    expect(focusRequests, 1);

    await handler.close();
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('close invalidates a pending successful recovery probe',
      () async {
    final oldEngine = _HeldStopEngine();
    final nextEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final nextPlayer = _player(nextEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _settle();
    oldEngine.stopGate = Completer<void>();

    handler.attach(nextPlayer, bookId: 'next', title: 'Next');
    // This recovery query is awaiting the *successful* old Stop.
    final recovery = handler.tryRecoverAfterConfirmedNativeStops();
    final closing = handler.close();
    oldEngine.stopGate!.complete();

    expect(await recovery, isFalse,
        reason: 'A closed MediaSession cannot report recovered ownership');
    await closing;
    expect(handler.hasActiveBook, isFalse);
    expect(handler.mediaItem.value, isNull);
    expect(nextEngine.spoken, isEmpty);
    await handler.close();
    oldPlayer.dispose();
    nextPlayer.dispose();
  });

  test('a newer book handoff invalidates an older recovery probe',
      () async {
    final oldEngine = _HeldStopEngine();
    final middleEngine = _HeldStopEngine();
    final currentEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final middlePlayer = _player(middleEngine);
    final currentPlayer = _player(currentEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _settle();
    oldEngine.stopGate = Completer<void>();

    handler.attach(middlePlayer, bookId: 'middle', title: 'Middle');
    final obsoleteRecovery = handler.tryRecoverAfterConfirmedNativeStops();
    handler.attach(currentPlayer, bookId: 'current', title: 'Current');
    oldEngine.stopGate!.complete();

    expect(await obsoleteRecovery, isFalse,
        reason: 'A successful old Stop does not validate a later binding');
    expect(handler.ownsPlayer(currentPlayer), isTrue);
    expect(handler.mediaItem.value?.id, 'current');
    expect(currentEngine.spoken, isEmpty);
    await handler.play();
    await _settle();
    expect(currentEngine.spoken, ['First']);
    expect(middleEngine.spoken, isEmpty);
    await handler.pause();
    await handler.close();
    oldPlayer.dispose();
    middlePlayer.dispose();
    currentPlayer.dispose();
  });

  test('already timed-out native Stop is rejected without a second wait',
      () async {
    final oldEngine = _HeldStopEngine();
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _settle();
    oldEngine.stopGate = Completer<void>();
    handler.attach(newPlayer, bookId: 'new', title: 'New');

    await expectLater(handler.play(), throwsStateError);
    expect(oldPlayer.nativeStopUnconfirmed, isTrue);
    var completed = false;
    final recovery = handler.tryRecoverAfterConfirmedNativeStops()
        .then((result) {
      completed = true;
      return result;
    });
    await _settle();
    expect(completed, isTrue,
        reason: 'Do not wait another Stop deadline after a known timeout');
    expect(await recovery, isFalse);
    expect(newEngine.spoken, isEmpty);
    expect(handler.requiresFreshAudioSession, isTrue);

    oldEngine.stopGate!.complete();
    await _settle();
    await handler.close();
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('simultaneous recovery checks share the winning late Stop result',
      () async {
    final oldEngine = _HeldStopEngine();
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    var focusRequests = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusRequests++;
      return true;
    });
    handler.attach(oldPlayer, bookId: 'old', title: 'Old book');
    await handler.play();
    await _settle();
    oldEngine.stopGate = Completer<void>();
    handler.attach(newPlayer, bookId: 'new', title: 'New book');

    await expectLater(handler.play(), throwsStateError);
    expect(handler.requiresFreshAudioSession, isTrue);
    oldEngine.stopGate!.complete();
    await _settle();
    expect(await oldPlayer.waitForNativeStopConfirmation(), isTrue);

    // Without a shared recovery Future, the first verification resets
    // _pendingTransportStops and the second incorrectly reports failure.
    final first = handler.tryRecoverAfterConfirmedNativeStops();
    final second = handler.tryRecoverAfterConfirmedNativeStops();
    expect(identical(first, second), isTrue);
    final results = await Future.wait([first, second]);
    expect(results, [true, true]);
    expect(handler.requiresFreshAudioSession, isFalse);
    expect(newEngine.spoken, isEmpty,
        reason: 'Recovering state never starts speech without user Play');
    expect(focusRequests, 1);

    await handler.play();
    await _settle();
    expect(newEngine.spoken, ['First']);
    expect(focusRequests, 2);
    await handler.pause();
    await handler.close();
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('second native Stop failure remains locked after earlier recovery',
      () async {
    final oldEngine = _HeldStopEngine();
    final middleEngine = _HeldStopEngine();
    final currentEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final middlePlayer = _player(middleEngine);
    final currentPlayer = _player(currentEngine);
    var focusRequests = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusRequests++;
      return true;
    });
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _settle();
    expect(focusRequests, 1);

    oldEngine.stopGate = Completer<void>();
    handler.attach(middlePlayer, bookId: 'middle', title: 'Middle');
    await expectLater(handler.play(), throwsStateError);
    expect(handler.requiresFreshAudioSession, isTrue);
    oldEngine.stopGate!.complete();
    await _settle();

    await handler.play(); // Explicit recovery after confirmed old Stop.
    await _settle();
    expect(middleEngine.spoken, ['First']);
    expect(handler.requiresFreshAudioSession, isFalse);
    expect(focusRequests, 2);

    middleEngine.throwOnStop = true;
    handler.attach(currentPlayer, bookId: 'current', title: 'Current');
    await expectLater(handler.play(), throwsStateError);
    expect(await handler.tryRecoverAfterConfirmedNativeStops(), isFalse);
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(handler.mediaItem.value?.id, 'current');
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.error);
    expect(handler.playbackState.value.controls, isEmpty);
    expect(currentEngine.spoken, isEmpty);
    expect(focusRequests, 2,
        reason: 'A later failed Stop must never inherit earlier recovery');
    middleEngine.throwOnStop = false;
    await handler.close();
    oldPlayer.dispose();
    middlePlayer.dispose();
    currentPlayer.dispose();
  });

  test('direct navigation invalidates recovery awaiting the old Stop',
      () async {
    final oldEngine = _HeldStopEngine();
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _settle();
    oldEngine.stopGate = Completer<void>();

    handler.attach(newPlayer, bookId: 'new', title: 'New');
    final obsoleteRecovery = handler.tryRecoverAfterConfirmedNativeStops();
    await newPlayer.seekTo(1); // Direct reader action, not MediaSession.
    oldEngine.stopGate!.complete();
    expect(await obsoleteRecovery, isFalse,
        reason: 'A new direct Seek invalidates an earlier recovery query');
    expect(newEngine.spoken, isEmpty);
    expect(newPlayer.currentIndex, 1);
    expect(handler.ownsPlayer(newPlayer), isTrue);

    await handler.play();
    await _settle();
    expect(newEngine.spoken, ['Second']);
    await handler.pause();
    await handler.close();
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('active direct native Stop prevents premature recovery rearm',
      () async {
    final oldEngine = _HeldStopEngine();
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _settle();
    oldEngine.stopGate = Completer<void>();
    handler.attach(newPlayer, bookId: 'new', title: 'New');

    await expectLater(handler.play(), throwsStateError);
    oldEngine.stopGate!.complete();
    await _settle();
    expect(oldPlayer.nativeStopUnconfirmed, isFalse);
    expect(handler.requiresFreshAudioSession, isTrue);

    newEngine.stopGate = Completer<void>();
    final directPause = newPlayer.pause();
    expect(newPlayer.isSettledIdle, isFalse);
    expect(await handler.tryRecoverAfterConfirmedNativeStops(), isFalse,
        reason: 'The current book has its own native Stop still pending');
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(newEngine.spoken, isEmpty);

    newEngine.stopGate!.complete();
    await directPause;
    await handler.play(); // Now both actual Stop acknowledgments exist.
    await _settle();
    expect(newEngine.spoken, ['First']);
    expect(handler.requiresFreshAudioSession, isFalse);
    await handler.pause();
    await handler.close();
    oldPlayer.dispose();
    newPlayer.dispose();
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
