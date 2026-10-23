import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ereader/audio/mp3_playback.dart';
import 'package:flutter_test/flutter_test.dart';

class MockMp3Decoder implements Mp3Decoder {
  final loadedPaths = <String>[];
  final speeds = <double>[];
  final playing = <Completer<void>>[];
  int stopCalls = 0;
  bool disposed = false;
  Completer<void>? delayedLoad;

  @override
  Future<void> load(String file, {required double speed}) async {
    loadedPaths.add(file);
    speeds.add(speed);
    expect(await File(file).exists(), isTrue);
    if (delayedLoad != null) await delayedLoad!.future;
  }
  @override
  Future<void> play() {
    final c = Completer<void>();
    playing.add(c);
    return c.future;
  }
  void finish() {
    for (final c in playing) {
      if (!c.isCompleted) c.complete();
    }
  }
  @override
  Future<void> stop() async {
    stopCalls++;
    finish();
  }
  @override
  Future<void> dispose() async {
    disposed = true;
    finish();
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 80; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected audio operation did not occur');
}

void main() {
  late Directory temp;
  late List<MockMp3Decoder> decoders;
  late JustAudioMp3Output output;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ereader-mp3-warm-');
    decoders = [];
    output = JustAudioMp3Output(
      decoderFactory: () {
        final decoder = MockMp3Decoder();
        decoders.add(decoder);
        return decoder;
      },
      temporaryDirectory: () async => temp,
    );
  });

  tearDown(() async {
    await output.dispose();
    expect(temp.listSync(), isEmpty);
    await temp.delete(recursive: true);
  });

  test('staged next clip loads on a second player and plays only once',
      () async {
    final first = Uint8List.fromList([1, 2, 3]);
    final next = Uint8List.fromList([4, 5, 6]);
    final current = output.play(first, speed: 1);
    await until(() => decoders.length == 1 && decoders[0].playing.isNotEmpty);
    await output.prepareNext(next, speed: 1.25);
    expect(decoders, hasLength(2));
    expect(decoders[1].loadedPaths, hasLength(1));
    expect(decoders[1].speeds, [1.25]);
    expect(decoders[1].playing, isEmpty,
      reason: 'Prebuffer must not overlap currently playing audio');
    decoders[0].finish();
    await current;
    final later = output.play(next, speed: 1.25);
    await until(() => decoders[1].playing.isNotEmpty);
    expect(decoders[1].loadedPaths, hasLength(1),
      reason: 'Prepared file must not be reloaded');
    decoders[1].finish();
    await later;
    expect(temp.listSync(), isEmpty);
  });

  test('never opens native player for speculative audio before Play',
      () async {
    await output.prepareNext(Uint8List.fromList([8]), speed: 1);
    expect(decoders, isEmpty);
    expect(temp.listSync(), isEmpty);
  });

  test('only one future clip may be staged at a time', () async {
    final active = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty && decoders[0].playing.isNotEmpty);
    await output.prepareNext(Uint8List.fromList([2]), speed: 1);
    await output.prepareNext(Uint8List.fromList([3]), speed: 1);
    expect(decoders.length, 2);
    expect(decoders[1].loadedPaths.length, 1);
    decoders[0].finish();
    await active;
  });

  test('different rate must not use previously decoded speed settings',
      () async {
    final incoming = Uint8List.fromList([2]);
    final active = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty && decoders[0].playing.isNotEmpty);
    await output.prepareNext(incoming, speed: 1);
    decoders[0].finish();
    await active;
    final playback = output.play(incoming, speed: 1.5);
    await until(() => decoders[0].playing.length == 2);
    expect(decoders[0].speeds.last, 1.5);
    expect(decoders[1].playing, isEmpty);
    decoders[0].finish();
    await playback;
  });

  test('stop invalidates staged audio and removes private files', () async {
    final active = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty && decoders[0].playing.isNotEmpty);
    await output.prepareNext(Uint8List.fromList([2]), speed: 1);
    await output.stop();
    await active;
    expect(temp.listSync(), isEmpty);
    expect(decoders.every((d) => d.stopCalls > 0), isTrue);
  });

  test('dispose releases both native decoders and all temp MP3 files',
      () async {
    final active = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty && decoders[0].playing.isNotEmpty);
    await output.prepareNext(Uint8List.fromList([2]), speed: 1);
    await output.dispose();
    await active;
    expect(decoders.where((d) => d.disposed), hasLength(2));
    expect(temp.listSync(), isEmpty);
  });

  test('invalid clip size or rate fails before creating temporary files',
      () async {
    await expectLater(output.prepareNext(Uint8List(0), speed: 1),
        throwsFormatException);
    await expectLater(output.play(Uint8List.fromList([1]), speed: 0.1),
        throwsFormatException);
    expect(decoders, isEmpty);
  });
}
