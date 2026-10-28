import 'dart:async';

import 'package:ereader/audio/offline_voice_audition.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:ereader/data/offline_voice_pack.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeOfflineEngine implements SpeechEngine {
  int speaks = 0;
  int stops = 0;
  int disposals = 0;
  SpeechVoice? voice;
  String? spoken;
  String? language;
  double? rate;
  double? pitch;
  Completer<void>? pending;

  @override
  Future<List<SpeechVoice>> listVoices() async => const [
    SpeechVoice(name: 'italian', locale: 'it-IT'),
  ];

  @override
  Future<void> chooseVoice(SpeechVoice selection) async {
    voice = selection;
  }

  @override
  Future<void> speak(String text, {required String language,
      required double rate, required double pitch}) async {
    speaks++;
    spoken = text;
    this.language = language;
    this.rate = rate;
    this.pitch = pitch;
    final waiting = pending;
    if (waiting != null) await waiting.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (pending != null && !pending!.isCompleted) pending!.complete();
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

InstalledOfflineVoicePack samplePack({String id = 'italian',
    String locale = 'it-IT', bool withPhonemizer = true}) =>
    InstalledOfflineVoicePack(
      manifest: OfflineVoicePackManifest(
        id: id,
        displayName: 'Local preview',
        locale: locale,
        licenseId: 'MIT',
        modelSha256: 'a' * 64,
        tokensSha256: 'b' * 64,
        phonemizerResources: withPhonemizer
            ? const [OfflineVoiceResource(
                relativePath: 'espeak-ng-data/phonemes',
                sha256: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
              )] : const [],
      ),
      modelPath: '/private/models/$id/model.onnx',
      tokensPath: '/private/models/$id/tokens.txt',
    );

void main() {
  test('sample is a fixed local phrase, never sourced from an ebook', () async {
    final fake = FakeOfflineEngine();
    var loads = 0;
    final audition = OfflineVoiceAudition(
      loadPack: (id) async { loads++; return samplePack(id: id); },
      createEngine: (_) => fake,
    );
    await audition.play('italian');
    expect(loads, 1);
    expect(fake.speaks, 1);
    expect(fake.spoken, offlineVoiceSampleText('it-IT'));
    expect(fake.spoken, contains('senza inviare'));
    expect(fake.voice!.name, 'italian');
    expect(fake.language, 'it-IT');
    expect(fake.rate, 0.5);
    expect(fake.pitch, 1);
    expect(fake.disposals, 1);
    await audition.dispose();
  });

  test('Stop during pack verification prevents all native audio', () async {
    final verification = Completer<InstalledOfflineVoicePack>();
    var creations = 0;
    final audition = OfflineVoiceAudition(
      loadPack: (_) => verification.future,
      createEngine: (_) { creations++; return FakeOfflineEngine(); },
    );
    final requested = audition.play('italian');
    await audition.stop();
    verification.complete(samplePack());
    await requested;
    expect(creations, 0);
    expect(audition.isPlaying, isFalse);
    await audition.dispose();
  });

  test('Stop cancels speech and releases exactly one native engine',
      () async {
    final fake = FakeOfflineEngine()..pending = Completer<void>();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    final requested = audition.play('italian');
    // Allow the Future to cross pack-load and voice selection.
    await Future<void>.delayed(Duration.zero);
    expect(fake.speaks, 1);
    await audition.stop();
    await requested;
    expect(fake.stops, 1);
    expect(fake.disposals, 1);
    expect(audition.isPlaying, isFalse);
    await audition.dispose();
    expect(fake.disposals, 1);
  });

  test('wrong model identity or missing phonemizer cannot reach native FFI',
      () async {
    var creations = 0;
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(id: 'different'),
      createEngine: (_) { creations++; return FakeOfflineEngine(); },
    );
    await expectLater(audition.play('italian'), throwsFormatException);
    expect(creations, 0);
    await audition.dispose();
    final missing = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(withPhonemizer: false),
      createEngine: (_) { creations++; return FakeOfflineEngine(); },
    );
    await expectLater(missing.play('italian'), throwsFormatException);
    expect(creations, 0);
    await missing.dispose();
  });

  test('unsupported language never synthesizes a mismatched sample',
      () async {
    var creations = 0;
    expect(offlineVoiceSampleText('fr-FR'), isNull);
    expect(offlineVoiceSampleText('en-GB'), isNotNull);
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(locale: 'fr-FR'),
      createEngine: (_) { creations++; return FakeOfflineEngine(); },
    );
    await expectLater(audition.play('italian'), throwsFormatException);
    expect(creations, 0);
    await audition.dispose();
  });

  test('concurrent preview is rejected, not allowed to synthesize twice',
      () async {
    final fake = FakeOfflineEngine()..pending = Completer<void>();
    final audition = OfflineVoiceAudition(
      loadPack: (_) async => samplePack(),
      createEngine: (_) => fake,
    );
    final first = audition.play('italian');
    await expectLater(audition.play('italian'), throwsStateError);
    await audition.stop();
    await first;
    expect(fake.speaks, lessThanOrEqualTo(1));
    await audition.dispose();
  });
}
