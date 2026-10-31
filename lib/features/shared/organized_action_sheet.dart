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

/// Scrollable, constrained sheet: actions remain large tap targets on
/// Android and are readable on desktop without filling the AppBar.
/// Return values only; no operation is started until the sheet is closed.
Future<String?> showOrganizedActionSheet(
  BuildContext context, {
  required String title,
  required List<OrganizedActionSection> sections,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) {
    final screen = MediaQuery.sizeOf(sheetContext);
    final maxHeight = screen.height * 0.80;
    final theme = Theme.of(sheetContext);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            for (final section in sections)
              if (section.items.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Text(
                    section.title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                for (final item in section.items)
                  ListTile(
                    key: ValueKey('organized-action-${item.id}'),
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
                        ? () => Navigator.of(sheetContext).pop(item.id)
                        : null,
                  ),
              ],
          ],
        ),
      ),
    );
  },
);
