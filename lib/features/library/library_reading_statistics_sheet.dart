import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../domain/book.dart';
import '../../domain/library_reading_statistics.dart';
import '../../domain/reading_activity.dart';
import 'book_reading_activity_sheet.dart';

/// Snapshot of local metadata and explicitly recorded activity. Nothing in
/// this panel sends analytics, changes reading anchors or starts narration.
class LibraryReadingStatisticsSheet extends StatefulWidget {
  const LibraryReadingStatisticsSheet({
    super.key,
    required this.statistics,
    required this.store,
  });

  final LibraryReadingStatistics statistics;
  final LibraryStore store;

  @override
  State<LibraryReadingStatisticsSheet> createState() =>
      _LibraryReadingStatisticsSheetState();
}

class _LibraryReadingStatisticsSheetState
    extends State<LibraryReadingStatisticsSheet> {
  @override
  Widget build(BuildContext context) {
    final s = widget.statistics;
    final week = widget.store.weeklyReadingActivity();
    final activeBooks = widget.store.mostActiveReadingBooks();
    final color = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('library-stats-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.76,
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
              spacing: 16, runSpacing: 18,
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
            const SizedBox(height: 20),
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
            Text('Local reading and listening — last 7 days',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16, runSpacing: 8,
              children: [
                _StatisticNumber(
                  id: 'stats-reading-seconds', label: 'Visual reading (minutes)',
                  value: week.visualSeconds ~/ 60,
                ),
                _StatisticNumber(
                  id: 'stats-tts-seconds', label: 'TTS activity (minutes)',
                  value: week.ttsSeconds ~/ 60,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Daily reading goal')),
                DropdownButton<int>(
                  key: const ValueKey('stats-goal-dropdown'),
                  value: week.goalMinutes,
                  items: (<int>{0, 10, 15, 20, 30, 45, 60, 90, 120,
                          180, 240, week.goalMinutes}.toList()..sort())
                      .map((minutes) => DropdownMenuItem<int>(
                            value: minutes,
                            child: Text(minutes == 0
                                ? 'Off' : '$minutes min'),
                          )).toList(),
                  onChanged: (minutes) {
                    if (minutes == null) return;
                    widget.store.saveDailyReadingGoalMinutes(minutes);
                    setState(() {});
                  },
                ),
              ],
            ),
            Text(week.goalMinutes == 0
                ? 'Daily goal disabled.'
                : '${week.daysMeetingGoal} of 7 days met the goal.',
              key: const ValueKey('stats-goal-summary'),
            ),
            const SizedBox(height: 12),
            for (final day in week.days) _ActivityDayRow(
              day: day,
              goalMinutes: week.goalMinutes,
            ),
            const SizedBox(height: 24),
            Text('Most active books this week',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (activeBooks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No timed reading activity recorded yet.'),
              )
            else
              for (final book in activeBooks)
                ListTile(
                  key: ValueKey('stats-book-${book.bookId}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(book.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${formatReadingActivityDuration(book.visualSeconds)} read'
                    ' · ${formatReadingActivityDuration(book.ttsSeconds)} TTS',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => BookReadingActivitySheet(
                      store: widget.store,
                      bookId: book.bookId,
                    ),
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
                  contentPadding: EdgeInsets.zero, dense: true,
                  title: Text(book.title, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(MaterialLocalizations.of(context)
                      .formatMediumDate(book.lastOpenedAt!.toLocal())),
                ),
            const SizedBox(height: 12),
            Text(
              'The session timer uses conservative elapsed-time sampling. '
              'Visual reading counts only after recent reader interaction '
              'and stops after three idle minutes; TTS tracks active playback '
              'intent, not verified audible speech. Suspended periods may be '
              'undercounted. Reading and Finished are manual shelves, and '
              'opening timestamps are not session counts. Data stays local.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityDayRow extends StatelessWidget {
  const _ActivityDayRow({required this.day, required this.goalMinutes});
  final ReadingActivityDay day;
  final int goalMinutes;

  @override
  Widget build(BuildContext context) {
    final goalSeconds = goalMinutes * 60;
    final fraction = goalSeconds == 0 ? 0.0 :
        (day.totalSeconds / goalSeconds).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(day.date)),
              Text('${day.visualSeconds ~/ 60}m read · '
                  '${day.ttsSeconds ~/ 60}m TTS',
                  key: ValueKey('stats-day-${day.date}')),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: fraction, minHeight: 5),
        ],
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
