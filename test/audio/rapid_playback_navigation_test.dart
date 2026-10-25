import 'dart:async';

import 'package:ereader/audio/reader_player.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/domain/speech_segment.dart';
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
