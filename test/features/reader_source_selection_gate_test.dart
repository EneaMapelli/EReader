import 'dart:async';

import 'package:ereader/features/reader/reader_source_selection_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('latest intent wins even when an older Pause finishes last', () async {
    final gate = ReaderSourceSelectionGate();
    final slowStop = Completer<void>();
    final fastStop = Completer<void>();
    final selections = <String>[];

    Future<void> navigate(String name, Completer<void> stop) async {
      final revision = gate.reserve();
      await stop.future;
      if (!gate.isCurrent(revision)) return;
      selections.add(name);
    }

    final old = navigate('old search', slowStop);
    final latest = navigate('new bookmark', fastStop);
    fastStop.complete();
    await latest;
    slowStop.complete();
    await old;
    expect(selections, ['new bookmark']);
  });

  test('a failed latest navigation does not resurrect an older one',
      () async {
    final gate = ReaderSourceSelectionGate();
    final old = gate.reserve();
    final newer = gate.reserve();
    expect(gate.isCurrent(old), isFalse);
    expect(gate.isCurrent(newer), isTrue);
    // The latest operation failed or was superseded after reserving;
    // old operations must never be made current again.
    gate.invalidate();
    expect(gate.isCurrent(old), isFalse);
    expect(gate.isCurrent(newer), isFalse);
  });

  test('newer selection suppresses Play after a stale async seek', () async {
    final gate = ReaderSourceSelectionGate();
    final seekCompleted = Completer<void>();
    var didPlay = false;

    Future<void> startPlay() async {
      final playIntent = gate.reserve();
      await seekCompleted.future;
      if (!gate.isCurrent(playIntent)) return;
      didPlay = true;
    }

    final playback = startPlay();
    final newChapter = gate.reserve();
    seekCompleted.complete();
    await playback;
    expect(didPlay, isFalse);
    expect(gate.isCurrent(newChapter), isTrue);
  });

  test('a cancelled in-flight source intent remains invalid after reload',
      () async {
    final gate = ReaderSourceSelectionGate();
    final pause = Completer<void>();
    var wroteCheckpoint = false;

    Future<void> jump() async {
      final intent = gate.reserve();
      await pause.future;
      if (gate.isCurrent(intent)) wroteCheckpoint = true;
    }

    final pending = jump();
    gate.invalidate(); // reader reloaded / replaced its audio player
    pause.complete();
    await pending;
    expect(wroteCheckpoint, isFalse);
  });

  test('a synchronous select and a remote selection share the same order', () {
    final gate = ReaderSourceSelectionGate();
    final tap = gate.reserve();
    expect(gate.isCurrent(tap), isTrue);
    gate.invalidate(); // remote chapter seek won
    expect(gate.isCurrent(tap), isFalse);
    final next = gate.reserve();
    expect(gate.isCurrent(next), isTrue);
    expect(gate.isCurrent(tap), isFalse);
  });
}
