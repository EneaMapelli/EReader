import 'dart:io';

import 'package:ereader/data/library_store.dart';
import 'package:ereader/domain/speech_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('installed free system voice survives a book-library reopen',
      () async {
    final root = await Directory.systemTemp.createTemp(
        'ereader-system-voice-preference-');
    var store = LibraryStore(homeDirectory: root);
    try {
      await store.initialize();
      final sample = File(p.join(root.path, 'book.txt'));
      await sample.writeAsString('A short book to test a stored voice.');
      final bookId = (await store.importFile(sample.path)).id;

      final original = store.getSpeechPreferences(bookId: bookId);
      final chosen = original.copyWith(
        providerId: 'system',
        voiceName: 'Italian voice A',
        voiceLocale: 'it-IT',
        language: 'it-IT',
      );
      await store.saveSpeechPreferences(chosen, bookId: bookId);
      expect(store.getSpeechPreferences(bookId: bookId).voiceName,
          'Italian voice A');

      store.dispose();
      store = LibraryStore(homeDirectory: root);
      await store.initialize();
      final restored = store.getSpeechPreferences(bookId: bookId);
      expect(restored.providerId, 'system');
      expect(restored.voiceName, 'Italian voice A');
      expect(restored.voiceLocale, 'it-IT');

      // Native-punctuation mode is a second free engine with the same
      // installed OS voices, not a separate paid subscription.
      final native = restored.copyWith(
        providerId: 'system-native',
        voiceName: restored.voiceName,
        voiceLocale: restored.voiceLocale,
      );
      await store.saveSpeechPreferences(native, bookId: bookId);
      expect(store.getSpeechPreferences(bookId: bookId).voiceName,
          'Italian voice A');
      expect(store.getSpeechPreferences(bookId: bookId).providerId,
          'system-native');

      // A real user can select Automatic in the free system voice picker.
      // It removes the explicit choice and remains that way across reopen;
      // merely inspecting the OS catalog must not re-pin a different voice.
      final automatic = native.copyWith(clearVoice: true);
      await store.saveSpeechPreferences(automatic, bookId: bookId);
      expect(store.getSpeechPreferences(bookId: bookId).voiceName, isNull);
      expect(store.getSpeechPreferences(bookId: bookId).voiceLocale, isNull);
      store.dispose();
      store = LibraryStore(homeDirectory: root);
      await store.initialize();
      final reopenedAutomatic = store.getSpeechPreferences(bookId: bookId);
      expect(reopenedAutomatic.providerId, 'system-native');
      expect(reopenedAutomatic.voiceName, isNull);
      expect(reopenedAutomatic.voiceLocale, isNull);

      // Leaving system TTS removes the stale OS voice identity without
      // touching the book's stored source/reading position.
      await store.saveSpeechPreferences(native.copyWith(
        providerId: 'openai-speech', clearVoice: true,
      ), bookId: bookId);
      final cloud = store.getSpeechPreferences(bookId: bookId);
      expect(cloud.voiceName, isNull);
      expect(cloud.voiceLocale, isNull);
    } finally {
      store.dispose();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
