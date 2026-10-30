import 'dart:async';

import 'package:ereader/audio/system_voice_audition.dart';
import 'package:ereader/audio/speech_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSystemEngine implements SpeechEngine {
  _FakeSystemEngine({
    this.voices = const [
      SpeechVoice(name: 'Italian A', locale: 'it-IT'),
      SpeechVoice(name: 'English B', locale: 'en-GB'),
    ],
  });

  final List<SpeechVoice> voices;
  Completer<void>? catalogGate;
  Completer<void>? choiceGate;
  Completer<void>? speechGate;
  Completer<void>? stopGate;
  int catalogs = 0;
  int choices = 0;
  int speaks = 0;
  int stops = 0;
  int disposals = 0;
  SpeechVoice? selected;
  String? text;
  String? language;
  double? rate;
  double? pitch;

  @override
  Future<List<SpeechVoice>> listVoices() async {
    catalogs++;
    final gate = catalogGate;
    if (gate != null) await gate.future;
    return voices;
  }

  @override
  Future<void> chooseVoice(SpeechVoice voice) async {
    choices++;
    final gate = choiceGate;
    if (gate != null) await gate.future;
    selected = voice;
  }

  @override
  Future<void> speak(String phrase, {
    required String language,
    required double rate,
    required double pitch,
  }) async {
    speaks++;
    text = phrase;
    this.language = language;
    this.rate = rate;
    this.pitch = pitch;
    final gate = speechGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    final speaking = speechGate;
    if (speaking != null && !speaking.isCompleted) speaking.complete();
    final gate = stopGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected system preview state was not reached');
}

void main() {
  const italian = SpeechVoice(name: 'Italian A', locale: 'it-IT');
  const english = SpeechVoice(name: 'English B', locale: 'en-GB');

  test('sample text is fixed by language and never sourced from books', () {
    expect(systemVoiceSampleText('it-IT'), contains('Buongiorno'));
    expect(systemVoiceSampleText('en-GB'), contains('English'));
    expect(systemVoiceSampleText('fr-FR'), contains('française'));
    expect(systemVoiceSampleText('es-ES'), contains('española'));
    expect(systemVoiceSampleText('de-DE'), contains('deutschen'));
    expect(systemVoiceSampleText('pt-BR'), contains('portuguesa'));
    expect(systemVoiceSampleText('nl-NL'), contains('Nederlandse'));
    expect(systemVoiceSampleText('pl-PL'), contains('polskiego'));
    expect(systemVoiceSampleText('sv-SE'), contains('svensk'));
    expect(systemVoiceSampleText('ru-RU'), contains('русского'));
    expect(systemVoiceSampleText('ja-JP'), contains('日本語'));
    expect(systemVoiceSampleText('zh-CN'), contains('中文'));
    expect(systemVoiceSampleText('it_IT'),
        systemVoiceSampleText('it-IT'));
    expect(systemVoiceSampleText('xx-XX'), isNull);
  });

  test('catalog language filters group accents without selecting narrator',
      () {
    const voices = [
      SpeechVoice(name: 'Italian', locale: 'it-IT'),
      SpeechVoice(name: 'British', locale: 'en-GB'),
      SpeechVoice(name: 'American', locale: 'en_US'),
      SpeechVoice(name: 'French', locale: 'fr-FR'),
      SpeechVoice(name: '', locale: 'it-IT'),
      SpeechVoice(name: 'Missing', locale: ''),
    ];
    expect(systemVoiceCatalogLanguages(voices), ['en', 'fr', 'it']);
    expect(systemVoicePrimaryLanguage(' en_US '), 'en');
    expect(filterSystemVoiceCatalog(voices, 'en').map((v) => v.name),
        ['British', 'American']);
    expect(filterSystemVoiceCatalog(voices, 'it').single.name, 'Italian');
    expect(filterSystemVoiceCatalog(voices, null), hasLength(4));
    expect(() => filterSystemVoiceCatalog(voices, 'en').clear(),
        throwsUnsupportedError);
  });

  test('an unpinned or missing OS voice never becomes an implicit selection',
      () {
    const voices = [
      SpeechVoice(name: 'Italian A', locale: 'it-IT'),
      SpeechVoice(name: 'Italian B', locale: 'it-IT'),
    ];
    expect(resolveExplicitSystemVoice(voices,
        voiceName: null, voiceLocale: null), isNull);
    expect(resolveExplicitSystemVoice(voices,
        voiceName: 'Italian Z', voiceLocale: 'it-IT'), isNull);
    expect(resolveExplicitSystemVoice(voices,
        voiceName: 'Italian B', voiceLocale: 'it-IT')?.name, 'Italian B');
    expect(resolveExplicitSystemVoice(voices,
        voiceName: 'Italian B', voiceLocale: 'en-US'), isNull);
  });

  test('installed catalog is deduplicated and temporary engine disposed',
      () async {
    final fake = _FakeSystemEngine(voices: const [
      italian, italian,
      SpeechVoice(name: '', locale: 'it-IT'),
      english,
      SpeechVoice(name: 'Missing locale', locale: ''),
    ]);
    final audition = SystemVoiceAudition(createEngine: (_) => fake);
    final result = await audition.listVoices();
    expect(result.map((v) => v.key).toSet(),
        {italian.key, english.key});
    expect(fake.catalogs, 1);
    expect(fake.disposals, 1);
    expect(() => result.add(italian), throwsUnsupportedError);
    await audition.dispose();
  });

  test('audition uses chosen installed voice and source-independent text',
      () async {
    final fake = _FakeSystemEngine();
    final policies = <bool>[];
    final audition = SystemVoiceAudition(createEngine: (interpret) {
      policies.add(interpret);
      return fake;
    });
    await audition.play(italian,
        interpretWindowsPunctuation: true, rate: 0.65, pitch: 1.1);
    expect(policies, [true]);
    expect(fake.selected?.key, italian.key);
    expect(fake.text, systemVoiceSampleText('it-IT'));
    expect(fake.text, isNot(contains('Private ebook passage')));
    expect(fake.language, 'it-IT');
    expect(fake.rate, 0.65);
    expect(fake.pitch, 1.1);
    expect(fake.disposals, 1);
    expect(audition.isPlaying, isFalse);
    await audition.dispose();
  });

  test('missing OS voice fails before any speech', () async {
    final fake = _FakeSystemEngine(voices: const [english]);
    final audition = SystemVoiceAudition(createEngine: (_) => fake);
    await expectLater(audition.play(italian), throwsFormatException);
    expect(fake.choices, 0);
    expect(fake.speaks, 0);
    expect(fake.disposals, 1);
    await audition.dispose();
  });

  test('unsupported sample language and invalid pitch fail closed',
      () async {
    var created = 0;
    final audition = SystemVoiceAudition(createEngine: (_) {
      created++;
      return _FakeSystemEngine();
    });
    await expectLater(audition.play(
      const SpeechVoice(name: 'Unknown', locale: 'xx-XX')),
      throwsFormatException);
    await expectLater(audition.play(italian, pitch: double.nan),
        throwsFormatException);
    expect(created, 0);
    await audition.dispose();
  });

  test('Stop during blocked catalog prevents voice choice and speech',
      () async {
    final fake = _FakeSystemEngine()
      ..catalogGate = Completer<void>();
    final audition = SystemVoiceAudition(createEngine: (_) => fake);
    final reading = audition.play(italian);
    await _until(() => fake.catalogs == 1);
    expect(audition.isPlaying, isTrue);
    final stopping = audition.stop();
    fake.catalogGate!.complete();
    await Future.wait([stopping, reading]);
    expect(fake.choices, 0);
    expect(fake.speaks, 0);
    expect(fake.stops, 1);
    expect(fake.disposals, 1);
    expect(audition.isPlaying, isFalse);
    await audition.dispose();
  });

  test('Stop during delayed native voice selection prevents speech',
      () async {
    final fake = _FakeSystemEngine()
      ..choiceGate = Completer<void>();
    final audition = SystemVoiceAudition(createEngine: (_) => fake);
    final reading = audition.play(italian);
    await _until(() => fake.choices == 1);
    final stopping = audition.stop();
    fake.choiceGate!.complete();
    await Future.wait([stopping, reading]);
    expect(fake.speaks, 0);
    expect(fake.disposals, 1);
    await audition.dispose();
  });

  test('next audition waits for native Stop and Dispose barrier',
      () async {
    final first = _FakeSystemEngine()
      ..speechGate = Completer<void>()
      ..stopGate = Completer<void>();
    final second = _FakeSystemEngine();
    var created = 0;
    final audition = SystemVoiceAudition(createEngine: (_) =>
        created++ == 0 ? first : second);
    final reading = audition.play(italian);
    await _until(() => first.speaks == 1);
    final stopping = audition.stop();
    await reading;
    expect(audition.isPlaying, isFalse);
    expect(first.stops, 1);
    expect(first.disposals, 0,
        reason: 'Native stop must finish before the engine is disposed');
    final later = audition.play(english);
    await Future<void>.delayed(Duration.zero);
    expect(created, 1);
    expect(second.speaks, 0);
    first.stopGate!.complete();
    await stopping;
    await later;
    expect(first.disposals, 1);
    expect(second.speaks, 1);
    expect(second.language, 'en-GB');
    expect(second.disposals, 1);
    await audition.dispose();
  });

  test('catalog refresh cannot overlap an unfinished audition', () async {
    final fake = _FakeSystemEngine()..speechGate = Completer<void>();
    final audition = SystemVoiceAudition(createEngine: (_) => fake);
    final reading = audition.play(italian);
    await _until(() => fake.speaks == 1);
    await expectLater(audition.listVoices(), throwsStateError);
    await audition.stop();
    await reading;
    await audition.dispose();
  });

  test('preview cannot start while installed-voice lookup is pending',
      () async {
    final fake = _FakeSystemEngine()..catalogGate = Completer<void>();
    final audition = SystemVoiceAudition(createEngine: (_) => fake);
    final listing = audition.listVoices();
    await _until(() => fake.catalogs == 1);
    await expectLater(audition.play(italian), throwsStateError);
    fake.catalogGate!.complete();
    await listing;
    expect(fake.speaks, 0);
    await audition.dispose();
  });

  test('simultaneous Play is rejected rather than running two voices',
      () async {
    final fake = _FakeSystemEngine()
      ..speechGate = Completer<void>();
    final audition = SystemVoiceAudition(createEngine: (_) => fake);
    final running = audition.play(italian);
    await _until(() => fake.speaks == 1);
    await expectLater(audition.play(english), throwsStateError);
    await audition.stop();
    await running;
    expect(fake.speaks, 1);
    expect(fake.disposals, 1);
    await audition.dispose();
  });

  test('Dispose during a pending catalog cancels speech', () async {
    final fake = _FakeSystemEngine()
      ..catalogGate = Completer<void>();
    final audition = SystemVoiceAudition(createEngine: (_) => fake);
    final reading = audition.play(italian);
    await _until(() => fake.catalogs == 1);
    final closing = audition.dispose();
    fake.catalogGate!.complete();
    await Future.wait([closing, reading]);
    expect(fake.speaks, 0);
    expect(fake.disposals, 1);
    await expectLater(audition.play(italian), throwsStateError);
    await expectLater(audition.listVoices(), throwsStateError);
  });
}
