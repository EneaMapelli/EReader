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
  bool loadingNative = false;
  int stopsDuringNativeLoad = 0;
  bool failNextLoad = false;
  bool failNextStop = false;
  Completer<void>? delayedLoad;
  Completer<void>? playbackReturnGate;
  Completer<void>? nativeStopGate;

  @override
  Future<void> load(String file, {required double speed}) async {
    loadedPaths.add(file);
    speeds.add(speed);
    expect(await File(file).exists(), isTrue);
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('simulated MP3 decoder load failure');
    }
    loadingNative = true;
    try {
      if (delayedLoad != null) await delayedLoad!.future;
    } finally {
      loadingNative = false;
    }
  }
  @override
  Future<void> play() async {
    final c = Completer<void>();
    playing.add(c);
    await c.future;
    final gate = playbackReturnGate;
    if (gate != null) await gate.future;
  }
  void finish() {
    for (final c in playing) {
      if (!c.isCompleted) c.complete();
    }
  }
  @override
  Future<void> stop() async {
    stopCalls++;
    if (loadingNative) stopsDuringNativeLoad++;
    if (failNextStop) {
      failNextStop = false;
      throw StateError('simulated native Stop failure');
    }
    if (nativeStopGate != null) await nativeStopGate!.future;
    finish();
  }
  @override
  Future<void> dispose() async {
    disposed = true;
    finish();
  }
}

/// Native-style file creation and flush are not guaranteed to complete
/// within a fixed number of microtask yields, especially on Windows.
Future<void> until(bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  const deadline = Duration(seconds: 5);
  while (elapsed.elapsed < deadline) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (condition()) return;
  fail('Expected audio operation was not reached within 5 seconds');
}

void main() {
  late Directory temp;
  late List<MockMp3Decoder> decoders;
  late JustAudioMp3Output output;
  Completer<void>? nextLoadGate;
  Completer<void>? firstLoadGate;
  int failFileDeletions = 0;
  bool failStandbyFirstLoad = false;
  bool failActiveFirstLoad = false;

  setUp(() async {
    nextLoadGate = null;
    firstLoadGate = null;
    failFileDeletions = 0;
    failStandbyFirstLoad = false;
    failActiveFirstLoad = false;
    temp = await Directory.systemTemp.createTemp('ereader-mp3-warm-');
    decoders = [];
    output = JustAudioMp3Output(
      decoderFactory: () {
        final decoder = MockMp3Decoder();
        if (decoders.isEmpty) {
          decoder.delayedLoad = firstLoadGate;
          decoder.failNextLoad = failActiveFirstLoad;
        }
        if (decoders.length == 1) {
          decoder.delayedLoad = nextLoadGate;
          decoder.failNextLoad = failStandbyFirstLoad;
        }
        decoders.add(decoder);
        return decoder;
      },
      temporaryDirectory: () async => temp,
      deleteTemporaryFile: (file) async {
        if (failFileDeletions > 0) {
          failFileDeletions--;
          throw const FileSystemException('simulated transient file lock');
        }
        if (await file.exists()) await file.delete();
      },
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

  test('cold native load avoids redundant Stop after confirmed release',
      () async {
    final first = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty &&
        decoders[0].playing.isNotEmpty);
    expect(decoders[0].stopCalls, 0,
        reason: 'A brand-new idle decoder has nothing to Stop');
    decoders[0].finish();
    await first;
    expect(decoders[0].stopCalls, 1,
        reason: 'Natural completion still performs a confirmed Stop');

    final second = output.play(Uint8List.fromList([2]), speed: 1);
    await until(() => decoders[0].playing.length == 2);
    expect(decoders[0].loadedPaths, hasLength(2));
    expect(decoders[0].stopCalls, 1,
        reason: 'Already stopped and cleaned: no duplicate Stop on load');
    decoders[0].finish();
    await second;
    expect(decoders[0].stopCalls, 2);
  });

  test('newly created warm decoder loads without unnecessary native Stop',
      () async {
    final first = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty &&
        decoders[0].playing.isNotEmpty);
    final next = Uint8List.fromList([2, 3]);
    await output.prepareNext(next, speed: 1);
    expect(decoders, hasLength(2));
    expect(decoders[1].stopCalls, 0);
    decoders[0].finish();
    await first;
    final second = output.play(next, speed: 1);
    await until(() => decoders[1].playing.isNotEmpty);
    expect(decoders[1].stopCalls, 0,
        reason: 'Warm decoder was loaded, not yet playing');
    decoders[1].finish();
    await second;
    expect(decoders[1].stopCalls, 1);
  });

  test('failed native load must receive a real Stop before reuse',
      () async {
    // Install a failing first native decoder before its first file write.
    // The decoder might retain an OS handle despite throwing on load.
    // A new output receives the updated flag from the injected factory.
    await output.dispose();
    output = JustAudioMp3Output(
      decoderFactory: () {
        final decoder = MockMp3Decoder()..failNextLoad = true;
        decoders.add(decoder);
        return decoder;
      },
      temporaryDirectory: () async => temp,
    );
    await expectLater(
      output.play(Uint8List.fromList([4]), speed: 1),
      throwsStateError,
    );
    expect(decoders.single.stopCalls, 1,
        reason: 'A partially failed native file load requires immediate Stop');
    final second = output.play(Uint8List.fromList([5]), speed: 1);
    await until(() => decoders.single.playing.isNotEmpty);
    expect(decoders.single.stopCalls, 1,
        reason: 'Confirmed load-failure Stop must not be repeated on retry');
    decoders.single.finish();
    await second;
    expect(decoders.single.stopCalls, 2);
  });

  test('failed native Stop retains the cleanup obligation on retry',
      () async {
    await output.dispose();
    output = JustAudioMp3Output(
      decoderFactory: () {
        final decoder = MockMp3Decoder()
          ..failNextLoad = true
          ..failNextStop = true;
        decoders.add(decoder);
        return decoder;
      },
      temporaryDirectory: () async => temp,
    );
    await expectLater(
      output.play(Uint8List.fromList([11]), speed: 1),
      throwsStateError,
    );
    expect(decoders.single.stopCalls, 1,
        reason: 'The native cleanup attempt itself failed');
    final second = output.play(Uint8List.fromList([12]), speed: 1);
    await until(() => decoders.single.playing.isNotEmpty);
    expect(decoders.single.stopCalls, 2,
        reason: 'Never assume a failed native Stop closed its file handle');
    decoders.single.finish();
    await second;
    expect(decoders.single.stopCalls, 3);
  });

  test('a slow native Stop blocks reuse of the same decoder',
      () async {
    final first = output.play(Uint8List.fromList([6]), speed: 1);
    await until(() => decoders.isNotEmpty &&
        decoders.single.playing.isNotEmpty);
    decoders.single.nativeStopGate = Completer<void>();
    decoders.single.finish();
    await until(() => decoders.single.stopCalls == 1);
    final second = output.play(Uint8List.fromList([7]), speed: 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(decoders.single.loadedPaths, hasLength(1),
        reason: 'Never open the next file while previous Stop is pending');
    expect(decoders.single.playing, hasLength(1));
    decoders.single.nativeStopGate!.complete();
    await first;
    await until(() => decoders.single.playing.length == 2);
    expect(decoders.single.stopCalls, 1,
        reason: 'Confirmed finalizer Stop also covers the next cold load');
    decoders.single.nativeStopGate = null;
    decoders.single.finish();
    await second;
    expect(decoders.single.stopCalls, 2);
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

  test('mismatched Play does not await an obsolete stalled warm load',
      () async {
    nextLoadGate = Completer<void>();
    final first = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty &&
        decoders[0].playing.isNotEmpty);

    final stale = output.prepareNext(Uint8List.fromList([2]), speed: 1);
    await until(() => decoders.length == 2 &&
        decoders[1].loadedPaths.isNotEmpty);
    expect(nextLoadGate!.isCompleted, isFalse);

    decoders[0].finish();
    await first;

    // Seek to a different byte sequence; it must not stall until the
    // abandoned standby setFilePath completes on another decoder.
    final current = output.play(Uint8List.fromList([3]), speed: 1);
    await until(() => decoders[0].playing.length == 2);
    expect(nextLoadGate!.isCompleted, isFalse);
    expect(decoders[1].playing, isEmpty);
    expect(decoders[1].stopsDuringNativeLoad, 0);

    // A subsequent warm request on that same standby decoder is queued
    // after the old load and its Stop; it may not overlap native calls.
    final incoming = Uint8List.fromList([4]);
    final futureWarm = output.prepareNext(incoming, speed: 1);
    expect(decoders[1].loadedPaths, hasLength(1));
    nextLoadGate!.complete();
    await Future.wait([stale, futureWarm]);
    expect(decoders[1].loadedPaths, hasLength(2));
    expect(decoders[1].stopsDuringNativeLoad, 0);
    decoders[0].finish();
    await current;

    final warmed = output.play(incoming, speed: 1);
    await until(() => decoders[1].playing.isNotEmpty);
    decoders[1].finish();
    await warmed;
    expect(temp.listSync(), isEmpty);
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
    await output.prepareNext(Uint8List.fromList([3]), speed: 1.5);
    expect(decoders[1].loadedPaths.length, 2,
      reason: 'A stale prebuffer must not block future warm loads');
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

  test('stop during slow native warm-load leaves no playable stale MP3',
      () async {
    nextLoadGate = Completer<void>();
    final current = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.length == 1 &&
        decoders[0].playing.isNotEmpty);
    final preload = output.prepareNext(
        Uint8List.fromList([2]), speed: 1);
    await until(() => decoders.length == 2 &&
        decoders[1].loadedPaths.isNotEmpty);
    final priorWarmStops = decoders[1].stopCalls;
    await output.stop();
    expect(decoders[1].stopCalls, priorWarmStops,
        reason: 'Stop must not interrupt native setFilePath on the '
            'preloading decoder');
    nextLoadGate!.complete();
    await preload;
    await current;
    expect(decoders[1].playing, isEmpty);
    expect(temp.listSync(), isEmpty);
  });

  test('Stop waits for the current native load before touching decoder',
      () async {
    firstLoadGate = Completer<void>();
    final opening = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty &&
        decoders[0].loadedPaths.isNotEmpty);
    final stopping = output.stop();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(decoders[0].stopsDuringNativeLoad, 0);
    firstLoadGate!.complete();
    await stopping;
    await opening;
    expect(decoders[0].playing, isEmpty);
    expect(decoders[0].stopsDuringNativeLoad, 0);
    expect(temp.listSync(), isEmpty);
  });

  test('disposing with slow standby load waits before releasing decoder',
      () async {
    nextLoadGate = Completer<void>();
    final active = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty &&
        decoders[0].playing.isNotEmpty);
    final loading = output.prepareNext(
        Uint8List.fromList([2]), speed: 1);
    await until(() => decoders.length == 2 &&
        decoders[1].loadedPaths.isNotEmpty);
    final disposal = output.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(decoders[1].disposed, isFalse,
        reason: 'Do not free a platform decoder during setFilePath');
    expect(decoders[1].stopsDuringNativeLoad, 0);
    nextLoadGate!.complete();
    await Future.wait([disposal, loading, active]);
    expect(decoders.every((decoder) => decoder.disposed), isTrue);
    expect(decoders[1].stopsDuringNativeLoad, 0);
    expect(temp.listSync(), isEmpty);
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

  test('old clip finalizer cannot stop a new playing clip after seek',
      () async {
    final former = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.length == 1 &&
        decoders[0].playing.isNotEmpty);
    decoders[0].playbackReturnGate = Completer<void>();
    await output.stop();
    // Old output.play still awaits its artificial completion barrier.
    final fresh = output.play(Uint8List.fromList([2]), speed: 1);
    await until(() => decoders[0].playing.length == 2);
    expect(decoders[0].playing.last.isCompleted, isFalse);
    decoders[0].playbackReturnGate!.complete();
    await former;
    expect(decoders[0].playing.last.isCompleted, isFalse,
        reason: 'Stale completion may not stop the new active decoder');
    decoders[0].playbackReturnGate = null;
    decoders[0].finish();
    await fresh;
    expect(temp.listSync(), isEmpty);
  });

  test('an older slow decoder load must not erase newer warmed MP3',
      () async {
    nextLoadGate = Completer<void>();
    final first = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.length == 1 &&
        decoders[0].playing.isNotEmpty);
    final older = output.prepareNext(
      Uint8List.fromList([2]), speed: 1);
    await until(() => decoders.length == 2 &&
        decoders[1].loadedPaths.isNotEmpty);
    await output.stop();
    await first;
    // Force cleanup of the interrupted original warm load; it belongs to
    // the previous generation and must not win against future preparing.
    nextLoadGate!.complete();
    await older;
    final current = output.play(Uint8List.fromList([3]), speed: 1);
    await until(() => decoders[0].playing.length == 2);
    await output.prepareNext(Uint8List.fromList([4]), speed: 1);
    expect(decoders[1].loadedPaths, hasLength(2));
    expect(await File(decoders[1].loadedPaths.last).exists(), isTrue);
    decoders[0].finish();
    await current;
  });

  test('transient locked MP3 is retried after decoder disposal',
      () async {
    failFileDeletions = 1;
    final playing = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty &&
        decoders[0].playing.isNotEmpty);
    decoders[0].finish();
    await playing;
    expect(temp.listSync(), hasLength(1),
        reason: 'Transient deletion failures need a retained file path');

    await output.dispose();
    expect(decoders[0].disposed, isTrue);
    expect(temp.listSync(), isEmpty,
        reason: 'The orphan must be retried after native decoder disposal');
  });

  test('failed warm decoder load does not poison the next prebuffer',
      () async {
    failStandbyFirstLoad = true;
    final first = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty &&
        decoders[0].playing.isNotEmpty);
    await expectLater(
      output.prepareNext(Uint8List.fromList([2]), speed: 1),
      throwsStateError,
    );
    expect(temp.listSync(), hasLength(1),
        reason: 'Failed warm load must clean up its private file');
    await output.prepareNext(Uint8List.fromList([3]), speed: 1);
    expect(decoders[1].loadedPaths, hasLength(2));
    expect(decoders[1].playing, isEmpty);
    decoders[0].finish();
    await first;
    final warmed = output.play(
        // Reuse the same immutable byte list as the prepared clip below.
        Uint8List.fromList([4]), speed: 1);
    await until(() => decoders[0].playing.length == 2);
    decoders[0].finish();
    await warmed;
  });

  test('concurrent disposal callers await the same native cleanup',
      () async {
    nextLoadGate = Completer<void>();
    final playing = output.play(Uint8List.fromList([1]), speed: 1);
    await until(() => decoders.isNotEmpty &&
        decoders[0].playing.isNotEmpty);
    final preparing = output.prepareNext(
        Uint8List.fromList([2]), speed: 1);
    await until(() => decoders.length == 2 &&
        decoders[1].loadedPaths.isNotEmpty);

    final first = output.dispose();
    final second = output.dispose();
    expect(identical(first, second), isTrue);
    var completed = false;
    second.then((_) => completed = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(completed, isFalse);
    nextLoadGate!.complete();
    await Future.wait([first, second, preparing, playing]);
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
