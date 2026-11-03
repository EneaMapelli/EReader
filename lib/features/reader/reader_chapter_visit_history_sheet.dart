import 'package:flutter/material.dart';

import '../../domain/reading_progress.dart';
import 'reader_chapter_visit_history.dart';

/// Shows committed EPUB chapter-switch origins, newest first.
///
/// The sheet never seeks or writes checkpoints; it returns the exact entry
/// object that was selected. The reader validates its identity and revision
/// against the live session before requesting any return.
Future<ReaderChapterVisit?> showReaderChapterVisitHistory(
  BuildContext context, {
  required List<ReaderChapterVisit> visits,
  required int sourceLength,
}) {
  if (visits.isEmpty || sourceLength <= 0) {
    return Future<ReaderChapterVisit?>.value(null);
  }
  return showModalBottomSheet<ReaderChapterVisit>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _ReaderChapterVisitHistorySheet(
      visits: List<ReaderChapterVisit>.unmodifiable(visits),
      sourceLength: sourceLength,
    ),
  );
}

class _ReaderChapterVisitHistorySheet extends StatelessWidget {
  const _ReaderChapterVisitHistorySheet({
    required this.visits,
    required this.sourceLength,
  });

  final List<ReaderChapterVisit> visits;
  final int sourceLength;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (height * 0.78).clamp(180.0, height).toDouble(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Recent chapter positions'),
              subtitle: Text(visits.length == 1
                  ? '1 saved visit in this reading session'
                  : '${visits.length} saved visits in this reading session'),
              trailing: IconButton(
                key: const ValueKey('reader-chapter-history-close'),
                tooltip: 'Close chapter history',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Flexible(
              child: ListView.builder(
                key: const ValueKey('reader-chapter-history-list'),
                shrinkWrap: true,
                itemCount: visits.length,
                itemBuilder: (context, index) {
                  final visit = visits[index];
                  final percent = ReadingSourceProgress.percentage(
                    offset: visit.sourceOffset,
                    length: sourceLength,
                  );
                  final section = 'Section ${visit.sectionNumber} '
                      'of ${visit.sectionCount}';
                  return ListTile(
                    key: ValueKey('reader-chapter-history-entry-$index'),
                    leading: const Icon(Icons.history),
                    title: Text(
                      visit.sectionTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('$section · $percent% of book'),
                    trailing: const Icon(Icons.chevron_right),
                    minVerticalPadding: 8,
                    onTap: () => Navigator.of(context).pop(visit),
                    titleTextStyle: theme.textTheme.bodyLarge,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
