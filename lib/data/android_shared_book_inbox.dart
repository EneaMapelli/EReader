import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../domain/book.dart';

/// Short-lived native share grant, referenced only by a random opaque handle.
class AndroidSharedBook {
  const AndroidSharedBook({required this.id, required this.name});
  final String id;
  final String name;
}

abstract class AndroidSharedBookInbox {
  Future<List<AndroidSharedBook>> pending();
  Stream<List<int>> read(String id);
  Future<void> finish(List<String> ids);
  void listen(void Function() onAvailable);
  void dispose();
}

/// The Android receiver never sends URI paths or a whole file over a channel.
/// The regular import pipeline enforces 100 MiB and cleans temporary copies.
class MethodChannelAndroidSharedBookInbox implements AndroidSharedBookInbox {
  MethodChannelAndroidSharedBookInbox({
    MethodChannel channel =
        const MethodChannel('com.example.ereader/share_import'),
  }) : _channel = channel;

  final MethodChannel _channel;
  bool _disposed = false;

  @override
  void listen(void Function() onAvailable) {
    _channel.setMethodCallHandler((call) async {
      if (!_disposed && call.method == 'sharedBooksAvailable') onAvailable();
    });
  }

  @override
  Future<List<AndroidSharedBook>> pending() async {
    final results = await _channel.invokeMethod<List<dynamic>>('pending');
    if (results == null) return const [];
    final seen = <String>{};
    return List<AndroidSharedBook>.unmodifiable([
      for (final item in results)
        if (item is Map &&
            item['id'] is String &&
            item['name'] is String &&
            (item['id'] as String).isNotEmpty &&
            seen.add(item['id'] as String) &&
            BookFormatPath.parse(item['name'] as String) != null)
          AndroidSharedBook(
              id: item['id'] as String, name: item['name'] as String),
    ]);
  }

  @override
  Stream<List<int>> read(String id) async* {
    if (id.isEmpty) throw const FileSystemException('Invalid shared book');
    while (true) {
      if (_disposed) {
        throw const FileSystemException('Shared document import cancelled');
      }
      Uint8List? chunk;
      try {
        chunk = await _channel.invokeMethod<Uint8List>('read', {'id': id});
      } on PlatformException {
        // Never propagate provider exceptions; they can contain private URIs.
        throw const FileSystemException('Shared document is unavailable');
      }
      // Only an explicit empty native block is EOF. A null reply or disposal
      // during streaming must not silently import truncated TXT contents.
      if (_disposed || chunk == null) {
        throw const FileSystemException('Shared document import interrupted');
      }
      if (chunk.isEmpty) break;
      if (chunk.length > 64 * 1024) {
        throw const FileSystemException('Invalid shared document block');
      }
      yield chunk;
    }
  }

  @override
  Future<void> finish(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('finish', {'ids': ids});
    } on PlatformException {
      throw const FileSystemException('Cannot release shared document');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }
}
