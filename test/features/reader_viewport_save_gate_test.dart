import 'package:ereader/features/reader/reader_viewport_save_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  testWidgets('manual drag resumes scrolling after a presentation relayout',
      (tester) async {
    final gate = ReaderViewportSaveGate();
    var userScrolls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if ((notification is ScrollStartNotification &&
                    notification.dragDetails != null) ||
                (notification is ScrollUpdateNotification &&
                    notification.dragDetails != null) ||
                (notification is UserScrollNotification &&
                    notification.direction != ScrollDirection.idle)) {
              gate.resumeFromUserScroll();
              userScrolls++;
            }
            return false;
          },
          child: ListView.builder(
            key: const ValueKey('reader-viewport-list'),
            itemCount: 80,
            itemBuilder: (_, i) => SizedBox(
              height: 70, child: Text('Paragraph $i'),
            ),
          ),
        ),
      ),
    ));
    gate.suspendForLayoutChange();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if ((notification is ScrollStartNotification &&
                    notification.dragDetails != null) ||
                (notification is ScrollUpdateNotification &&
                    notification.dragDetails != null) ||
                (notification is UserScrollNotification &&
                    notification.direction != ScrollDirection.idle)) {
              gate.resumeFromUserScroll();
              userScrolls++;
            }
            return false;
          },
          child: SizedBox(
            height: 400,
            child: ListView.builder(
              key: const ValueKey('reader-viewport-list'),
              itemCount: 80,
              itemBuilder: (_, i) => SizedBox(
                height: 70, child: Text('Paragraph $i'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(gate.allowsViewportSave, isFalse);
    expect(userScrolls, 0,
        reason: 'Resizing a list without touch input must not save a bookmark');
    await tester.drag(
        find.byKey(const ValueKey('reader-viewport-list')),
        const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(gate.allowsViewportSave, isTrue);
    expect(userScrolls, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
