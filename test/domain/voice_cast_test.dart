import 'package:ereader/domain/reading_anchor.dart';
import 'package:ereader/domain/speech_segment.dart';
import 'package:ereader/domain/voice_cast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = SpeechSegment(10, 22, '"Hello there"');
  final mark = SegmentCastAssignment(
    bookId: 'book-1', start: 10, end: 23,
    sourceDigest: SegmentCastAssignment.fingerprint(source.text),
    characterId: 'char-1',
    anchor: const ReadingAnchor(
      kind: AnchorKind.epubSpine, sourceId: 'scene-2', localOffset: 5),
  );
  final voices = [
    const CastVoiceAssignment(characterId: 'char-1', providerId: 'system',
        voiceName: 'Voice A', voiceLocale: 'en-US'),
    const CastVoiceAssignment(characterId: 'char-1',
        providerId: 'openai-speech', voiceName: 'marin', voiceLocale: 'multi'),
  ];

  test('valid exact source mapping resolves correct speaker and provider', () {
    final valid = SegmentCastAssignment(
      bookId: 'book-1', start: source.start, end: source.end,
      sourceDigest: SegmentCastAssignment.fingerprint(source.text),
      characterId: 'char-1',
      anchor: const ReadingAnchor(
        kind: AnchorKind.epubSpine, sourceId: 'scene-2', localOffset: 5),
    );
    final reader = VoiceCastResolver(
      bookId: 'book-1', providerId: 'system',
      attributions: [valid], voices: voices,
      offsetFromAnchor: (_) => 10,
    );
    expect(reader.speakerFor(source), 'char-1');
    expect(reader.voiceFor(source)?.voiceName, 'Voice A');

    final cloud = VoiceCastResolver(
      bookId: 'book-1', providerId: 'openai-speech',
      attributions: [valid], voices: voices,
      offsetFromAnchor: (_) => 10,
    );
    expect(cloud.voiceFor(source)?.voiceName, 'marin');
  });

  test('stale offsets, changed source and missing anchors use narrator', () {
    final wrongDigest = VoiceCastResolver(
      bookId: 'book-1', providerId: 'system',
      attributions: [
        SegmentCastAssignment(
          bookId: 'book-1', start: 10, end: 23,
          sourceDigest: SegmentCastAssignment.fingerprint('different'),
          characterId: 'char-1'),
      ],
      voices: voices,
      offsetFromAnchor: (_) => null,
    );
    expect(wrongDigest.speakerFor(source), isNull);
    final invalidAnchor = VoiceCastResolver(
      bookId: 'book-1', providerId: 'system',
      attributions: [mark], voices: voices,
      offsetFromAnchor: (_) => null,
    );
    expect(invalidAnchor.speakerFor(source), isNull);
  });

  test('source-relative chapter relocation preserves valid character', () {
    final migrated = SegmentCastAssignment(
      bookId: 'book-1', start: 10, end: 23,
      sourceDigest: SegmentCastAssignment.fingerprint(source.text),
      characterId: 'char-1',
      anchor: const ReadingAnchor(
        kind: AnchorKind.epubSpine, sourceId: 'scene-2', localOffset: 5),
    );
    final resolver = VoiceCastResolver(
      bookId: 'book-1', providerId: 'system',
      attributions: [migrated], voices: voices,
      offsetFromAnchor: (_) => 50,
    );
    expect(resolver.speakerFor(const SpeechSegment(50, 63, '"Hello there"')),
        'char-1');
  });

  test('original text remains untouched by cast resolution', () {
    final snapshot = source.text;
    final cast = VoiceCastResolver(
      bookId: 'book-1', providerId: 'system',
      attributions: [mark], voices: voices,
      offsetFromAnchor: (_) => 10,
    );
    cast.speakerFor(source);
    expect(source.text, snapshot);
  });
}
