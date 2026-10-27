import 'dart:async';
import 'dart:io';

import 'package:ereader/audio/offline_wav_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-wav-cleaner-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('first deletion failure is remembered and later retry clears WAV',
      () async {
    final folder = await root.createTemp('ereader-local-tts-');
    await File(p.join(folder.path, 'speech.wav')).writeAsBytes([1, 2, 3]);
    var locked = true;
    final cleaner = OfflineWavCleanup(deleteDirectory: (directory) async {
      if (locked) throw const FileSystemException('Native handle locked');
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    await cleaner.release(folder);
    expect(cleaner.pendingCount, 1);
    expect(await folder.exists(), isTrue);
    locked = false;
    await cleaner.retryPending();
    expect(cleaner.pendingCount, 0);
    expect(await folder.exists(), isFalse);
  });

  test('sweep deletes only explicitly registered WAV directory', () async {
    final owned = await root.createTemp('ereader-local-tts-');
    final unrelated = await root.createTemp('unrelated-user-documents-');
    await File(p.join(unrelated.path, 'keep.txt')).writeAsString('preserve');
    var locked = true;
    final cleaner = OfflineWavCleanup(deleteDirectory: (directory) async {
      if (locked) throw const FileSystemException('Native lock');
      await directory.delete(recursive: true);
    });
    await cleaner.release(owned);
    locked = false;
    await cleaner.retryPending();
    expect(await owned.exists(), isFalse);
    expect(await File(p.join(unrelated.path, 'keep.txt')).readAsString(),
        'preserve');
  });

  test('capacity guard refuses generation after bounded pending failures',
      () async {
    final cleaner = OfflineWavCleanup(
      maxPending: 2,
      deleteDirectory: (_) async {
        throw const FileSystemException('Locked');
      },
    );
    await cleaner.release(await root.createTemp('ereader-local-tts-'));
    await cleaner.ensureCapacity();
    await cleaner.release(await root.createTemp('ereader-local-tts-'));
    expect(cleaner.pendingCount, 2);
    await expectLater(cleaner.ensureCapacity(), throwsStateError);
    expect(cleaner.pendingCount, 2);
  });

  test('failed entries rotate so a permanent lock cannot starve cleanup',
      () async {
    final first = await root.createTemp('ereader-local-tts-');
    final second = await root.createTemp('ereader-local-tts-');
    final third = await root.createTemp('ereader-local-tts-');
    var locked = true;
    // Only explicitly registered paths are retried; the first remains
    // locked, while other entries can recover during later retry passes.
    var holdOthers = true;
    final rotating = OfflineWavCleanup(
      retryBatchSize: 1,
      deleteDirectory: (dir) async {
        if (dir.path == first.path && locked ||
            holdOthers && (dir.path == second.path || dir.path == third.path)) {
          throw const FileSystemException('locked');
        }
        if (await dir.exists()) await dir.delete(recursive: true);
      },
    );
    await rotating.release(first);
    await rotating.release(second);
    await rotating.release(third);
    holdOthers = false;
    await rotating.retryPending();
    expect(await second.exists(), isTrue);
    await rotating.retryPending();
    expect(await second.exists(), isFalse);
    await rotating.retryPending();
    expect(await third.exists(), isFalse);
    expect(rotating.pendingCount, 1);
    locked = false;
    await rotating.retryPending();
    expect(rotating.pendingCount, 0);
    expect(await first.exists(), isFalse);
  });

  test('concurrent retry calls share one sweep, never double-delete', () async {
    final folder = await root.createTemp('ereader-local-tts-');
    final gate = Completer<void>();
    var attempts = 0;
    var blocked = true;
    final cleaner = OfflineWavCleanup(
      deleteDirectory: (directory) async {
        attempts++;
        if (blocked) throw const FileSystemException('locked');
        await gate.future;
        if (await directory.exists()) await directory.delete(recursive: true);
      },
    );
    await cleaner.release(folder);
    blocked = false;
    final first = cleaner.retryPending();
    final second = cleaner.retryPending();
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 2, reason: 'One initial try and one shared retry');
    gate.complete();
    await Future.wait([first, second]);
    expect(attempts, 2);
    expect(cleaner.pendingCount, 0);
  });

  test('ordinary release succeeds immediately and double release is safe',
      () async {
    final folder = await root.createTemp('ereader-local-tts-');
    final cleaner = OfflineWavCleanup();
    await cleaner.release(folder);
    await cleaner.release(folder);
    expect(cleaner.pendingCount, 0);
    expect(await folder.exists(), isFalse);
  });
}
