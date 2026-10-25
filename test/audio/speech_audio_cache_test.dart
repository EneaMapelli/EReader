import 'dart:io';
import 'dart:typed_data';

import 'package:ereader/audio/speech_audio_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late PrivateMp3SpeechCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-mp3-cache-');
    cache = PrivateMp3SpeechCache(root: root);
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('reuses exact data per book and key without leaking to other books',
      () async {
    final firstBook = 'a' * 64;
    final secondBook = 'b' * 64;
    final key = 'c' * 64;
    final audio = Uint8List.fromList([1, 2, 3, 4]);
    expect(await cache.read(firstBook, key), isNull);
    await cache.write(firstBook, key, audio);
    expect(await cache.read(firstBook, key), audio);
    expect(await cache.read(secondBook, key), isNull);
    await cache.clearBook(firstBook);
    expect(await cache.read(firstBook, key), isNull);
  });

  test('prevents cache directory traversal via book id or clip id',
      () async {
    await expectLater(
      cache.read('../../outside', 'a' * 64),
      throwsFormatException,
    );
    await expectLater(
      cache.write('a' * 64, '../clip.mp3',
          Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  test('clear all deletes generated local speech files', () async {
    await cache.write('a' * 64, 'b' * 64,
        Uint8List.fromList([4, 5, 6]));
    await cache.clearAll();
    expect(await cache.read('a' * 64, 'b' * 64), isNull);
  });
}
