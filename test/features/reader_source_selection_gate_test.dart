import 'dart:async';

import 'package:ereader/features/reader/reader_source_selection_gate.dart';
import 'package:ereader/features/reader/reader_chapter_visit_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deferred failures belong only to their original active intent',
      () async {
    final gate = ReaderSourceSelectionGate();
    final oldNativeFailure = Completer<void>();
    final errors = <String>[];
    final oldSession = Object();
    var currentSession = oldSession;

    Future<void> navigate() async {
      final intent = gate.reserve();
      try {
        await oldNativeFailure.future;
      } catch (_) {
        if (identical(currentSession, oldSession) &&
            gate.isCurrent(intent)) {
          errors.add('old failure');
        }
      }
    }

    final obsolete = navigate();
    gate.reserve(); // newer explicit EPUB source selection
    oldNativeFailure.completeError(StateError('obsolete voice engine'));
    await obsolete;
    expect(errors, isEmpty);

    final latest = gate.reserve();
    expect(gate.isCurrent(latest), isTrue);
    expect(gate.revision, latest);
    gate.invalidate(); // reload replaces the current player
    currentSession = Object();
    expect(gate.isCurrent(latest), isFalse);
    expect(identical(currentSession, oldSession), isFalse);
  });

  test('a current native failure stays reportable until another intent',
      () async {
    final gate = ReaderSourceSelectionGate();
    final intent = gate.reserve();
    final failure = Completer<void>();
    var reported = false;

    Future<void> execute() async {
      try {
        await failure.future;
      } catch (_) {
        reported = gate.isCurrent(intent);
      }
    }

    final pending = execute();
    failure.completeError(StateError('active voice failure'));
    await pending;
    expect(reported, isTrue,
        reason: 'Only obsolete errors are suppressed, not active failures');
  });

  test('superseded chapter Back cannot consume history after a new branch',
      () async {
    final gate = ReaderSourceSelectionGate();
    final history = ReaderChapterVisitHistory();
    for (final pair in [(100, 250), (250, 400)]) {
      expect(history.recordCommittedJump(
        fromOffset: pair.$1, toOffset: pair.$2, sourceLength: 1000,
        sectionTitle: 'Chapter', sectionNumber: 1, sectionCount: 5,
      ), isTrue);
    }
    var savedOffset = 400;
    var visualOffset = 400;
    final backTarget = history.latest!;
    final historyRevision = history.revision;
    final latePause = Completer<void>();

    Future<void> oldBack() async {
      final request = gate.reserve(); // before a potentially slow Pause
      await latePause.future;
      if (!gate.isCurrent(request)) return;
      savedOffset = backTarget.sourceOffset; // not reached for stale Back
      await Future<void>.value();
      if (!gate.isCurrent(request)) return;
      visualOffset = backTarget.sourceOffset;
      history.consumeThrough(backTarget,
          expectedRevision: historyRevision,
          departedFrom: const ReaderChapterVisit(
            sourceOffset: 400, sectionTitle: 'Current',
            sectionNumber: 3, sectionCount: 5,
          ));
    }

    final obsoleteBack = oldBack();
    final newRequest = gate.reserve(); // user chooses a new chapter
    savedOffset = 750; // synchronous durable update
    await Future<void>.value();
    expect(gate.isCurrent(newRequest), isTrue);
    visualOffset = 750;
    expect(history.recordCommittedJump(
      fromOffset: 400, toOffset: 750, sourceLength: 1000,
      sectionTitle: 'Current', sectionNumber: 3, sectionCount: 5,
    ), isTrue);
    latePause.complete();
    await obsoleteBack;

    expect(savedOffset, 750);
    expect(visualOffset, 750);
    expect(history.recent.map((v) => v.sourceOffset), [400, 250, 100]);
    expect(history.canGoForward, isFalse);
  });


  test('older Pause completing after latest commit cannot write or '
      'append a chapter visit', () async {
    final gate = ReaderSourceSelectionGate();
    final history = ReaderChapterVisitHistory();
    final oldPause = Completer<void>();
    final newPause = Completer<void>();
    var checkpoint = 100;
    var visual = 100;
    var saves = 0;

    Future<void> choose(int destination, Completer<void> pause) async {
      final token = gate.reserve();
      await pause.future;
      if (!gate.isCurrent(token)) return;
      final origin = checkpoint;
      checkpoint = destination; // Synchronous SQLite write contract.
      saves++;
      if (!gate.isCurrent(token)) return;
      visual = destination;
      history.recordCommittedJump(
        fromOffset: origin, toOffset: destination,
        sourceLength: 1000, sectionTitle: 'Chapter',
        sectionNumber: 1, sectionCount: 3,
      );
    }

    final obsolete = choose(250, oldPause);
    final lastIntent = choose(750, newPause);
    newPause.complete();
    await lastIntent;
    oldPause.complete();
    await obsolete;

    expect(checkpoint, 750);
    expect(visual, checkpoint);
    expect(saves, 1);
    expect(history.length, 1);
    expect(history.latest!.sourceOffset, 100);
    expect(history.recent.map((e) => e.sourceOffset), [100]);
  });

  test('late SQLite Future of obsolete request cannot repaint or '
      'mutate chapter history', () async {
    final gate = ReaderSourceSelectionGate();
    final history = ReaderChapterVisitHistory();
    final oldSaveContinuation = Completer<void>();
    var durable = 100;
    var visual = 100;

    Future<void> choose(int destination, Future<void> saveYield) async {
      final token = gate.reserve();
      if (!gate.isCurrent(token)) return;
      final origin = durable;
      durable = destination;
      // The real store updates SQLite before returning its Future;
      // a superseding intent may arrive before this continuation resumes.
      await saveYield;
      if (!gate.isCurrent(token)) return;
      visual = destination;
      history.recordCommittedJump(
        fromOffset: origin, toOffset: destination,
        sourceLength: 1000, sectionTitle: 'Chapter',
        sectionNumber: 1, sectionCount: 3,
      );
    }

    final old = choose(300, oldSaveContinuation.future);
    await choose(800, Future<void>.value());
    oldSaveContinuation.complete();
    await old;

    expect(durable, 800);
    expect(visual, 800);
    expect(history.length, 1);
    expect(history.latest!.sourceOffset, 300,
        reason: 'The latest committed intent owns its actual departure');
  });

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
