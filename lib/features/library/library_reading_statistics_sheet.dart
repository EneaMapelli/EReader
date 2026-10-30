import 'package:flutter/material.dart';

import '../../domain/book.dart';
import '../../domain/library_reading_statistics.dart';

/// Read-only dashboard; does not modify books, anchors, playback or consent.
class LibraryReadingStatisticsSheet extends StatelessWidget {
  const LibraryReadingStatisticsSheet({
    super.key,
    required this.statistics,
  });

  final LibraryReadingStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final s = statistics;
    final color = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('library-stats-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.68,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Reading statistics',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'Close reading statistics',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Private overview of all books, independent of library filters.',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 18,
              children: [
                _StatisticNumber(label: 'Total books', value: s.totalBooks,
                    id: 'stats-total'),
                _StatisticNumber(
                    label: 'To read', id: 'stats-to-read',
                    value: s.countForStatus(BookReadingStatus.toRead)),
                _StatisticNumber(
                    label: 'Reading', id: 'stats-reading',
                    value: s.countForStatus(BookReadingStatus.reading)),
                _StatisticNumber(
                    label: 'Finished (manual)', id: 'stats-finished',
                    value: s.countForStatus(BookReadingStatus.finished)),
                _StatisticNumber(
                    label: 'Opened at least once', id: 'stats-opened',
                    value: s.everOpenedBooks),
                _StatisticNumber(
                    label: 'Last opened within 7 days', id: 'stats-recent',
                    value: s.openedInLastSevenDays),
                _StatisticNumber(
                    label: 'Favorites', id: 'stats-favorites',
                    value: s.favoriteBooks),
              ],
            ),
            const SizedBox(height: 24),
            Text('Books marked finished',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Semantics(
              label: 'Manually finished books: ${s.countForStatus(BookReadingStatus.finished)} of ${s.totalBooks}',
              child: LinearProgressIndicator(
                value: s.finishedFraction,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 24),
            Text('Library by format',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final format in BookFormat.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(format.name.toUpperCase())),
                    Text(s.countForFormat(format).toString(),
                        key: ValueKey('stats-format-${format.name}')),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Text('Recently opened books',
                style: Theme.of(context).textTheme.titleMedium),
            if (s.recentBooks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No recorded book openings yet.'),
              )
            else
              for (final book in s.recentBooks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(book.title, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(MaterialLocalizations.of(context)
                      .formatMediumDate(book.lastOpenedAt!.toLocal())),
                ),
            const SizedBox(height: 12),
            Text(
              'These figures use only local catalog metadata. Reading and '
              'Finished are manually chosen shelves. Last opened is a single '
              'timestamp per book, not an event history; minutes, pages read, '
              'reading streaks and daily goals are not measured yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatisticNumber extends StatelessWidget {
  const _StatisticNumber({
    required this.label,
    required this.value,
    required this.id,
  });

  final String label;
  final int value;
  final String id;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 144,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value.toString(), key: ValueKey(id),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
