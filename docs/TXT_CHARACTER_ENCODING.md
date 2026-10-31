# M1 — Local TXT character encoding and safe text extraction

**Scope:** TXT files imported into EReader. This is not an OCR reader or
a replacement for PDF/EPUB extraction. The reader and FTS indexing share
the same `PrototypeDocumentDecoder` and therefore the same canonical
UTF-16 source positions.

## Supported decoding paths

| Input form | Behavior |
|---|---|
| UTF-8 without BOM | Strict UTF-8, preserve Unicode/smart punctuation |
| UTF-8 BOM (`EF BB BF`) | Remove only the leading BOM; reject malformed UTF-8 |
| UTF-16 little endian BOM (`FF FE`) | Decode 16-bit code units and validate surrogate pairs |
| UTF-16 big endian BOM (`FE FF`) | Same validation, big-endian code units |
| BOM-less UTF-16 | Conservative heuristic *only* when 60% or more sampled character pairs have zero high bytes and no more than 5% have zero low bytes |
| Windows-1252 / Latin-1-style legacy TXT | If unmarked input is invalid UTF-8, decode it as Windows-1252, including curly quotes, apostrophes, ellipsis, en/em dash and euro sign |

The heuristic deliberately does **not** try to guess arbitrary CJK
UTF-16 without a BOM. This avoids interpreting unknown binary data as
text. A malformed explicit UTF-8 or UTF-16 declaration is **not**
silently reinterpreted as another encoding.

The extraction happens on a separate Dart isolate, not the Flutter UI
isolate. The synchronous file reader inside that isolate refuses files
larger than the library's existing 100 MiB import limit. No network calls
or cloud requests are made by charset detection.

## Safety and source offsets

- UTF-16 input with an odd number of content bytes or unpaired
  high/low surrogates is rejected rather than replaced with Unicode
  U+FFFD.
- Clearly binary or misnamed TXT content (NUL bytes or excessive
  non-text control characters) is rejected with a `FormatException`.
  This is **not** a substitute for file-type sandboxing or antivirus.
- The decoded string is used unchanged by visual reading, TTS
  segmentation and the opt-in FTS index. A supplementary character such
  as an emoji occupies two Dart UTF-16 code units, preserving the
  existing reader source-anchor contract.
- Windows-1252 is a best-effort legacy fallback, **not** a complete
  statistical charset detector. Less common encodings, including
  Shift-JIS, GB18030 and KOI8-R, remain unsupported.
- No original text, file paths or encoding diagnostics are sent to
  analytics or third-party services during decoding.

## Regression coverage and status

- `test/data/plain_text_decoder_test.dart`: UTF-8+BOM, UTF-16 both
  byte orders, conservative BOM-less UTF-16, Windows punctuation,
  invalid UTF-8 declarations, malformed surrogates, binary rejection,
  and allowed line breaks.
- `test/data/book_decoder_test.dart`: end-to-end TXT decoding in
  `PrototypeDocumentDecoder`, visual source anchors and a binary-file
  refusal.
- `test/data/library_full_text_index_test.dart`: indexing a UTF-16 TXT
  and opening a full-text hit at the same UTF-16 position used by the
  freshly decoded reader.

**Code and tests authored but not executed.** The current environment
does not have a Dart/Flutter SDK. No Windows or Android binaries were
built and no GitHub Actions were started. Release requires verification
against real plain-text files on both platforms, including very large
books and their memory footprint.
