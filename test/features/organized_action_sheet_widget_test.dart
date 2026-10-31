import 'package:ereader/features/shared/organized_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('actions are grouped and run only after explicit selection',
      (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => FilledButton(
        onPressed: () async {
          selected = await showOrganizedActionSheet(
            context, title: 'Reader tools',
            sections: const [
              OrganizedActionSection(title: 'Navigate & find', items: [
                OrganizedActionItem(
                  id: 'search', title: 'Search this book',
                  icon: Icons.search, subtitle: 'Find a passage',
                ),
              ]),
              OrganizedActionSection(title: 'Reading appearance', items: [
                OrganizedActionItem(
                  id: 'night', title: 'Night reading',
                  icon: Icons.dark_mode_outlined, selected: true,
                ),
              ]),
              OrganizedActionSection(title: 'Unavailable', items: [
                OrganizedActionItem(
                  id: 'disabled', title: 'Disabled option',
                  icon: Icons.lock_outline, enabled: false,
                ),
              ]),
            ],
          );
        },
        child: const Text('Open tools'),
      )),
    )));
    await tester.tap(find.text('Open tools'));
    await tester.pumpAndSettle();
    expect(find.text('Reader tools'), findsOneWidget);
    expect(find.text('Navigate & find'), findsOneWidget);
    expect(find.text('Reading appearance'), findsOneWidget);
    expect(selected, isNull);
    final selectedTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('organized-action-night')));
    expect(selectedTile.selected, isTrue);
    final disabledTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('organized-action-disabled')));
    expect(disabledTile.onTap, isNull);
    await tester.ensureVisible(
        find.byKey(const ValueKey('organized-action-search')));
    await tester.tap(
        find.byKey(const ValueKey('organized-action-search')));
    await tester.pumpAndSettle();
    expect(selected, 'search');
    expect(find.text('Reader tools'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long action menus remain scrollable on a narrow phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(340, 480));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    String? chosen;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          chosen = await showOrganizedActionSheet(context,
              title: 'Many actions',
              sections: [
                OrganizedActionSection(title: 'Settings', items: [
                  for (var i = 0; i < 22; i++)
                    OrganizedActionItem(
                      id: 'option-$i', title: 'Option $i',
                      icon: Icons.settings_outlined,
                    ),
                ]),
              ]);
        },
        child: const Text('Open many'),
      )),
    )));
    await tester.tap(find.text('Open many'));
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('organized-action-option-21'));
    await tester.scrollUntilVisible(
        target, 350, scrollable: find.byType(Scrollable).last);
    expect(target, findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(chosen, 'option-21');
    expect(tester.takeException(), isNull);
  });
}
