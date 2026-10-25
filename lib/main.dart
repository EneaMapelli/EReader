import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';

import 'app/ereader_app.dart';
import 'audio/reader_media_handler.dart';
import 'data/library_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LibraryStore();
  try {
    await store.initialize();
    ReaderMediaHandler? mediaHandler;
    if (Platform.isAndroid) {
      try {
        final session = await AudioSession.instance;
        await session.configure(AudioSessionConfiguration.speech());
        mediaHandler = await AudioService.init<ReaderMediaHandler>(
          builder: () => ReaderMediaHandler(audioSession: session),
          config: const AudioServiceConfig(
            androidNotificationChannelId:
                'com.example.ereader.ereader.audio',
            androidNotificationChannelName: 'EReader narration',
            // On Android 12+, resuming a stopped foreground service from
            // a paused notification may be restricted. Keep this active
            // only while the reader page retains its media binding.
            androidStopForegroundOnPause: false,
          ),
        );
      } catch (error) {
        // Background controls must not make offline reading unavailable.
        debugPrint('Android audio service unavailable: $error');
      }
    }
    runApp(EReaderApp(store: store, mediaHandler: mediaHandler));
  } catch (error) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(child: SelectableText('EReader startup error: $error')),
      ),
    ));
  }
}
