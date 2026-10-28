import 'dart:typed_data';

import 'package:ereader/data/android_shared_book_inbox.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.ereader/share_import');

  setUp(() {
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'pending':
          return [
            {'id': 'a', 'name': 'Novel.epub'},
            {'id': 'a', 'name': 'Duplicate.epub'},
            {'id': 'b', 'name': 'Document.pdf'},
            {'id': 'c', 'name': 'photo.png'},
          ];
        case 'read':
          reads++;
          return reads == 1
              ? Uint8List.fromList([65, 66])
              : Uint8List(0);
        case 'finish':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('unique supported documents enter inbox and stream bounded chunks',
      () async {
    final inbox = MethodChannelAndroidSharedBookInbox(channel: channel);
    final selected = await inbox.pending();
    expect(selected.map((item) => item.id), ['a', 'b']);
    expect(selected.map((item) => item.name), ['Novel.epub', 'Document.pdf']);
    expect(await inbox.read('a').toList(), [[65, 66]]);
    await inbox.finish(['a', 'b']);
    inbox.dispose();
  });

  test('disposing during streaming fails instead of accepting partial TXT',
      () async {
    final inbox = MethodChannelAndroidSharedBookInbox(channel: channel);
    final seen = <List<int>>[];
    await expectLater(() async {
      await for (final bytes in inbox.read('a')) {
        seen.add(bytes);
        inbox.dispose();
      }
    }(), throwsA(isA<Exception>()));
    expect(seen, [[65, 66]]);
  });

  test('provider exceptions never expose private URI to the caller',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') {
        throw PlatformException(
          code: 'unavailable', message: 'content://secret-provider/book');
      }
      return null;
    });
    final inbox = MethodChannelAndroidSharedBookInbox(channel: channel);
    await expectLater(inbox.read('private').toList(), throwsA(
      isA<Exception>().having(
        (error) => error.toString(), 'message',
        isNot(contains('secret-provider')))));
    inbox.dispose();
  });
}
