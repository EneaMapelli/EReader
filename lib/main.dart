import 'package:flutter/material.dart';

import 'app/ereader_app.dart';
import 'data/library_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LibraryStore();
  try {
    await store.initialize();
    runApp(EReaderApp(store: store));
  } catch (error) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(child: SelectableText('EReader startup error: $error')),
      ),
    ));
  }
}
