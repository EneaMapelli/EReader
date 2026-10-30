import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../domain/reading_activity.dart';

/// Detail of one book's measured local reading and listening totals.
/// The global daily goal is deliberately not attributed to individual books.
class BookReadingActivitySheet extends StatelessWidget {
  const BookReadingActivitySheet({
    super.key,
    required this.store,
    required this.bookId,
  });

  final LibraryStore store;
  final String bookId;

  @override
  Widget build(BuildContext context) {
    final lifetime = store.bookReadingLifetimeTotals(bookId);
    final week = store.weeklyReadingActivity(bookId: bookId);
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('stats-book-detail'),
        height: MediaQuery.sizeOf(context).height * 0.70,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(lifetime.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'Close book reading details',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('All recorded activity',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Reading: ${formatReadingActivityDuration(lifetime.visualSeconds)}  '
              '· TTS: ${formatReadingActivityDuration(lifetime.ttsSeconds)}',
              key: const ValueKey('stats-book-lifetime'),
            ),
            const SizedBox(height: 22),
            Text('Last seven calendar days',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Reading: ${formatReadingActivityDuration(week.visualSeconds)}  '
              '· TTS: ${formatReadingActivityDuration(week.ttsSeconds)}',
              key: const ValueKey('stats-book-week'),
            ),
            const SizedBox(height: 12),
            for (final day in week.days)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(day.date),
                subtitle: Text(
                  'Reading ${formatReadingActivityDuration(day.visualSeconds)}'
                  ' · TTS ${formatReadingActivityDuration(day.ttsSeconds)}',
                  key: ValueKey('stats-book-day-${day.date}'),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'These totals start when activity tracking was introduced. '
              'Visual time is a conservative interaction-based estimate; '
              'TTS time is based on playback state, not confirmed sound '
              'output. This view is read-only and all data stays on-device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
