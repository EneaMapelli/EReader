import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../audio/reader_media_handler.dart';
import '../../domain/book.dart';
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

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['epub', 'pdf', 'txt'],
      );
      if (result == null) return;
      final path = result.files.single.path;
      if (path == null) {
        throw const FormatException('File path unavailable from picker');
      }
      final record = await widget.store.importFile(path, originalName: result.files.single.name);
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
    final books = widget.store.books;
    final lastOpened = widget.store.lastOpenedBook;
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
      body: books.isEmpty
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
                Expanded(
                  child: ListView.builder(
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
                          '${book.format.name.toUpperCase()} · '
                          'saved at character ${book.progressOffset}',
                        ),
                        onTap: () => _open(book),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove book',
                          onPressed: () => _remove(book),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: books.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.add),
              label: const Text('Import'),
            )
          : null,
    );
  }
}
