import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// The renderer is injectable so library/thumbnail tests need no native
/// PDFium installation. Only the first page is rendered, never uploaded.
typedef PdfCoverRenderer = Future<Uint8List?> Function(String localPath);

/// Renders a deliberately small, opaque first-page PNG. PDFium handles are
/// released on success and failure; corrupt/encrypted PDFs are handled by
/// the caller as an absent preview, not as an import failure.
Future<Uint8List?> renderPdfFirstPageThumbnail(String localPath) async {
  final document = await PdfDocument.openFile(localPath);
  try {
    if (document.pages.isEmpty) return null;
    final page = document.pages.first;
    final width = page.width;
    final height = page.height;
    if (!width.isFinite || !height.isFinite ||
        width <= 0 || height <= 0) return null;
    // Bound the native pixel allocation even for huge/pathological page
    // dimensions and respect portrait/landscape page proportions.
    final scale = math.min(180.0 / width, 260.0 / height);
    final image = await page.render(
      fullWidth: math.max(1.0, width * scale),
      fullHeight: math.max(1.0, height * scale),
    );
    if (image == null) return null;
    try {
      final decoded = await image.createImage();
      try {
        final png = await decoded.toByteData(format: ui.ImageByteFormat.png);
        return png == null ? null : Uint8List.fromList(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
      } finally {
        decoded.dispose();
      }
    } finally {
      image.dispose();
    }
  } finally {
    await document.dispose();
  }
}
