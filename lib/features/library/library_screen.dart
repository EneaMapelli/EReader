import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../data/picked_book_import.dart';
import '../../audio/reader_media_handler.dart';
import '../../domain/book.dart';
import '../../domain/library_catalog.dart';
import '../reader/reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.store, this.mediaHandler});
  final LibraryStore store;
  final ReaderMediaHandler? mediaHandler;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _busy = false;
  final _searchController = TextEditingController();
  String _query = '';
  BookFormat? _formatFilter;
  LibrarySortOrder _sortOrder = LibrarySortOrder.recentlyImported;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _formatFilter = null;
      _sortOrder = LibrarySortOrder.recentlyImported;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // file_picker v13 exposes a PlatformFile directly. Some Android SAF
      // providers expose only a stream, not a readable filesystem path.
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['epub', 'pdf', 'txt'],
      );
      if (selected == null) return;
      final record = await importPickedBook<BookRecord>(
        originalName: selected.name,
        pickedPath: selected.path,
        readAsByteStream: selected.readAsByteStream,
        importFile: widget.store.importFile,
      );
      if (!mounted) return;
      setState(() {});
      await _open(record);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot import book: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(BookRecord book) async {
    try {
      await widget.store.markBookOpened(book.id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: book, store: widget.store,
            mediaHandler: widget.mediaHandler,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot reopen book: $error')),
        );
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _editMetadata(BookRecord book) async {
    if (_busy || !mounted) return;
    var title = book.title;
    var author = book.author ?? '';
    var series = book.series ?? '';
    var language = book.language ?? '';
    final entered = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Edit book details'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('book-edit-title'),
                  initialValue: title,
                  onChanged: (value) => title = value,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextFormField(
                  key: const ValueKey('book-edit-author'),
                  initialValue: author,
                  onChanged: (value) => author = value,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Author'),
                ),
                TextFormField(
                  key: const ValueKey('book-edit-series'),
                  initialValue: series,
                  onChanged: (value) => series = value,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Series'),
                ),
                TextFormField(
                  key: const ValueKey('book-edit-language'),
                  initialValue: language,
                  onChanged: (value) => language = value,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    labelText: 'Language (e.g. it-IT)',
                    helperText: 'TTS voice is configured separately.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          if (book.format == BookFormat.epub)
            TextButton(
              onPressed: () => Navigator.pop(dialog, {
                'action': 'fill-missing',
              }),
              child: const Text('Fill from EPUB'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, {
              'title': title,
              'author': author,
              'series': series,
              'language': language,
            }),
            child: const Text('Save details'),
          ),
        ],
      ),
    );
    if (entered == null || !mounted) return;
    try {
      if (entered['action'] == 'fill-missing') {
        await widget.store.fillMissingEpubMetadata(book.id);
        if (mounted) setState(() {});
        return;
      }
      widget.store.updateBookMetadata(
        book.id,
        title: entered['title'] ?? '',
        author: entered['author'],
        series: entered['series'],
        language: entered['language'],
      );
      setState(() {});
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } on FileSystemException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
              'EPUB file is missing or cannot be read.')),
        );
      }
    } on StateError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Book is no longer in the library.')),
        );
      }
    }
  }

  Future<void> _remove(BookRecord book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove book?'),
        content: Text('Remove "${book.title}" from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.removeBook(book.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final allBooks = widget.store.books;
    final books = filterAndSortLibraryBooks(
      allBooks, query: _query, format: _formatFilter, sort: _sortOrder,
    );
    final lastOpened = widget.store.lastOpenedBook;
    final interrupted = widget.store.interruptedNarrationBook;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EReader'),
        actions: [
          IconButton(
            tooltip: 'Import book',
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      body: allBooks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_stories_outlined, size: 64),
                  const SizedBox(height: 12),
                  const Text('Your library is empty'),
                  const SizedBox(height: 8),
                  const Text('Import a TXT, EPUB, or PDF to begin'),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.add),
                    label: const Text('Import book'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (interrupted != null)
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: ListTile(
                      leading: const Icon(Icons.settings_backup_restore),
                      title: const Text('Narration interrupted'),
                      subtitle: Text(
                        '${interrupted.title} · Reopen at the saved position. '
                        'Audio will not start automatically.',
                      ),
                      isThreeLine: true,
                      onTap: () => _open(interrupted),
                      trailing: IconButton(
                        tooltip: 'Dismiss interrupted narration notice',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          widget.store.dismissInterruptedNarration();
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                if (lastOpened != null)
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('Continue reading'),
                      subtitle: Text(
                        '${lastOpened.title} · character ${lastOpened.progressOffset}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () => _open(lastOpened),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: TextField(
                    key: const ValueKey('library-search'),
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      labelText: 'Search library',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _query.isEmpty ? null : IconButton(
                        tooltip: 'Clear library search',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Row(
                    children: [
                      const Text('Sort'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<LibrarySortOrder>(
                          key: const ValueKey('library-sort'),
                          value: _sortOrder,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: LibrarySortOrder.recentlyImported,
                              child: Text('Recently imported')),
                            DropdownMenuItem(
                              value: LibrarySortOrder.titleAscending,
                              child: Text('Title A–Z')),
                            DropdownMenuItem(
                              value: LibrarySortOrder.titleDescending,
                              child: Text('Title Z–A')),
                            DropdownMenuItem(
                              value: LibrarySortOrder.authorAscending,
                              child: Text('Author A–Z')),
                            DropdownMenuItem(
                              value: LibrarySortOrder.seriesAscending,
                              child: Text('Series A–Z')),
                            DropdownMenuItem(
                              value: LibrarySortOrder.format,
                              child: Text('File format')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _sortOrder = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Row(
                    children: [
                      for (final format in <BookFormat?>[
                        null, BookFormat.epub, BookFormat.pdf, BookFormat.txt,
                      ]) ...[
                        ChoiceChip(
                          key: ValueKey('library-filter-${format?.name ?? 'all'}'),
                          label: Text(format?.name.toUpperCase() ?? 'All'),
                          selected: _formatFilter == format,
                          onSelected: (_) =>
                              setState(() => _formatFilter = format),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: books.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('No books match your filters.'),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _clearFilters,
                                child: const Text('Clear filters'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return ListTile(
                        leading: Icon(
                          book.format == BookFormat.pdf
                              ? Icons.picture_as_pdf_outlined
                              : Icons.menu_book_outlined,
                        ),
                        title: Text(book.title),
                        subtitle: Text(
                          [
                            if (book.author != null) book.author!,
                            if (book.series != null) book.series!,
                            if (book.language != null) book.language!,
                            book.format.name.toUpperCase(),
                            'saved at character ${book.progressOffset}',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _open(book),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit book details',
                              onPressed: () => _editMetadata(book),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Remove book',
                              onPressed: () => _remove(book),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: allBooks.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.add),
              label: const Text('Import'),
            )
          : null,
    );
  }
}
