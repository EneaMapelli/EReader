import 'package:ereader/features/library/library_book_row_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small host using the same nested menu and keyboard focus integration as
/// the real library, without filesystem, TTS, network, or database operations.
Widget _row({
  required String id,
  bool enabled = true,
  VoidCallback? onOpen,
  ValueChanged<String>? onMenu,
}) => LibraryBookRowFocus(
  key: ValueKey('library-book-focus-' + id),
  bookTitle: id,
  enabled: enabled,
  builder: (rowFocus, menuKey, openMenu) => ListTile(
    key: ValueKey('row-' + id),
    focusNode: rowFocus,
    title: Text(id),
    onTap: onOpen,
    onLongPress: enabled ? openMenu : null,
    trailing: PopupMenuButton<String>(
      key: menuKey,
      enabled: enabled,
      tooltip: 'Book actions',
      onSelected: onMenu,
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit metadata')),
        PopupMenuItem(value: 'remove', child: Text('Remove from library')),
      ],
    ),
  ),
);

void main() {
  testWidgets('Shift+F10 opens only the focused book menu', (tester) async {
    var openedBook = 0;
    String? action;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _row(
        id: 'Atlas',
        onOpen: () => openedBook++,
        onMenu: (value) => action = value,
      )),
    ));
    final focus = tester.widget<ListTile>(
      find.byKey(const ValueKey('row-Atlas')),
    ).focusNode!;
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Edit metadata'), findsOneWidget);
    expect(openedBook, 0);
    expect(action, isNull);
    await tester.tap(find.text('Edit metadata'));
    await tester.pumpAndSettle();
    expect(action, 'edit');
    expect(openedBook, 0);
  });

  testWidgets('disabled rows cannot open their menu from long press',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _row(id: 'Blocked', enabled: false)),
    ));
    await tester.longPress(find.byKey(const ValueKey('row-Blocked')));
    await tester.pumpAndSettle();
    expect(find.text('Edit metadata'), findsNothing);
  });

  testWidgets('focus and GlobalKey are reclaimed as lazy rows leave viewport',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: scroll,
          itemExtent: 72,
          itemCount: 1000,
          itemBuilder: (_, index) => _row(id: 'Book ' + index.toString()),
        ),
      ),
    ));
    final first = tester.widget<ListTile>(
      find.byKey(const ValueKey('row-Book 0')),
    ).focusNode!;
    expect(first.attached, isTrue);
    expect(find.byType(LibraryBookRowFocus).evaluate().length, lessThan(30),
        reason: 'A thousand-book catalog must construct only visible rows');
    scroll.jumpTo(72 * 400.0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row-Book 0')), findsNothing);
    expect(first.attached, isFalse,
        reason: 'Offscreen book focus nodes must not be stored forever');
    expect(find.byType(LibraryBookRowFocus).evaluate().length, lessThan(30));
    expect(find.byKey(const ValueKey('row-Book 400')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyed row preserves focus object through a local metadata edit',
      (tester) async {
    var name = 'Atlas';
    late StateSetter setHost;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (_, setState) {
        setHost = setState;
        return Scaffold(body: _row(id: name));
      }),
    ));
    final first = tester.widget<ListTile>(
      find.byKey(const ValueKey('row-Atlas')),
    ).focusNode!;
    // Update title with same book identity: a new label but no duplicated
    // focus resource. This is the same ownership pattern as LibraryScreen.
    setHost(() {});
    await tester.pump();
    final second = tester.widget<ListTile>(
      find.byKey(const ValueKey('row-Atlas')),
    ).focusNode!;
    expect(identical(first, second), isTrue);
    expect(tester.takeException(), isNull);
  });
}
