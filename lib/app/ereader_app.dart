import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../features/library/library_screen.dart';

class EReaderApp extends StatelessWidget {
  const EReaderApp({super.key, required this.store});
  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EReader',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF496478)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7BAEC6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: LibraryScreen(store: store),
    );
  }
}
