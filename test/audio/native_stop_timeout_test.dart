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

class _DisposalProbeEngine extends _HeldStopEngine {
  int disposalCalls = 0;
  bool disposedBeforeStopSettled = false;
  bool stopPending = false;
  Completer<void>? disposalGate;
  bool throwOnDispose = false;

  @override
  Future<void> stop() async {
    stopPending = true;
    try {
      await super.stop();
    } finally {
      stopPending = false;
    }
  }

  @override
  Future<void> dispose() async {
    disposalCalls++;
    disposedBeforeStopSettled |= stopPending;
    if (disposalGate != null) await disposalGate!.future;
    if (throwOnDispose) throw StateError('native disposal failed');
    await super.dispose();
  }
}

ReaderPlayer _player(
  _HeldStopEngine engine, {
  Duration nativeStopTimeout = const Duration(milliseconds: 15),
}) => ReaderPlayer(
  engine: engine,
  segments: const [
    SpeechSegment(0, 5, 'First'),
    SpeechSegment(6, 12, 'Second'),
  ],
  nativeStopTimeout: nativeStopTimeout,
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
    expect(handler.debugRetainedStopPlayers, 0,
        reason: 'Successful verified recovery drops all old players');
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

  test('terminal close releases failed Stop recovery sources',
      () async {
    final oldEngine = _HeldStopEngine()..throwOnStop = true;
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _settle();

    handler.attach(newPlayer, bookId: 'new', title: 'New');
    await expectLater(handler.play(), throwsStateError);
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(handler.debugRetainedStopPlayers, 1,
        reason: 'Keep the failed old player only while recovery is possible');

    await handler.close();
    expect(handler.debugRetainedStopPlayers, 0,
        reason: 'A closed handler cannot recover and must release old players');
    expect(handler.requiresFreshAudioSession, isTrue,
        reason: 'Discarding references must not turn a failed Stop into success');
    expect(handler.hasActiveBook, isFalse);
    await handler.close(); // repeated close is terminal and idempotent
    expect(handler.debugRetainedStopPlayers, 0);
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('late Stop completion after close cannot re-retain an old player',
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
    await handler.close().timeout(const Duration(seconds: 1));
    expect(handler.debugRetainedStopPlayers, 0);
    expect(oldPlayer.nativeStopUnconfirmed, isTrue);

    oldEngine.stopGate!.complete();
    await _settle();
    expect(handler.debugRetainedStopPlayers, 0);
    expect(handler.hasActiveBook, isFalse);
    expect(newEngine.spoken, isEmpty);
    oldPlayer.dispose();
    newPlayer.dispose();
  });

  test('player disposal waits for the in-flight native Stop', () async {
    final engine = _DisposalProbeEngine();
    final player = _player(engine);
    final reading = player.play();
    await _settle();
    expect(engine.spoken, ['First']);

    engine.stopGate = Completer<void>();
    final pause = player.pause();
    expect(engine.stopPending, isTrue);
    player.dispose();
    player.dispose();
    await _settle();
    expect(engine.disposalCalls, 0,
        reason: 'Dispose must not race an in-flight native Stop');

    engine.stopGate!.complete();
    await pause;
    await reading;
    await _settle();
    expect(engine.disposalCalls, 1);
    expect(engine.disposedBeforeStopSettled, isFalse);
  });

  test('late Stop acknowledgement retires the disposed engine once',
      () async {
    final engine = _DisposalProbeEngine();
    final player = _player(engine);
    final reading = player.play();
    await _settle();

    engine.stopGate = Completer<void>();
    await expectLater(player.pause(), throwsA(isA<SpeechStopTimeout>()));
    player.dispose();
    await _settle();
    expect(engine.disposalCalls, 0,
        reason: 'Timeout is not evidence that the native Stop settled');

    engine.stopGate!.complete();
    await reading;
    await _settle();
    expect(engine.disposalCalls, 1);
    expect(engine.disposedBeforeStopSettled, isFalse);
  });

  test('rejected native Stop still allows terminal engine disposal',
      () async {
    final engine = _DisposalProbeEngine()..throwOnStop = true;
    final player = _player(engine);
    final reading = player.play();
    await _settle();

    await expectLater(player.pause(), throwsStateError);
    player.dispose();
    await _settle();
    expect(engine.disposalCalls, 1,
        reason: 'An already settled exception must not leak the old engine');
    expect(engine.disposedBeforeStopSettled, isFalse);
    engine.completeSpeech();
    await reading;
  });

  test('idle player disposal retires its engine exactly once', () async {
    final engine = _DisposalProbeEngine();
    final player = _player(engine);
    player.dispose();
    player.dispose();
    await _settle();
    expect(engine.disposalCalls, 1);
    expect(engine.nativeStops, 0,
        reason: 'No Stop is needed for a never-started player');
  });

  test('old native engine disposal fences replacement Android speech',
      () async {
    final oldEngine = _DisposalProbeEngine();
    final nextEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final nextPlayer = _player(nextEngine);
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

    oldEngine.disposalGate = Completer<void>();
    handler.detach(oldPlayer);
    handler.retireDetachedPlayer(oldPlayer);
    handler.attach(nextPlayer, bookId: 'next', title: 'Next');
    final requestedPlay = handler.play();
    await _settle();
    expect(oldEngine.disposalCalls, 1);
    expect(oldPlayer.nativeEngineRetirementConfirmed, isFalse);
    expect(nextEngine.spoken, isEmpty);
    expect(focusRequests, 1,
        reason: 'New focus cannot start while old dispose might call Stop');

    oldEngine.disposalGate!.complete();
    await requestedPlay;
    await _settle();
    expect(oldPlayer.nativeEngineRetirementConfirmed, isTrue);
    expect(nextEngine.spoken, ['First']);
    expect(focusRequests, 2);
    await handler.pause();
    await handler.close();
    nextPlayer.dispose();
  });

  test('timed-out disposal requires late retirement confirmation to recover',
      () async {
    final oldEngine = _DisposalProbeEngine();
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _settle();

    oldEngine.disposalGate = Completer<void>();
    handler.detach(oldPlayer);
    handler.retireDetachedPlayer(oldPlayer);
    handler.attach(newPlayer, bookId: 'new', title: 'New');
    await expectLater(handler.play(), throwsStateError);
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(oldPlayer.nativeEngineRetirementConfirmed, isFalse);
    expect(await handler.tryRecoverAfterConfirmedNativeStops(), isFalse);
    expect(newEngine.spoken, isEmpty);

    oldEngine.disposalGate!.complete();
    await _settle();
    expect(oldPlayer.nativeEngineRetirementConfirmed, isTrue);
    await handler.play(); // New explicit request after confirmed disposal.
    await _settle();
    expect(handler.requiresFreshAudioSession, isFalse);
    expect(newEngine.spoken, ['First']);
    await handler.pause();
    await handler.close();
    newPlayer.dispose();
  });

  test('failed native disposal cannot rearm old engine on retry',
      () async {
    final oldEngine = _DisposalProbeEngine()..throwOnDispose = true;
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    await handler.play();
    await _settle();

    handler.detach(oldPlayer);
    handler.retireDetachedPlayer(oldPlayer);
    handler.attach(newPlayer, bookId: 'new', title: 'New');
    await expectLater(handler.play(), throwsStateError);
    expect(oldPlayer.nativeEngineRetirementConfirmed, isFalse);
    expect(handler.requiresFreshAudioSession, isTrue);
    await expectLater(handler.play(), throwsStateError);
    expect(newEngine.spoken, isEmpty);
    await handler.close();
    newPlayer.dispose();
  });

  test('obsolete screen defers its native Dispose until new narration pauses',
      () async {
    final oldEngine = _DisposalProbeEngine();
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    handler.attach(newPlayer, bookId: 'new', title: 'New');
    await handler.play();
    await _settle();
    expect(newEngine.spoken, ['First']);

    // The obsolete screen unmounts *after* the new one started speaking.
    handler.detach(oldPlayer); // Stale page must not clear new metadata.
    handler.retireDetachedPlayer(oldPlayer);
    await _settle();
    expect(oldEngine.disposalCalls, 0,
        reason: 'Old engine Dispose can stop global Android TTS');
    expect(handler.ownsPlayer(newPlayer), isTrue);
    expect(newPlayer.isPlaying, isTrue);

    await handler.pause(); // Confirm native silence on the current book.
    await _settle();
    expect(oldEngine.disposalCalls, 1);
    expect(oldPlayer.nativeEngineRetirementConfirmed, isTrue);

    await handler.play();
    await _settle();
    expect(newEngine.spoken, ['First', 'First']);
    await handler.pause();
    await handler.close();
    newPlayer.dispose();
  });

  test('late disposal cannot bypass Play waiting for Android focus',
      () async {
    final oldEngine = _DisposalProbeEngine();
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    final focusGate = Completer<bool>();
    var focusCalls = 0;
    final handler = ReaderMediaHandler(requestFocus: () {
      focusCalls++;
      return focusGate.future;
    });
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    handler.attach(newPlayer, bookId: 'new', title: 'New');
    final requestedPlay = handler.play();
    await _settle();
    expect(focusCalls, 1);
    oldEngine.disposalGate = Completer<void>();

    // Play has already checked the old stop barrier, but still awaits
    // Android focus. Retirement must be checked AGAIN after focus.
    handler.retireDetachedPlayer(oldPlayer);
    await _settle();
    expect(oldEngine.disposalCalls, 1);
    focusGate.complete(true);
    await _settle();
    expect(newEngine.spoken, isEmpty);

    oldEngine.disposalGate!.complete();
    await requestedPlay;
    await _settle();
    expect(newEngine.spoken, ['First']);
    await handler.pause();
    await handler.close();
    newPlayer.dispose();
  });

  test('Play rechecks a retirement added during the final Stop fence',
      () async {
    const timeout = Duration(seconds: 1);
    final firstEngine = _DisposalProbeEngine()
      ..disposalGate = Completer<void>();
    final lateEngine = _DisposalProbeEngine()
      ..disposalGate = Completer<void>();
    final currentEngine = _HeldStopEngine();
    final firstPlayer = _player(firstEngine, nativeStopTimeout: timeout);
    final latePlayer = _player(lateEngine, nativeStopTimeout: timeout);
    final currentPlayer = _player(currentEngine, nativeStopTimeout: timeout);
    final focusGate = Completer<bool>();
    final focusEntered = Completer<void>();
    final handler = ReaderMediaHandler(requestFocus: () {
      focusEntered.complete();
      return focusGate.future;
    });
    handler.attach(currentPlayer, bookId: 'current', title: 'Current');

    // Play has already seen the initial, successful transport barrier
    // and is paused waiting for Android focus.
    final requested = handler.play();
    await focusEntered.future;
    handler.retireDetachedPlayer(firstPlayer);
    await _settle();
    expect(firstEngine.disposalCalls, 1);

    // After focus settles, Play snapshots the first retirement barrier.
    // Register ANOTHER retirement while that snapshot is unresolved.
    focusGate.complete(true);
    await _settle();
    handler.retireDetachedPlayer(latePlayer);
    await _settle();
    expect(lateEngine.disposalCalls, 0);
    expect(currentEngine.spoken, isEmpty);

    firstEngine.disposalGate!.complete();
    for (var i = 0; i < 15 && lateEngine.disposalCalls == 0; i++) {
      await _settle();
    }
    expect(lateEngine.disposalCalls, 1);
    expect(currentEngine.spoken, isEmpty,
        reason: 'An older confirmed fence cannot authorize speech while '
            'another native Dispose is pending');
    lateEngine.disposalGate!.complete();
    await requested;
    await _settle();
    expect(currentEngine.spoken, ['First']);
    expect(firstPlayer.nativeEngineRetirementConfirmed, isTrue);
    expect(latePlayer.nativeEngineRetirementConfirmed, isTrue);
    await handler.pause();
    await handler.close();
    currentPlayer.dispose();
  });

  test('late failed retirement blocks Play and releases acquired focus',
      () async {
    const timeout = Duration(seconds: 1);
    final firstEngine = _DisposalProbeEngine()
      ..disposalGate = Completer<void>();
    final failedEngine = _DisposalProbeEngine()..throwOnDispose = true;
    final currentEngine = _HeldStopEngine();
    final firstPlayer = _player(firstEngine, nativeStopTimeout: timeout);
    final failedPlayer = _player(failedEngine, nativeStopTimeout: timeout);
    final currentPlayer = _player(currentEngine, nativeStopTimeout: timeout);
    final focusGate = Completer<bool>();
    final focusEntered = Completer<void>();
    var releases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () {
        focusEntered.complete();
        return focusGate.future;
      },
      releaseFocus: () async { releases++; },
    );
    handler.attach(currentPlayer, bookId: 'current', title: 'Current');
    final requested = handler.play();
    await focusEntered.future;
    handler.retireDetachedPlayer(firstPlayer);
    await _settle();
    focusGate.complete(true);
    await _settle();

    // The failed disposal is not in Play's first post-focus snapshot.
    handler.retireDetachedPlayer(failedPlayer);
    firstEngine.disposalGate!.complete();
    await expectLater(requested, throwsStateError);
    expect(failedEngine.disposalCalls, 1);
    expect(currentEngine.spoken, isEmpty,
        reason: 'A failed late native Dispose cannot be skipped');
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(releases, 1);
    await handler.close();
    currentPlayer.dispose();
  });

  test('late retirement waits for replacement book Stop during next handoff',
      () async {
    final oldEngine = _DisposalProbeEngine();
    final middleEngine = _HeldStopEngine();
    final currentEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final middlePlayer = _player(middleEngine);
    final currentPlayer = _player(currentEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    handler.attach(middlePlayer, bookId: 'middle', title: 'Middle');
    await handler.play();
    await _settle();
    expect(middleEngine.spoken, ['First']);

    handler.retireDetachedPlayer(oldPlayer);
    expect(oldEngine.disposalCalls, 0);
    middleEngine.stopGate = Completer<void>();
    handler.attach(currentPlayer, bookId: 'current', title: 'Current');
    final nextPlay = handler.play();
    await _settle();
    expect(oldEngine.disposalCalls, 0);
    expect(currentEngine.spoken, isEmpty);

    middleEngine.stopGate!.complete();
    await nextPlay;
    await _settle();
    expect(oldEngine.disposalCalls, 1);
    expect(currentEngine.spoken, ['First']);
    expect(handler.mediaItem.value?.id, 'current');
    await handler.pause();
    await handler.close();
    middlePlayer.dispose();
    currentPlayer.dispose();
  });

  test('unsafe outgoing Stop quarantines an older deferred Dispose',
      () async {
    final oldEngine = _DisposalProbeEngine();
    final middleEngine = _HeldStopEngine()..throwOnStop = true;
    final currentEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final middlePlayer = _player(middleEngine);
    final currentPlayer = _player(currentEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    handler.attach(middlePlayer, bookId: 'middle', title: 'Middle');
    await handler.play();
    await _settle();

    handler.retireDetachedPlayer(oldPlayer);
    expect(oldEngine.disposalCalls, 0);
    handler.attach(currentPlayer, bookId: 'current', title: 'Current');
    await expectLater(handler.play(), throwsStateError);
    await _settle();
    expect(oldEngine.disposalCalls, 0,
        reason: 'Failed current Stop cannot authorize old native disposal');
    expect(oldPlayer.nativeEngineRetirementConfirmed, isFalse);
    expect(currentEngine.spoken, isEmpty);
    expect(handler.requiresFreshAudioSession, isTrue);
    await handler.close();
    middleEngine.throwOnStop = false;
    middlePlayer.dispose();
    currentPlayer.dispose();
  });

  test('failed obsolete disposal releases late Android focus grant',
      () async {
    final oldEngine = _DisposalProbeEngine()..throwOnDispose = true;
    final newEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final newPlayer = _player(newEngine);
    final focusGate = Completer<bool>();
    var claims = 0;
    var releases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () {
        claims++;
        return focusGate.future;
      },
      releaseFocus: () async { releases++; },
    );
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    handler.attach(newPlayer, bookId: 'new', title: 'New');
    final requesting = handler.play();
    await _settle();
    expect(claims, 1);

    // This old-screen cleanup fails while the new book waits for focus.
    // It must not start new speech or strand a focus lease on failure.
    handler.retireDetachedPlayer(oldPlayer);
    await _settle();
    expect(oldEngine.disposalCalls, 1);
    expect(oldPlayer.nativeEngineRetirementConfirmed, isFalse);
    focusGate.complete(true);
    await expectLater(requesting, throwsStateError);
    expect(newEngine.spoken, isEmpty);
    expect(releases, 1,
        reason: 'Unsafe retirement must relinquish newly acquired focus');
    expect(handler.requiresFreshAudioSession, isTrue);
    await handler.close();
    expect(releases, 1);
    newPlayer.dispose();
  });

  test('multiple obsolete engines dispose one at a time before new Play',
      () async {
    final firstEngine = _DisposalProbeEngine()
      ..disposalGate = Completer<void>();
    final secondEngine = _DisposalProbeEngine()
      ..disposalGate = Completer<void>();
    final currentEngine = _HeldStopEngine();
    final firstPlayer = _player(firstEngine);
    final secondPlayer = _player(secondEngine);
    final currentPlayer = _player(currentEngine);
    var focusClaims = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusClaims++;
      return true;
    });
    handler.attach(firstPlayer, bookId: 'first', title: 'First');
    handler.attach(secondPlayer, bookId: 'second', title: 'Second');
    handler.attach(currentPlayer, bookId: 'current', title: 'Current');

    handler.retireDetachedPlayer(firstPlayer);
    handler.retireDetachedPlayer(secondPlayer);
    final pendingPlay = handler.play();
    await _settle();
    expect(firstEngine.disposalCalls, 1);
    expect(secondEngine.disposalCalls, 0,
        reason: 'The second native disposal must not overlap the first');
    expect(currentEngine.spoken, isEmpty);
    expect(focusClaims, 0);

    firstEngine.disposalGate!.complete();
    await _settle();
    expect(firstPlayer.nativeEngineRetirementConfirmed, isTrue);
    expect(secondEngine.disposalCalls, 1);
    expect(currentEngine.spoken, isEmpty);
    expect(focusClaims, 0);

    secondEngine.disposalGate!.complete();
    await pendingPlay;
    await _settle();
    expect(secondPlayer.nativeEngineRetirementConfirmed, isTrue);
    expect(currentEngine.spoken, ['First']);
    expect(focusClaims, 1);
    await handler.pause();
    await handler.close();
    currentPlayer.dispose();
  });

  test('stuck first disposal keeps subsequent disposal quarantined',
      () async {
    final firstEngine = _DisposalProbeEngine()
      ..disposalGate = Completer<void>();
    final secondEngine = _DisposalProbeEngine()
      ..disposalGate = Completer<void>();
    final currentEngine = _HeldStopEngine();
    final firstPlayer = _player(firstEngine);
    final secondPlayer = _player(secondEngine);
    final currentPlayer = _player(currentEngine);
    var focusClaims = 0;
    final handler = ReaderMediaHandler(requestFocus: () async {
      focusClaims++;
      return true;
    });
    handler.attach(firstPlayer, bookId: 'first', title: 'First');
    handler.attach(secondPlayer, bookId: 'second', title: 'Second');
    handler.attach(currentPlayer, bookId: 'current', title: 'Current');
    handler.retireDetachedPlayer(firstPlayer);
    handler.retireDetachedPlayer(secondPlayer);

    await expectLater(handler.play().timeout(const Duration(seconds: 1)),
        throwsStateError);
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(firstEngine.disposalCalls, 1);
    expect(secondEngine.disposalCalls, 0);
    expect(currentEngine.spoken, isEmpty);
    expect(focusClaims, 0);

    // A very late native acknowledgment may permit the second Dispose,
    // but neither late callback starts speech automatically.
    firstEngine.disposalGate!.complete();
    await _settle();
    expect(secondEngine.disposalCalls, 1);
    expect(currentEngine.spoken, isEmpty);
    secondEngine.disposalGate!.complete();
    await _settle();
    expect(firstPlayer.nativeEngineRetirementConfirmed, isTrue);
    expect(secondPlayer.nativeEngineRetirementConfirmed, isTrue);

    await handler.play(); // A NEW explicit request verifies both engines.
    await _settle();
    expect(handler.requiresFreshAudioSession, isFalse);
    expect(currentEngine.spoken, ['First']);
    expect(focusClaims, 1);
    await handler.pause();
    await handler.close();
    currentPlayer.dispose();
  });

  test('failed prior Dispose prevents a later native Dispose from starting',
      () async {
    final firstEngine = _DisposalProbeEngine()..throwOnDispose = true;
    final secondEngine = _DisposalProbeEngine();
    final currentEngine = _HeldStopEngine();
    final firstPlayer = _player(firstEngine);
    final secondPlayer = _player(secondEngine);
    final currentPlayer = _player(currentEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(firstPlayer, bookId: 'first', title: 'First');
    handler.attach(secondPlayer, bookId: 'second', title: 'Second');
    handler.attach(currentPlayer, bookId: 'current', title: 'Current');

    handler.retireDetachedPlayer(firstPlayer);
    handler.retireDetachedPlayer(secondPlayer);
    await expectLater(handler.play(), throwsStateError);
    expect(firstEngine.disposalCalls, 1);
    expect(secondEngine.disposalCalls, 0,
        reason: 'Failed global cleanup cannot authorize another native Stop');
    expect(secondPlayer.nativeEngineRetirementConfirmed, isFalse);
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(currentEngine.spoken, isEmpty);
    await handler.close();
    currentPlayer.dispose();
  });

  test('close bounds multiple deferred disposals after outgoing Stop hangs',
      () async {
    final firstEngine = _DisposalProbeEngine();
    final secondEngine = _DisposalProbeEngine();
    final currentEngine = _HeldStopEngine();
    final firstPlayer = _player(firstEngine);
    final secondPlayer = _player(secondEngine);
    final currentPlayer = _player(currentEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(firstPlayer, bookId: 'first', title: 'First');
    handler.attach(secondPlayer, bookId: 'second', title: 'Second');
    handler.attach(currentPlayer, bookId: 'current', title: 'Current');
    await handler.play();
    await _settle();
    expect(currentEngine.spoken, ['First']);

    handler.retireDetachedPlayer(firstPlayer);
    handler.retireDetachedPlayer(secondPlayer);
    expect(firstEngine.disposalCalls, 0);
    expect(secondEngine.disposalCalls, 0);
    currentEngine.stopGate = Completer<void>();

    await handler.close().timeout(const Duration(seconds: 1));
    expect(handler.hasActiveBook, isFalse);
    expect(firstEngine.disposalCalls, 0);
    expect(secondEngine.disposalCalls, 0);
    expect(currentPlayer.nativeStopUnconfirmed, isTrue);
    expect(handler.debugRetainedStopPlayers, 0,
        reason: 'Terminal close clears failed player references');
    currentEngine.stopGate!.complete();
    await _settle();
    expect(firstEngine.disposalCalls, 0);
    expect(secondEngine.disposalCalls, 0);
    firstPlayer.dispose();
    secondPlayer.dispose();
    currentPlayer.dispose();
  });

  test('duplicate retirement cannot poison a live reader during pause',
      () async {
    final oldEngine = _DisposalProbeEngine();
    final currentEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final currentPlayer = _player(currentEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    handler.attach(currentPlayer, bookId: 'current', title: 'Current');
    await handler.play();
    await _settle();
    expect(currentEngine.spoken, ['First']);

    // An obsolete page can receive two teardown/lifecycle notifications
    // while the current page is still narrating. Retirement is allowed to
    // wait indefinitely for quiet, not to create a duplicate 15ms deadline.
    handler.retireDetachedPlayer(oldPlayer);
    handler.retireDetachedPlayer(oldPlayer);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(oldEngine.disposalCalls, 0);
    expect(currentEngine.spoken, ['First']);

    await handler.pause();
    await _settle();
    expect(oldEngine.disposalCalls, 1);
    expect(oldPlayer.nativeEngineRetirementConfirmed, isTrue);
    expect(handler.requiresFreshAudioSession, isFalse,
        reason: 'Duplicate teardown must not create a false unsafe fence');

    await handler.play();
    await _settle();
    expect(currentEngine.spoken, ['First', 'First']);
    handler.retireDetachedPlayer(oldPlayer); // Even after native completion.
    await _settle();
    expect(oldEngine.disposalCalls, 1);
    await handler.pause();
    await handler.close();
    currentPlayer.dispose();
  });

  test('late obsolete retirement waits for the last detached native Stop',
      () async {
    final oldEngine = _DisposalProbeEngine();
    final outgoingEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final outgoingPlayer = _player(outgoingEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    handler.attach(outgoingPlayer, bookId: 'outgoing', title: 'Outgoing');
    await handler.play();
    await _settle();
    expect(outgoingEngine.spoken, ['First']);

    outgoingEngine.stopGate = Completer<void>();
    handler.detach(outgoingPlayer);
    // There is no currently attached book now. Previously this allowed
    // a late obsolete engine Dispose to bypass the outstanding Stop.
    handler.retireDetachedPlayer(oldPlayer);
    await _settle();
    expect(oldEngine.disposalCalls, 0);
    expect(outgoingEngine.nativeStops, 1);

    outgoingEngine.stopGate!.complete();
    for (var i = 0; i < 10 && oldEngine.disposalCalls == 0; i++) {
      await _settle();
    }
    expect(oldEngine.disposalCalls, 1);
    expect(oldPlayer.nativeEngineRetirementConfirmed, isTrue);
    await handler.close();
    outgoingPlayer.dispose();
  });

  test('failed detached Stop quarantines a late obsolete retirement',
      () async {
    final oldEngine = _DisposalProbeEngine();
    final outgoingEngine = _HeldStopEngine();
    final oldPlayer = _player(oldEngine);
    final outgoingPlayer = _player(outgoingEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(oldPlayer, bookId: 'old', title: 'Old');
    handler.attach(outgoingPlayer, bookId: 'outgoing', title: 'Outgoing');
    await handler.play();
    await _settle();

    outgoingEngine.stopGate = Completer<void>();
    handler.detach(outgoingPlayer);
    handler.retireDetachedPlayer(oldPlayer);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(oldEngine.disposalCalls, 0,
        reason: 'A timed-out Stop cannot authorize a native Dispose');
    await handler.close();
    outgoingEngine.stopGate!.complete();
    await _settle();
    expect(oldEngine.disposalCalls, 0,
        reason: 'A failed disposal gate must not silently re-arm');
    outgoingPlayer.dispose();
  });

  test('retirement of the still-bound reader detaches before native Dispose',
      () async {
    final activeEngine = _DisposalProbeEngine();
    final replacementEngine = _HeldStopEngine();
    final activePlayer = _player(activeEngine);
    final replacementPlayer = _player(replacementEngine);
    var focusReleases = 0;
    final handler = ReaderMediaHandler(
      requestFocus: () async => true,
      releaseFocus: () async { focusReleases++; },
    );
    handler.attach(activePlayer, bookId: 'active', title: 'Active');
    await handler.play();
    await _settle();
    expect(activeEngine.spoken, ['First']);

    activeEngine.stopGate = Completer<void>();
    // Deliberately skip ReaderScreen.detach: a duplicate or out-of-order
    // lifecycle notification must not dispose a still-speaking engine.
    handler.retireDetachedPlayer(activePlayer);
    expect(handler.hasActiveBook, isFalse);
    expect(handler.mediaItem.value, isNull);
    expect(activePlayer.isPlaying, isFalse);
    await _settle();
    expect(activeEngine.nativeStops, 1);
    expect(activeEngine.disposalCalls, 0,
        reason: 'Dispose cannot overlap a live native Stop');

    handler.attach(replacementPlayer,
        bookId: 'replacement', title: 'Replacement');
    final newPlay = handler.play();
    await _settle();
    expect(replacementEngine.spoken, isEmpty);
    expect(activeEngine.disposalCalls, 0);

    activeEngine.stopGate!.complete();
    await newPlay;
    await _settle();
    expect(activeEngine.disposalCalls, 1);
    expect(activeEngine.disposedBeforeStopSettled, isFalse);
    expect(activePlayer.nativeEngineRetirementConfirmed, isTrue);
    expect(replacementEngine.spoken, ['First']);
    expect(handler.ownsPlayer(replacementPlayer), isTrue);
    await handler.pause();
    await handler.close();
    expect(focusReleases, greaterThanOrEqualTo(1));
    replacementPlayer.dispose();
  });

  test('active retirement with failed Stop quarantines its engine',
      () async {
    final engine = _DisposalProbeEngine()..throwOnStop = true;
    final player = _player(engine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);
    handler.attach(player, bookId: 'active', title: 'Active');
    await handler.play();
    await _settle();
    expect(engine.spoken, ['First']);

    handler.retireDetachedPlayer(player);
    await _settle();
    expect(handler.hasActiveBook, isFalse);
    expect(engine.nativeStops, 1);
    expect(engine.disposalCalls, 0,
        reason: 'Failed native Stop must not trigger a global Dispose');
    expect(player.nativeEngineRetirementConfirmed, isFalse);
    expect(handler.requiresFreshAudioSession, isTrue);
    await handler.close();
    expect(engine.disposalCalls, 0);
    engine.completeSpeech();
  });


  test('confirmed recovery resets detached Stop fence for later disposal',
      () async {
    final staleEngine = _DisposalProbeEngine();
    final blockedEngine = _HeldStopEngine();
    final newEngine = _HeldStopEngine();
    final stale = _player(staleEngine);
    final blocked = _player(blockedEngine);
    final current = _player(newEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);

    handler.attach(stale, bookId: 'stale', title: 'Stale');
    handler.attach(blocked, bookId: 'blocked', title: 'Blocked');
    await handler.play();
    await _settle();
    blockedEngine.stopGate = Completer<void>();
    handler.attach(current, bookId: 'current', title: 'Current');
    await expectLater(handler.play().timeout(const Duration(seconds: 1)),
        throwsStateError);
    expect(handler.requiresFreshAudioSession, isTrue);
    expect(newEngine.spoken, isEmpty);

    blockedEngine.stopGate!.complete();
    await _settle();
    expect(await blocked.waitForNativeStopConfirmation(), isTrue);
    expect(newEngine.spoken, isEmpty,
        reason: 'A late native callback cannot automatically resume');
    await handler.play(); // Explicit recovery after a positive native Stop.
    await _settle();
    expect(handler.requiresFreshAudioSession, isFalse);
    expect(handler.debugRetainedStopPlayers, 0);
    expect(newEngine.spoken, ['First']);

    handler.retireDetachedPlayer(stale);
    await _settle();
    expect(staleEngine.disposalCalls, 0,
        reason: 'Dispose must await the currently speaking book');
    await handler.pause();
    expect(
      await stale.engineRetirementCompletion.timeout(const Duration(seconds: 1)),
      isTrue,
      reason: 'Only confirmed silence may release a later native Dispose',
    );
    expect(staleEngine.disposalCalls, 1,
        reason: 'An earlier recovered timeout must not poison future Dispose');
    expect(stale.nativeEngineRetirementConfirmed, isTrue);
    expect(handler.requiresFreshAudioSession, isFalse);
    await handler.close();
    blocked.dispose();
    current.dispose();
  });

  test('failed native Stop keeps later obsolete disposal quarantined',
      () async {
    final staleEngine = _DisposalProbeEngine();
    final failedEngine = _HeldStopEngine()..throwOnStop = true;
    final currentEngine = _HeldStopEngine();
    final stale = _player(staleEngine);
    final failed = _player(failedEngine);
    final current = _player(currentEngine);
    final handler = ReaderMediaHandler(requestFocus: () async => true);

    handler.attach(stale, bookId: 'stale', title: 'Stale');
    handler.attach(failed, bookId: 'failed', title: 'Failed');
    await handler.play();
    await _settle();
    handler.attach(current, bookId: 'new', title: 'New');
    await expectLater(handler.play(), throwsStateError);
    expect(await handler.tryRecoverAfterConfirmedNativeStops(), isFalse);
    expect(handler.requiresFreshAudioSession, isTrue);
    handler.retireDetachedPlayer(stale);
    await _settle();
    expect(staleEngine.disposalCalls, 0);
    expect(currentEngine.spoken, isEmpty);
    await handler.close();
    expect(staleEngine.disposalCalls, 0);
    failed.dispose();
    current.dispose();
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
