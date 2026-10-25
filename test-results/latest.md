# EReader test report

* Result: **FAIL**
* Source: 946fc7b9dae008bbe92e89248921bad6430f7a50 (feature/m0-flutter-foundation)
* Run: 20261025T165839Z-946fc7b9-dc2652
* Cases: 589 passed, 0 failed, 5 errors, 0 skipped
* Test files discovered: 67

## All commands
| Command | Exit | Seconds | Timeout |
|---|---:|---:|---|
| flutter-version | 125 | 2.7 | False |
| dart-version | 125 | 1.6 | False |
| pub-get | 125 | 4.6 | False |
| format-check | 125 | 3.2 | False |
| flutter-analyze | 125 | 27.3 | False |
| flutter-test-all | 125 | 42.8 | False |
| individual-0001 | 125 | 7.5 | False |
| individual-0002 | 125 | 6.8 | False |
| individual-0003 | 125 | 7.5 | False |
| individual-0004 | 125 | 7.4 | False |
| individual-0005 | 125 | 7.2 | False |
| individual-0006 | 125 | 6 | False |
| individual-0007 | 125 | 5.1 | False |
| individual-0008 | 125 | 7.6 | False |
| individual-0009 | 125 | 7.8 | False |
| individual-0010 | 125 | 6.3 | False |
| individual-0011 | 125 | 6.7 | False |
| individual-0012 | 125 | 10.7 | False |
| individual-0013 | 125 | 7.7 | False |
| individual-0014 | 125 | 7.4 | False |
| individual-0015 | 125 | 6.6 | False |
| individual-0016 | 125 | 8.4 | False |
| individual-0017 | 125 | 7.2 | False |
| individual-0018 | 125 | 5.9 | False |
| individual-0019 | 125 | 6.2 | False |
| individual-0020 | 125 | 8.1 | False |
| individual-0021 | 125 | 7 | False |
| individual-0022 | 125 | 6.9 | False |
| individual-0023 | 125 | 9.4 | False |
| individual-0024 | 125 | 14.1 | False |
| individual-0025 | 125 | 8.3 | False |
| individual-0026 | 125 | 7.8 | False |
| individual-0027 | 125 | 11.3 | False |
| individual-0028 | 125 | 6.9 | False |
| individual-0029 | 125 | 6.3 | False |
| individual-0030 | 125 | 6.9 | False |
| individual-0031 | 125 | 7.3 | False |
| individual-0032 | 125 | 7.7 | False |
| individual-0033 | 125 | 8 | False |
| individual-0034 | 125 | 6.5 | False |
| individual-0035 | 125 | 7.3 | False |
| individual-0036 | 125 | 8.1 | False |
| individual-0037 | 125 | 8.3 | False |
| individual-0038 | 125 | 6 | False |
| individual-0039 | 125 | 7.5 | False |
| individual-0040 | 125 | 8.3 | False |
| individual-0041 | 125 | 6.5 | False |
| individual-0042 | 125 | 7.3 | False |
| individual-0043 | 125 | 7.7 | False |
| individual-0044 | 125 | 7.3 | False |
| individual-0045 | 125 | 5.7 | False |
| individual-0046 | 125 | 6.3 | False |
| individual-0047 | 125 | 5.8 | False |
| individual-0048 | 125 | 6.4 | False |
| individual-0049 | 125 | 7.3 | False |
| individual-0050 | 125 | 13 | False |
| individual-0051 | 125 | 6.7 | False |
| individual-0052 | 125 | 7.1 | False |
| individual-0053 | 125 | 5.8 | False |
| individual-0054 | 125 | 7.3 | False |
| individual-0055 | 125 | 7.2 | False |
| individual-0056 | 125 | 11.7 | False |
| individual-0057 | 125 | 7.9 | False |
| individual-0058 | 125 | 6.5 | False |
| individual-0059 | 125 | 6.6 | False |
| individual-0060 | 125 | 5.7 | False |
| individual-0061 | 125 | 6.1 | False |
| individual-0062 | 125 | 7.6 | False |
| individual-0063 | 125 | 5.2 | False |
| individual-0064 | 125 | 8.9 | False |
| individual-0065 | 125 | 12.6 | False |
| individual-0066 | 125 | 11.4 | False |
| individual-0067 | 125 | 7.2 | False |

## Failures (complete list in JSON)
| Test file | Test case | Type |
|---|---|---|
| test/data/epub_reader_preflight_test.dart | independent preflights cannot cancel each other | compile_or_runtime |
| test/features/book_source_search_widget_test.dart | closed search dialog never navigates or starts playback | runtime |
| test/features/book_source_search_widget_test.dart | EPUB search begins near reading position before wrapping | runtime |
| test/features/book_source_search_widget_test.dart | EPUB source search navigates to silent caption source offset | runtime |
| test/features/epub_opening_performance_sheet_test.dart | frame capture starts only by explicit action, and report shows bounded numeric timings | runtime |

## Source locations of compilation/load errors (safe metadata)
| Test file | Source file | Line | Column |
|---|---|---:|---:|
| <full_suite> | lib/features/reader/reading_tools.dart | 107 | 16 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 23 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 23 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 26 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 26 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 27 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 28 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 28 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 29 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 55 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 55 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 56 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 56 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 57 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 58 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 58 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 59 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 84 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 84 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 85 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 85 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 86 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 87 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 87 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 88 | 5 |
| <full_suite> | test/features/epub_opening_performance_sheet_test.dart | 132 | 5 |
| test/features/book_source_search_widget_test.dart | lib/features/reader/reading_tools.dart | 107 | 16 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 23 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 23 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 26 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 26 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 27 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 28 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 28 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 29 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 55 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 55 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 56 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 56 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 57 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 58 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 58 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 59 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 84 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 84 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 85 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 85 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 86 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 87 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 87 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 88 | 5 |
| test/features/epub_opening_performance_sheet_test.dart | test/features/epub_opening_performance_sheet_test.dart | 132 | 5 |

## Analyzer diagnostics
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/audio/mp3_playback.dart:127:59 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/mp3_playback.dart:160:26 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/mp3_playback.dart:161:64 - prefer_interpolation_to_compose_strings
-    info - Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' - lib/audio/mp3_playback.dart:341:7 - use_null_aware_elements
-    info - Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' - lib/audio/mp3_playback.dart:342:7 - use_null_aware_elements
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/openai_speech_engine.dart:57:24 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/openai_speech_engine.dart:101:24 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/openai_speech_engine.dart:138:30 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/openai_speech_engine.dart:191:21 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/openai_speech_engine.dart:191:42 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/openai_speech_engine.dart:229:9 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/audio/openai_speech_engine.dart:276:50 - curly_braces_in_flow_control_structures
- warning - Unnecessary cast. Try removing the cast - lib/audio/openai_speech_engine.dart:296:20 - unnecessary_cast
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._requestFocus') to initialize the field - lib/audio/reader_media_handler.dart:20:8 - prefer_initializing_formal
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib/audio/reader_media_handler.dart:142:34 - unnecessary_non_null_assertion
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/audio/reader_media_handler.dart:181:34 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/audio/reader_media_handler.dart:198:61 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/audio/reader_media_handler.dart:201:63 - curly_braces_in_flow_control_structures
-    info - Unnecessary use of multiple underscores. Try using '_' - lib/audio/reader_media_handler.dart:214:62 - unnecessary_underscores
-    info - Unnecessary use of multiple underscores. Try using '_' - lib/audio/reader_media_handler.dart:266:56 - unnecessary_underscores
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._engine') to initialize the field - lib/audio/reader_player.dart:42:8 - prefer_initializing_formals
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._segments') to initialize the field - lib/audio/reader_player.dart:43:8 - prefer_initializing_formals
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/reader_player.dart:205:9 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/secret_vault.dart:20:12 - prefer_interpolation_to_compose_strings
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._root') to initialize the field - lib/audio/speech_audio_cache.dart:30:46 - prefer_initializing_formals
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/speech_audio_cache.dart:58:34 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/speech_audio_cache.dart:88:7 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/speech_audio_cache.dart:88:25 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/speech_engine_factory.dart:33:11 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_embedded_content.dart:68:45 - curly_braces_in_flow_control_structures
-    info - Statements in a while should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_embedded_content.dart:78:62 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_navigation.dart:69:35 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_navigation.dart:124:37 - curly_braces_in_flow_control_structures
-    info - Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' - lib/data/epub_reader_preflight.dart:67:5 - use_null_aware_elements
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_structural_markup.dart:98:63 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_structural_markup.dart:123:25 - curly_braces_in_flow_control_structures
- warning - Unused import: 'dart:convert'. Try removing the import directive - lib/data/epub_text_extractor.dart:1:8 - unused_import
-    info - Use 'isEmpty' instead of 'length' to test whether the collection is empty. Try rewriting the expression to use 'isEmpty' - lib/data/epub_text_extractor.dart:91:9 - prefer_is_empty
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_text_extractor.dart:171:39 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/data/epub_text_extractor.dart:213:31 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_text_extractor.dart:327:33 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_text_extractor.dart:381:47 - curly_braces_in_flow_control_structures
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib/data/epub_text_extractor.dart:525:35 - unnecessary_non_null_assertion
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib/data/epub_text_extractor.dart:527:55 - unnecessary_non_null_assertion
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/data/epub_text_extractor.dart:596:46 - prefer_interpolation_to_compose_strings
-    info - 'dispose' is deprecated and shouldn't be used. Call close() instead. Try replacing the use of the deprecated member with the replacement - lib/data/library_store.dart:404:10 - deprecated_member_use
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/library_store.dart:462:46 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/library_store.dart:475:45 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/data/library_store.dart:545:32 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/data/library_store.dart:549:28 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/library_store.dart:979:68 - curly_braces_in_flow_control_structures
-    info - 'dispose' is deprecated and shouldn't be used. Call close() instead. Try replacing the use of the deprecated member with the replacement - lib/data/library_store.dart:1981:10 - deprecated_member_use
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/book_search.dart:79:61 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/book_search.dart:82:59 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/cast_span.dart:173:56 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/cast_span.dart:217:61 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/cast_span.dart:224:65 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/cast_span.dart:270:43 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/cast_span.dart:272:41 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/cast_span.dart:276:44 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/cast_span.dart:279:43 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/cast_span.dart:281:41 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/cast_span.dart:292:43 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/cast_span.dart:294:41 - curly_braces_in_flow_control_structures
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib/domain/dialogue_segmenter.dart:150:29 - unnecessary_non_null_assertion
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_inspector.dart:108:45 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_inspector.dart:118:63 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_inspector.dart:124:32 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_inspector.dart:129:59 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_inspector.dart:134:52 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_inspector.dart:142:67 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_review.dart:78:51 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_review.dart:81:58 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_review.dart:89:50 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_review.dart:93:34 - curly_braces_in_flow_control_structures
-    info - Statements in a while should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_review.dart:142:46 - curly_braces_in_flow_control_structures
-    info - Statements in a while should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_review.dart:177:55 - curly_braces_in_flow_control_structures
-    info - Statements in a while should be enclosed in a block. Try wrapping the statement in a block - lib/domain/dialogue_turn_review.dart:178:59 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/epub_anchor_context.dart:56:60 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/epub_anchor_context.dart:58:31 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/epub_anchor_context.dart:69:55 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/epub_anchor_context.dart:76:40 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/epub_anchor_context.dart:78:33 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/epub_anchor_context.dart:80:32 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/speech_segment.dart:215:44 - curly_braces_in_flow_control_structures
-   error - The getter 'platform' isn't defined for the type 'FilePicker'. Try importing the library that defines 'platform', correcting the name to the name of an existing getter, or defining a getter or field named 'plat
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/features/reader/cast_merge_screen.dart:58:69 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/features/reader/cast_merge_screen.dart:72:23 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/features/reader/cast_merge_screen.dart:73:13 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/features/reader/cast_merge_screen.dart:80:20 - prefer_interpolation_to_compose_strings
-    info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the depreca
-    info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the depreca
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/features/reader/cast_merge_screen.dart:159:18 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/features/reader/cast_merge_screen.dart:160:17 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/features/reader/cast_merge_screen.dart:161:18 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/features/reader/cast_merge_screen.dart:162:17 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/features/reader/cast_merge_screen.dart:173:20 - prefer_interpolation_to_compose_strings
-    info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the depreca
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/features/reader/cast_merge_screen.dart:188:34 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/features/reader/cast_merge_screen.dart:194:37 - prefer_interpolation_to_compose_strings

Raw stdout/stderr logs are saved locally and are never committed.