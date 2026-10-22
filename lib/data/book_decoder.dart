import 'dart:convert';
import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' as html_parser;

import '../domain/book.dart';

class DocumentContent {
  const DocumentContent({required this.text, required this.title});
  final String text;
  final String title;
}

abstract interface class DocumentDecoder {
  Future<DocumentContent> read(BookRecord record);
}

/// An initial extraction POC. EPUB3 spine ordering, images, footnotes,
/// stable CFI anchors, ZIP bomb handling and PDF text layer remain open M0/M1
/// gates. In particular, this is not a full-fidelity EPUB renderer.
class PrototypeDocumentDecoder implements DocumentDecoder {
  @override
  Future<DocumentContent> read(BookRecord record) async {
    final file = File(record.localPath);
    if (!await file.exists()) {
      throw FileSystemException('Book file not found', file.path);
    }
    switch (record.format) {
      case BookFormat.txt:
        final bytes = await file.readAsBytes();
        final text = utf8.decode(bytes, allowMalformed: true);
        return DocumentContent(
          title: record.title,
          text: text.startsWith('\uFEFF') ? text.substring(1) : text,
        );
      case BookFormat.epub:
        final bytes = await file.readAsBytes();
        final epub = await EpubReader.readBook(bytes);
        final chunks = <String>[];
        void addChapter(EpubChapter chapter) {
          final raw = chapter.HtmlContent ?? '';
          if (raw.isNotEmpty) {
            final withBreaks = raw.replaceAll(
              RegExp(r'</(p|div|h[1-6]|li|blockquote)>', caseSensitive: false),
              '\n\n',
            );
            final document = html_parser.parse(withBreaks);
            document.querySelectorAll('script,style').forEach(
              (element) => element.remove(),
            );
            final text = document.body?.text.trim() ?? '';
            if (text.isNotEmpty) chunks.add(text);
          }
          for (final child in chapter.SubChapters ?? <EpubChapter>[]) {
            addChapter(child);
          }
        }
        for (final chapter in epub.Chapters ?? <EpubChapter>[]) {
          addChapter(chapter);
        }
        final text = chunks.join('\n\n');
        if (text.isEmpty) {
          throw const FormatException('No readable text found in EPUB');
        }
        return DocumentContent(title: epub.Title ?? record.title, text: text);
      case BookFormat.pdf:
        throw UnsupportedError(
          'PDF text extraction is not enabled yet; open the visual PDF viewer.',
        );
    }
  }
}
