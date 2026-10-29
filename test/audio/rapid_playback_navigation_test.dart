import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

class _SlowVoiceEngine implements SpeechEngine {
  final spoken = <String>[];
  final rates = <double>[];
  final chosen = <String>[];
  final utterances = <Completer<void>>[];
  Completer<void>? stopGate;
  Completer<void>? voiceGate;
  String? activeVoice;
  int stops = 0;

  @override
  Future<List<SpeechVoice>> listVoices() async => const [
    SpeechVoice(name: 'Narrator', locale: 'en-US'),
    SpeechVoice(name: 'First', locale: 'en-US'),
    SpeechVoice(name: 'Second', locale: 'en-US'),
  ];

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {
    chosen.add(voice.name);
    final gate = voiceGate;
    if (gate != null) await gate.future;
    activeVoice = voice.name;
  }

  @override
  Future<void> speak(String text, {
    required String language,
    required double rate,
    required double pitch,
  }) {
    spoken.add(text);
    rates.add(rate);
    final waiting = Completer<void>();
    utterances.add(waiting);
    return waiting.future;
  }

  void finish() {
    for (final item in utterances) {
      if (!item.isCompleted) item.complete();
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    final gate = stopGate;
    if (gate != null) await gate.future;
    finish();
  }

  @override
  Future<void> dispose() => stop();
}

Future<void> _until(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('The expected player session state was never reached');
}

void main() {
  late _SlowVoiceEngine engine;
  late ReaderPlayer player;

  setUp(() async {
    engine = _SlowVoiceEngine();
    player = ReaderPlayer(
      engine: engine,
      segments: const [
        SpeechSegment(0, 3, 'One'),
        SpeechSegment(4, 7, 'Two'),
        SpeechSegment(8, 13, 'Three'),
      ],
      onSegmentStarted: (_) async {},
    );
    await player.loadVoices();
  });

  tearDown(() async {
    engine.stopGate?.completeIfPending();
    engine.voiceGate?.completeIfPending();
    if (!player.isPlaying) {
      player.dispose();
    } else {
      await player.pause();
      player.dispose();
    }
  });

  test('visual-only EOF seek never replays the previous spoken clip',
      () async {
    final running = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.stopGate = Completer<void>();
    final visualEnd = player.seekToSourceEnd();
    expect(player.isPlaying, isFalse);
    expect(player.isSettledIdle, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['One']);
    engine.stopGate!.complete();
    await visualEnd;
    await running;
    expect(player.currentIndex, player.segments.length);
    expect(player.isSettledIdle, isTrue);
    expect(engine.spoken, ['One'],
        reason: 'Silent trailing EPUB section has no TTS request');

    // Explicit Play at completed speech EOF is a fresh user-initiated
    // restart, not a delayed auto-resume from the chapter jump.
    final restarted = player.play();
    await _until(() => engine.spoken.length == 2);
    expect(engine.spoken, ['One', 'One']);
    await player.pause();
    await restarted;
  });

  test('silent source navigation supersedes pending auto-resuming Seek',
      () async {
    final running = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.stopGate = Completer<void>();
    final stale = player.seekTo(2);
    final finalVisualDestination = player.seekToSourceEnd();
    await Future<void>.delayed(Duration.zero);
    expect(engine.spoken, ['One']);
    engine.stopGate!.complete();
    await Future.wait([stale, finalVisualDestination, running]);
    expect(player.currentIndex, player.segments.length);
    expect(player.isPlaying, isFalse);
    expect(engine.spoken, ['One'],
        reason: 'Old Seek may not narrate Third after final visual jump');
  });

  test('rapid seeks retain only the last target and still resume once',
      () async {
    final initial = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.stopGate = Completer<void>();
    final older = player.seekTo(1);
    final latest = player.seekTo(2);
    expect(engine.spoken, ['One']);
    engine.stopGate!.complete();
    await Future.wait([older, latest]);
    await initial;
    await _until(() => engine.spoken.length == 2);
    expect(engine.spoken, ['One', 'Three']);
    expect(player.currentIndex, 2);
    engine.finish();
    await _until(() => !player.isPlaying);
    expect(player.currentIndex, 3);
  });

  test('explicit pause supersedes an outstanding auto-resuming seek',
      () async {
    final initial = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.stopGate = Completer<void>();
    final seek = player.seekTo(2);
    final stop = player.pause();
    engine.stopGate!.complete();
    await Future.wait([seek, stop, initial]);
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    expect(player.currentIndex, 0);
    expect(engine.spoken, ['One']);
  });

  test('two overlapping native voice choices preserve the last choice',
      () async {
    const narrator = SpeechVoice(name: 'Narrator', locale: 'en-US');
    const first = SpeechVoice(name: 'First', locale: 'en-US');
    const second = SpeechVoice(name: 'Second', locale: 'en-US');
    await player.selectVoice(narrator);
    final initial = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.voiceGate = Completer<void>();
    final old = player.selectVoice(first);
    await _until(() => engine.chosen.contains('First'));
    final newer = player.selectVoice(second);
    engine.voiceGate!.complete();
    await Future.wait([old, newer, initial]);
    await _until(() => engine.spoken.length == 2);
    expect(player.selectedVoice?.name, 'Second');
    expect(engine.activeVoice, 'Second');
    expect(engine.spoken, ['One', 'One']);
    engine.finish();
  });

  test('committed speed restarts same source segment, not another chapter',
      () async {
    final initial = player.play();
    await _until(() => engine.spoken.length == 1);
    player.setRate(0.9);
    await player.restartAfterSettingsChange();
    await initial;
    await _until(() => engine.spoken.length == 2);
    expect(engine.spoken, ['One', 'One']);
    expect(engine.rates, [0.5, 0.9]);
    expect(player.currentIndex, 0);
    engine.finish();
  });

  test('settings commit during an explicit pause does not auto-play',
      () async {
    final initial = player.play();
    await _until(() => engine.spoken.length == 1);
    await player.pause();
    await initial;
    player.setPitch(1.2);
    player.setRate(0.7);
    await player.restartAfterSettingsChange();
    expect(player.isPlaying, isFalse);
    expect(engine.spoken, ['One']);
  });

  test('dispose during an outstanding voice change prevents later speech',
      () async {
    const a = SpeechVoice(name: 'First', locale: 'en-US');
    final initial = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.voiceGate = Completer<void>();
    final switching = player.selectVoice(a);
    await _until(() => engine.chosen.contains('First'));
    player.dispose();
    engine.voiceGate!.complete();
    await switching;
    await initial;
    await player.play();
    expect(engine.spoken, ['One']);
  });

  test('direct Play supersedes a blocked seek without a late jump',
      () async {
    final first = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.stopGate = Completer<void>();
    final outdatedSeek = player.seekTo(2);
    final direct = player.play();
    engine.stopGate!.complete();
    await outdatedSeek;
    await first;
    await _until(() => engine.spoken.length == 2);
    expect(engine.spoken, ['One', 'One']);
    expect(player.currentIndex, 0);
    // A direct Play resumes the complete three-segment queue, not just
    // the first restarted utterance. Resolve each mock segment explicitly
    // before awaiting the full-book play() future.
    engine.finish();
    await _until(() => engine.spoken.length == 3);
    expect(engine.spoken.last, 'Two');
    engine.finish();
    await _until(() => engine.spoken.length == 4);
    expect(engine.spoken.last, 'Three');
    engine.finish();
    await direct;
    expect(player.currentIndex, 3);
  });

  test('changing narrator voice while paused does not start narration',
      () async {
    const voice = SpeechVoice(name: 'Second', locale: 'en-US');
    await player.selectVoice(voice);
    expect(player.selectedVoice?.name, 'Second');
    expect(engine.activeVoice, 'Second');
    expect(engine.spoken, isEmpty);
    expect(player.isPlaying, isFalse);
  });

  test('latest saved voice preference overrides an unfinished manual choice',
      () async {
    const narrator = SpeechVoice(name: 'Narrator', locale: 'en-US');
    const first = SpeechVoice(name: 'First', locale: 'en-US');
    await player.selectVoice(narrator);
    engine.voiceGate = Completer<void>();
    final stale = player.selectVoice(first);
    await _until(() => engine.chosen.contains('First'));

    final restored = player.applyPreferences(const SpeechPreferences(
      language: 'en-US', rate: 0.7, pitch: 1.2,
      voiceName: 'Second', voiceLocale: 'en-US',
    ));
    await Future<void>.delayed(Duration.zero);
    expect(engine.chosen, ['Narrator', 'First'],
        reason: 'Native choice from the saved profile waits for old choice');
    engine.voiceGate!.complete();
    await Future.wait([stale, restored]);

    expect(engine.chosen, ['Narrator', 'First', 'Second']);
    expect(engine.activeVoice, 'Second');
    expect(player.selectedVoice?.name, 'Second');
    expect(player.currentPreferences.rate, 0.7);
    expect(player.currentPreferences.pitch, 1.2);
    expect(engine.spoken, isEmpty,
        reason: 'Applying preferences while idle must never auto-play');
  });

  test('two overlapping book profiles retain only the newest settings',
      () async {
    engine.voiceGate = Completer<void>();
    final stale = player.applyPreferences(const SpeechPreferences(
      language: 'en-US', rate: 0.8, voiceName: 'First',
      voiceLocale: 'en-US',
    ));
    await _until(() => engine.chosen.contains('First'));
    final latest = player.applyPreferences(const SpeechPreferences(
      language: 'en-US', rate: 0.3, voiceName: 'Second',
      voiceLocale: 'en-US',
    ));
    engine.voiceGate!.complete();
    await Future.wait([stale, latest]);

    expect(engine.chosen, ['First', 'Second']);
    expect(player.selectedVoice?.name, 'Second');
    expect(engine.activeVoice, 'Second');
    expect(player.currentPreferences.rate, 0.3);
    expect(engine.spoken, isEmpty);
  });

  test('restoring preferences during speech stops without auto-resume',
      () async {
    final initial = player.play();
    await _until(() => engine.spoken.length == 1);
    await player.applyPreferences(const SpeechPreferences(
      language: 'en-US', voiceName: 'Second',
      voiceLocale: 'en-US', rate: 0.9,
    ));
    await initial;
    expect(player.isPlaying, isFalse);
    expect(player.currentIndex, 0,
        reason: 'An interrupted utterance remains the resume position');
    expect(player.selectedVoice?.name, 'Second');
    expect(player.currentPreferences.rate, 0.9);
    expect(engine.spoken, ['One']);
  });

  test('restoring preferences supersedes delayed auto-resuming Seek',
      () async {
    final initial = player.play();
    await _until(() => engine.spoken.length == 1);
    engine.stopGate = Completer<void>();
    final staleSeek = player.seekTo(2);
    final restore = player.applyPreferences(const SpeechPreferences(
      language: 'en-US', voiceName: 'Second', voiceLocale: 'en-US',
    ));
    expect(player.isPlaying, isFalse);
    engine.stopGate!.complete();
    await Future.wait([staleSeek, restore, initial]);

    expect(player.currentIndex, 0,
        reason: 'An obsolete Seek cannot move the active reading cursor');
    expect(player.selectedVoice?.name, 'Second');
    expect(engine.spoken, ['One'],
        reason: 'Restoring a saved voice does not resume abandoned Seek');
  });

  test('invalid provider cannot change in-flight navigation or voice',
      () async {
    await player.selectVoice(
        const SpeechVoice(name: 'First', locale: 'en-US'));
    await expectLater(
      player.applyPreferences(const SpeechPreferences(
          providerId: 'openai-speech')),
      throwsUnsupportedError,
    );
    expect(player.selectedVoice?.name, 'First');
    expect(engine.activeVoice, 'First');
    expect(engine.spoken, isEmpty);
  });

  test('direct Play is denied after disposal', () async {
    player.dispose();
    await player.play();
    expect(engine.spoken, isEmpty);
  });
}

extension _CompletePending on Completer<void> {
  void completeIfPending() {
    if (!isCompleted) complete();
  }
}
