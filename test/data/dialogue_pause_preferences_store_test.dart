import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LibraryStore store;
  late String first;
  late String second;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
        'ereader-dialogue-pause-prefs-');
    store = LibraryStore(homeDirectory: Directory(p.join(root.path, 'home')));
    await store.initialize();
    final a = File(p.join(root.path, 'first.txt'));
    final b = File(p.join(root.path, 'second.txt'));
    await a.writeAsString('First title. A chapter about Anna.');
    await b.writeAsString('Second title. A chapter about Marco.');
    first = (await store.importFile(a.path)).id;
    second = (await store.importFile(b.path)).id;
  });

  tearDown(() async {
    store.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('a per-book pause overrides the global default for only that book',
      () async {
    await store.saveSpeechPreferences(
        const SpeechPreferences(dialogueTurnPauseMs: 180));
    await store.saveSpeechPreferences(
        const SpeechPreferences(dialogueTurnPauseMs: 0),
        bookId: first);

    expect(store.getSpeechPreferences().dialogueTurnPauseMs, 180);
    expect(store.getSpeechPreferences(bookId: first).dialogueTurnPauseMs, 0);
    expect(store.getSpeechPreferences(bookId: second).dialogueTurnPauseMs, 180);

    await store.clearBookSpeechPreferences(first);
    expect(store.getSpeechPreferences(bookId: first).dialogueTurnPauseMs, 180,
        reason: 'Clearing the override restores the global profile');
  });

  test('dialogue pause preference survives closing and reopening SQLite',
      () async {
    await store.saveSpeechPreferences(
        const SpeechPreferences(dialogueTurnPauseMs: 300),
        bookId: first);

    store.dispose();
    store = LibraryStore(homeDirectory: Directory(p.join(root.path, 'home')));
    await store.initialize();

    expect(store.getSpeechPreferences(bookId: first).dialogueTurnPauseMs, 300);
    expect(store.getSpeechPreferences(bookId: second).dialogueTurnPauseMs, 110);
  });
}
