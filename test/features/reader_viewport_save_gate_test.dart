import 'package:ereader/features/reader/reader_viewport_save_gate.dart';
import 'package:flutter/material.dart';
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
