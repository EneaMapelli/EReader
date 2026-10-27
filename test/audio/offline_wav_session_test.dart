import 'dart:io';

import 'package:ereader/audio/offline_wav_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ereader-recovery-test-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<Directory> addWav(OfflineWavSession session, {
    String prefix = 'ereader-local-tts-',
  }) async {
    final folder = await session.directory.createTemp(prefix);
    await File(p.join(folder.path, 'speech.wav'))
        .writeAsBytes([82, 73, 70, 70]);
    return folder;
  }

  test('normal session exit with no WAV removes marker and lease', () async {
    final session = await OfflineWavSession.create(root);
    expect(await File(p.join(session.directory.path,
        OfflineWavSession.markerName)).exists(), isTrue);
    await session.close();
    expect(await session.directory.exists(), isFalse);
    expect(await OfflineWavSession.recoverAbandoned(root), 0);
    expect(await root.list().toList(), isEmpty);
  });

  test('running reader registry and OS lease prevent reclaiming live WAV',
      () async {
    final live = await OfflineWavSession.create(root);
    final clip = await addWav(live);
    expect(await OfflineWavSession.recoverAbandoned(root), 0);
    expect(await File(p.join(clip.path, 'speech.wav')).exists(), isTrue);
    await live.close();
    expect(await live.directory.exists(), isTrue,
        reason: 'A leftover WAV keeps the old marked session recoverable');
    expect(await OfflineWavSession.recoverAbandoned(root), 1);
    expect(await live.directory.exists(), isFalse);
    expect(await root.list().toList(), isEmpty);
  });

  test('recovers abandoned lookahead and audible WAV from same session',
      () async {
    final crashed = await OfflineWavSession.create(root);
    await addWav(crashed, prefix: 'ereader-local-tts-');
    await addWav(crashed, prefix: 'ereader-local-lookahead-');
    // Simulate the OS releasing the crashed reader's lease, while WAV
    // folders remain. No external process or real native audio needed.
    await crashed.close();
    expect(await OfflineWavSession.recoverAbandoned(root), 1);
    expect(await root.list().toList(), isEmpty);
  });

  test('metadata-only directory after interrupted close is recoverable',
      () async {
    final partial = await root.createTemp(OfflineWavSession.sessionPrefix);
    await File(p.join(partial.path, OfflineWavSession.leaseName))
        .writeAsBytes([]);
    expect(await OfflineWavSession.recoverAbandoned(root), 1);
    expect(await partial.exists(), isFalse);
  });

  test('unmarked lease plus WAV is NOT proof of ownership', () async {
    final suspicious =
        await root.createTemp(OfflineWavSession.sessionPrefix);
    await File(p.join(suspicious.path, OfflineWavSession.leaseName))
        .writeAsBytes([]);
    final clip = await suspicious.createTemp('ereader-local-tts-');
    final wav = File(p.join(clip.path, 'speech.wav'));
    await wav.writeAsBytes([7, 8, 9]);
    expect(await OfflineWavSession.recoverAbandoned(root), 0);
    expect(await wav.readAsBytes(), [7, 8, 9]);
  });

  test('lease-only metadata with an unexpected file remains untouched',
      () async {
    final suspicious =
        await root.createTemp(OfflineWavSession.sessionPrefix);
    await File(p.join(suspicious.path, OfflineWavSession.leaseName))
        .writeAsBytes([]);
    final stranger = File(p.join(suspicious.path, 'notes.txt'));
    await stranger.writeAsString('unrelated');
    expect(await OfflineWavSession.recoverAbandoned(root), 0);
    expect(await stranger.readAsString(), 'unrelated');
  });

  test('concurrent recovery sweeps reclaim one abandoned session once',
      () async {
    final old = await OfflineWavSession.create(root);
    await addWav(old);
    await old.close();
    final results = await Future.wait([
      OfflineWavSession.recoverAbandoned(root),
      OfflineWavSession.recoverAbandoned(root),
    ]);
    expect(results.reduce((a, b) => a + b), 1);
    expect(await root.list().toList(), isEmpty);
  });

  test('repeated calls to close wait for the same session cleanup', () async {
    final session = await OfflineWavSession.create(root);
    final first = session.close();
    final second = session.close();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    expect(await session.directory.exists(), isFalse);
  });

  test('legacy unmarked temp WAV is never touched', () async {
    final legacy = await root.createTemp('ereader-local-tts-');
    final wav = File(p.join(legacy.path, 'speech.wav'));
    await wav.writeAsBytes([1, 2, 3]);
    expect(await OfflineWavSession.recoverAbandoned(root), 0);
    expect(await wav.readAsBytes(), [1, 2, 3]);
  });

  test('marker content mismatch is never an authority to delete', () async {
    final fake = await root.createTemp(OfflineWavSession.sessionPrefix);
    await File(p.join(fake.path, OfflineWavSession.markerName))
        .writeAsString('OTHER APPLICATION');
    await File(p.join(fake.path, OfflineWavSession.leaseName))
        .writeAsString('');
    final payload = File(p.join(fake.path, 'notes.txt'));
    await payload.writeAsString('keep me');
    expect(await OfflineWavSession.recoverAbandoned(root), 0);
    expect(await payload.readAsString(), 'keep me');
  });

  test('unknown contents abort recovery rather than recursive deletion',
      () async {
    final old = await OfflineWavSession.create(root);
    final folder = await addWav(old);
    final privateNotes = File(p.join(folder.path, 'do-not-delete.txt'));
    await privateNotes.writeAsString('unrelated file');
    await old.close();
    expect(await OfflineWavSession.recoverAbandoned(root), 0);
    expect(await privateNotes.readAsString(), 'unrelated file');
    expect(await File(p.join(folder.path, 'speech.wav')).exists(), isTrue);
  });

  test('non-WAV nested directories are rejected', () async {
    final old = await OfflineWavSession.create(root);
    final folder = await addWav(old);
    await Directory(p.join(folder.path, 'nested')).create();
    await old.close();
    expect(await OfflineWavSession.recoverAbandoned(root), 0);
    expect(await Directory(p.join(folder.path, 'nested')).exists(), isTrue);
  });

  test('root candidate scan has a strict upper bound', () async {
    final abandoned = <OfflineWavSession>[];
    for (var i = 0; i < OfflineWavSession.maxScannedSessions + 2; i++) {
      final s = await OfflineWavSession.create(root);
      await addWav(s);
      await s.close();
      abandoned.add(s);
    }
    final removed = await OfflineWavSession.recoverAbandoned(root);
    expect(removed, lessThanOrEqualTo(OfflineWavSession.maxScannedSessions));
    expect(removed, greaterThan(0));
    final left = await root.list().toList();
    expect(left.length,
        greaterThanOrEqualTo(abandoned.length -
            OfflineWavSession.maxScannedSessions));
  });
}
