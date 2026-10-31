import 'package:flutter/material.dart';

/// Shared, accessible action grouping for book and library navigation.
/// A sheet item returns an ID; callers own all side effects after the sheet
/// closes. This keeps destructive/bookkeeping actions out of the widget.
class OrganizedActionItem {
  const OrganizedActionItem({
    required this.id,
    required this.title,
    required this.icon,
    this.subtitle,
    this.enabled = true,
    this.selected = false,
  });

  final String id;
  final String title;
  final IconData icon;
  final String? subtitle;
  final bool enabled;
  final bool selected;
}

class OrganizedActionSection {
  const OrganizedActionSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<OrganizedActionItem> items;
}

/// Return only non-empty groups containing actions matched by all query words.
/// Matching is case-insensitive and includes group name, title and subtitle.
/// Original action objects, disabled state and selection markers are preserved.
List<OrganizedActionSection> filterOrganizedActionSections(
  List<OrganizedActionSection> sections,
  String query,
) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) {
    return [for (final section in sections)
      if (section.items.isNotEmpty) section];
  }
  return [
    for (final section in sections)
      if (section.items.isNotEmpty)
        OrganizedActionSection(
          title: section.title,
          items: [
            for (final item in section.items)
              if (words.every((word) =>
                  section.title.toLowerCase().contains(word) ||
                  item.title.toLowerCase().contains(word) ||
                  (item.subtitle?.toLowerCase().contains(word) ?? false)))
                item,
          ],
        ),
  ].where((section) => section.items.isNotEmpty).toList();
}

/// Search appears only in larger action sheets and never starts an operation.
/// The sheet is keyboard-aware; individual tiles still return only an ID.
Future<String?> showOrganizedActionSheet(
  BuildContext context, {
  required String title,
  required List<OrganizedActionSection> sections,
  bool autofocusSearch = false,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => _OrganizedActionSheetBody(
    title: title,
    sections: sections,
    autofocusSearch: autofocusSearch,
  ),
);

class _OrganizedActionSheetBody extends StatefulWidget {
  const _OrganizedActionSheetBody({
    required this.title,
    required this.sections,
    required this.autofocusSearch,
  });

  final String title;
  final List<OrganizedActionSection> sections;
  final bool autofocusSearch;

  @override
  State<_OrganizedActionSheetBody> createState() =>
      _OrganizedActionSheetBodyState();
}

class _OrganizedActionSheetBodyState extends State<_OrganizedActionSheetBody> {
  final TextEditingController _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final showFilter = widget.sections.fold<int>(
      0, (count, section) => count + section.items.length,
    ) >= 8;
    final filtered = filterOrganizedActionSections(
      widget.sections, _filterController.text,
    );
    final isSearching = _filterController.text.trim().isNotEmpty;
    final resultCount = filtered.fold<int>(
      0, (count, section) => count + section.items.length,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (screen.height * 0.80 - keyboardInset)
                .clamp(120.0, screen.height * 0.80)
                .toDouble(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.title, style: theme.textTheme.titleLarge),
                ),
              ),
              if (showFilter)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    key: const ValueKey('organized-action-filter'),
                    controller: _filterController,
                    // Only keyboard-invoked menus request text focus. Tapping
                    // the toolbar never opens the Android keyboard eagerly.
                    autofocus: widget.autofocusSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Find a tool',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _filterController.text.isEmpty
                          ? null
                          : IconButton(
                              key: const ValueKey('organized-action-clear'),
                              tooltip: 'Clear tool search',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _filterController.clear();
                                setState(() {});
                              },
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              if (showFilter && isSearching && resultCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        resultCount == 1 ? '1 tool found' :
                            '$resultCount tools found',
                        key: const ValueKey('organized-action-count'),
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No tools match your search.',
                          key: ValueKey('organized-action-empty'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    for (final section in filtered) ...[
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: Semantics(
                          header: true,
                          child: Text(
                            section.title,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      for (final item in section.items)
                        ListTile(
                          key: ValueKey('organized-action-' + item.id),
                          minLeadingWidth: 32,
                          leading: Icon(item.icon),
                          title: Text(item.title),
                          subtitle: item.subtitle == null
                              ? null : Text(item.subtitle!),
                          selected: item.selected,
                          trailing: item.selected
                              ? const Icon(Icons.check, size: 20) : null,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          onTap: item.enabled
                              ? () => Navigator.of(context).pop(item.id)
                              : null,
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
