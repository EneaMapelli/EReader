import 'dart:async';

import 'package:ereader/features/reader/reader_viewport_save_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejected deferred viewport write is caught and reported once',
      () async {
    final errors = <Object>[];
    var saved = false;
    await persistReaderViewportCheckpoint(
      save: () async => throw StateError('sqlite read-only'),
      isCurrent: () => true,
      onFailure: errors.add,
      onSaved: () => saved = true,
    );
    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());
    expect(saved, isFalse);
  });

  test('superseded viewport request never starts a database write', () async {
    var activeRevision = 3;
    var writes = 0;
    final captured = activeRevision;
    activeRevision++;
    await persistReaderViewportCheckpoint(
      save: () async { writes++; },
      isCurrent: () => activeRevision == captured,
      onFailure: (_) => fail('Stale request reported an error'),
    );
    expect(writes, 0);
  });

  test('a late failed write is silent after another source selection',
      () async {
    final pending = Completer<void>();
    var revision = 4;
    final savedRevision = revision;
    final errors = <Object>[];
    final future = persistReaderViewportCheckpoint(
      save: () => pending.future,
      isCurrent: () => revision == savedRevision,
      onFailure: errors.add,
    );
    revision++; // Explicit EPUB seek supersedes the queued viewport save.
    pending.completeError(StateError('obsolete SQLite failure'));
    await future;
    expect(errors, isEmpty);
  });

  test('a current successful write clears earlier error notification',
      () async {
    var warned = false;
    final error = StateError('temporary write failure');
    await persistReaderViewportCheckpoint(
      save: () async => throw error,
      isCurrent: () => true,
      onFailure: (_) => warned = true,
    );
    expect(warned, isTrue);
    await persistReaderViewportCheckpoint(
      save: () async {},
      isCurrent: () => true,
      onFailure: (_) => fail('Successful write failed'),
      onSaved: () => warned = false,
    );
    expect(warned, isFalse);
  });

  test('viewport relayout does not authorize a bookmark write', () {
    final gate = ReaderViewportSaveGate();
    expect(gate.allowsViewportSave, isTrue);
    gate.suspendForLayoutChange();
    expect(gate.allowsViewportSave, isFalse);
    // Repeated appearance/focus toggles must not accidentally unsuspend.
    gate.suspendForLayoutChange();
    expect(gate.allowsViewportSave, isFalse);
    gate.resumeFromUserScroll();
    expect(gate.allowsViewportSave, isTrue);
    gate.suspendForLayoutChange();
    expect(gate.allowsViewportSave, isFalse);
  });

  testWidgets('programmatic jumps and animations are not manual scrolling',
      (tester) async {
    final gate = ReaderViewportSaveGate();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var drags = 0;
    var directionalNotifications = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is UserScrollNotification) {
              directionalNotifications++;
            }
            if ((notification is ScrollStartNotification &&
                    notification.dragDetails != null) ||
                (notification is ScrollUpdateNotification &&
                    notification.dragDetails != null)) {
              gate.resumeFromUserScroll();
              drags++;
            }
            return false;
          },
          child: ListView.builder(
            key: const ValueKey('reader-viewport-list'),
            controller: controller,
            itemCount: 80,
            itemBuilder: (_, i) => SizedBox(
              height: 70, child: Text('Paragraph $i'),
            ),
          ),
        ),
      ),
    ));
    gate.suspendForLayoutChange();
    controller.jumpTo(490);
    await tester.pumpAndSettle();
    expect(gate.allowsViewportSave, isFalse,
        reason: 'jumpTo can emit notifications but is not user intent');
    final moving = controller.animateTo(700,
        duration: const Duration(milliseconds: 180),
        curve: Curves.linear);
    await tester.pumpAndSettle();
    await moving;
    expect(gate.allowsViewportSave, isFalse,
        reason: 'Auto-follow animations must not overwrite saved bookmarks');
    expect(drags, 0);
    // A real finger drag restores the user's ability to save progress.
    await tester.drag(find.byKey(const ValueKey('reader-viewport-list')),
        const Offset(0, -310));
    await tester.pumpAndSettle();
    expect(gate.allowsViewportSave, isTrue);
    expect(drags, greaterThan(0));
    expect(tester.takeException(), isNull);
    expect(directionalNotifications, greaterThanOrEqualTo(0));
  });
}
