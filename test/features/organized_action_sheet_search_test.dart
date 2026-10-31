import 'package:ereader/features/shared/organized_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const sections = [
  OrganizedActionSection(title: 'Navigation', items: [
    OrganizedActionItem(id: 'search', title: 'Find in book',
        subtitle: 'Search original text', icon: Icons.search),
    OrganizedActionItem(id: 'chapters', title: 'Chapters',
        subtitle: 'Jump to a chapter', icon: Icons.list),
  ]),
  OrganizedActionSection(title: 'Voices', items: [
    OrganizedActionItem(id: 'offline', title: 'Offline neural voices',
        subtitle: 'Free voice models', icon: Icons.record_voice_over),
    OrganizedActionItem(id: 'cloud', title: 'Cloud provider',
        subtitle: 'Requires explicit consent', icon: Icons.cloud),
    OrganizedActionItem(id: 'locked', title: 'Unavailable voice',
        icon: Icons.lock, enabled: false, selected: true),
    OrganizedActionItem(id: 'pitch', title: 'Pitch',
        icon: Icons.tune),
    OrganizedActionItem(id: 'rate', title: 'Speech speed',
        icon: Icons.speed),
    OrganizedActionItem(id: 'cast', title: 'Character casting',
        icon: Icons.people),
  ]),
];

void main() {
  testWidgets('keyboard palette focuses search for immediate typing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () => showOrganizedActionSheet(
          context,
          title: 'Keyboard tools',
          sections: sections,
          autofocusSearch: true,
        ),
        child: const Text('Keyboard palette'),
      )),
    )));
    await tester.tap(find.text('Keyboard palette'));
    await tester.pumpAndSettle();
    final filter = tester.widget<TextField>(
        find.byKey(const ValueKey('organized-action-filter')));
    expect(filter.autofocus, isTrue);
    expect(tester.widget<EditableText>(
        find.byType(EditableText)).focusNode.hasFocus, isTrue);
    await tester.enterText(
        find.byKey(const ValueKey('organized-action-filter')), 'consent');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organized-action-cloud')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-offline')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('filter matches unordered words across title, subtitle and group', () {
    final matches = filterOrganizedActionSections(
        sections, '  VoIcEs  CONSENT  ');
    expect(matches, hasLength(1));
    expect(matches.single.title, 'Voices');
    expect(matches.single.items.map((item) => item.id), ['cloud']);
    expect(filterOrganizedActionSections(sections, 'original')
        .single.items.single.id, 'search');
    expect(filterOrganizedActionSections(sections, '  ')[0].items,
        same(sections[0].items));
  });

  test('search cannot enable a disabled item or change its selection', () {
    final matches = filterOrganizedActionSections(sections, 'unavailable');
    final locked = matches.single.items.single;
    expect(locked.id, 'locked');
    expect(locked.enabled, isFalse);
    expect(locked.selected, isTrue);
    expect(filterOrganizedActionSections(sections, 'not here'), isEmpty);
    expect(sections[1].items.length, 6);
  });

  testWidgets('large menu filters, clears and selects without triggering others',
      (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          selected = await showOrganizedActionSheet(context,
              title: 'Reader tools', sections: sections);
        },
        child: const Text('Open menu'),
      )),
    )));
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('organized-action-filter'));
    expect(field, findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-offline')),
        findsOneWidget);

    await tester.enterText(field, 'neural');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organized-action-offline')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-cloud')),
        findsNothing);
    expect(find.text('1 tool found'), findsOneWidget);
    expect(selected, isNull);

    await tester.enterText(field, 'xyz999');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organized-action-empty')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-count')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('organized-action-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organized-action-empty')),
        findsNothing);

    await tester.enterText(field, 'neural');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('organized-action-offline')));
    await tester.pumpAndSettle();
    expect(selected, 'offline');
    expect(find.text('Reader tools'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard search remains available in short PDF-like menus',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () => showOrganizedActionSheet(context,
            title: 'PDF page tools', sections: [sections.first],
            autofocusSearch: true),
        child: const Text('Open PDF palette'),
      )),
    )));
    await tester.tap(find.text('Open PDF palette'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('organized-action-filter'));
    expect(search, findsOneWidget);
    expect(tester.widget<EditableText>(
        find.byType(EditableText)).focusNode.hasFocus, isTrue);
    await tester.enterText(search, 'chapters');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organized-action-chapters')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('organized-action-search')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short menus keep the compact sheet without search',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () => showOrganizedActionSheet(context,
            title: 'Few commands',
            sections: [sections.first]),
        child: const Text('Open compact'),
      )),
    )));
    await tester.tap(find.text('Open compact'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organized-action-filter')),
        findsNothing);
    expect(find.byKey(const ValueKey('organized-action-search')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
