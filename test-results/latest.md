# EReader test report

* Result: **FAIL**
* Source: 7b9bd23034e082e99a2eeb4a2d3c0c3dc296d777 (feature/m0-flutter-foundation)
* Run: 20261025T120153Z-7b9bd230-236d92
* Cases: 555 passed, 6 failed, 2 errors, 0 skipped
* Test files discovered: 66

## All commands
| Command | Exit | Seconds | Timeout |
|---|---:|---:|---|
| flutter-version |  | 2.5 | False |
| dart-version |  | 1.2 | False |
| pub-get |  | 3.4 | False |
| format-check |  | 2.4 | False |
| flutter-analyze |  | 25 | False |
| flutter-test-all |  | 66.1 | False |
| individual-0001 |  | 6.6 | False |
| individual-0002 |  | 5.9 | False |
| individual-0003 |  | 7.3 | False |
| individual-0004 |  | 6 | False |
| individual-0005 |  | 5.8 | False |
| individual-0006 |  | 5.6 | False |
| individual-0007 |  | 6.5 | False |
| individual-0008 |  | 7 | False |
| individual-0009 |  | 5.5 | False |
| individual-0010 |  | 5.7 | False |
| individual-0011 |  | 5.3 | False |
| individual-0012 |  | 9.3 | False |
| individual-0013 |  | 7.5 | False |
| individual-0014 |  | 6 | False |
| individual-0015 |  | 5.9 | False |
| individual-0016 |  | 5.3 | False |
| individual-0017 |  | 5.4 | False |
| individual-0018 |  | 6.4 | False |
| individual-0019 |  | 5.7 | False |
| individual-0020 |  | 5.6 | False |
| individual-0021 |  | 6 | False |
| individual-0022 |  | 6 | False |
| individual-0023 |  | 6.7 | False |
| individual-0024 |  | 6.6 | False |
| individual-0025 |  | 5.2 | False |
| individual-0026 |  | 6.4 | False |
| individual-0027 |  | 13.1 | False |
| individual-0028 |  | 8 | False |
| individual-0029 |  | 5.8 | False |
| individual-0030 |  | 6.2 | False |
| individual-0031 |  | 7.1 | False |
| individual-0032 |  | 6.6 | False |
| individual-0033 |  | 5.5 | False |
| individual-0034 |  | 5.4 | False |
| individual-0035 |  | 6 | False |
| individual-0036 |  | 5.7 | False |
| individual-0037 |  | 5.5 | False |
| individual-0038 |  | 5 | False |
| individual-0039 |  | 5.2 | False |
| individual-0040 |  | 4.8 | False |
| individual-0041 |  | 4.7 | False |
| individual-0042 |  | 5.4 | False |
| individual-0043 |  | 5.2 | False |
| individual-0044 |  | 4.9 | False |
| individual-0045 |  | 4.9 | False |
| individual-0046 |  | 5.2 | False |
| individual-0047 |  | 4.6 | False |
| individual-0048 |  | 6.3 | False |
| individual-0049 |  | 5.5 | False |
| individual-0050 |  | 9 | False |
| individual-0051 |  | 13.8 | False |
| individual-0052 |  | 7.7 | False |
| individual-0053 |  | 5.3 | False |
| individual-0054 |  | 7.3 | False |
| individual-0055 |  | 10.8 | False |
| individual-0056 |  | 7.1 | False |
| individual-0057 |  | 5.9 | False |
| individual-0058 |  | 6.6 | False |
| individual-0059 |  | 5.5 | False |
| individual-0060 |  | 5.9 | False |
| individual-0061 |  | 6.2 | False |
| individual-0062 |  | 5.9 | False |
| individual-0063 |  | 5.7 | False |
| individual-0064 |  | 5.4 | False |
| individual-0065 |  | 6.1 | False |
| individual-0066 |  | 6.2 | False |

## Failures (complete list in JSON)
| Test file | Test case | Type |
|---|---|---|
| E:/GitHub/EReader/test/data/epub_encoding_integration_test.dart | declared Windows-1252 chapter keeps punctuation and style offsets | assertion |
| E:/GitHub/EReader/test/data/epub_encoding_integration_test.dart | UTF-16LE and BE XHTML chapters yield the same spoken source | assertion |
| E:/GitHub/EReader/test/data/epub_reader_preflight_test.dart | independent preflights cannot cancel each other | compile_or_runtime |
| E:/GitHub/EReader/test/data/epub_text_extractor_test.dart | malformed head heading never becomes source or chapter title | assertion |
| E:/GitHub/EReader/test/data/epub_text_extractor_test.dart | spine labels use XHTML body headings, not navigation or head | assertion |
| E:/GitHub/EReader/test/features/epub_chapter_navigation_test.dart | quote coalescing never merges across hard EPUB spine boundary | assertion |
| E:/GitHub/EReader/test/features/epub_opening_performance_sheet_test.dart | frame capture starts only by explicit action, and report shows bounded numeric timings | runtime |
| E:/GitHub/EReader/test/features/epub_progressive_layout_test.dart | 12000 paragraphs index without constructing any rich runs | assertion |

## Source locations of compilation/load errors (safe metadata)
| Test file | Source file | Line | Column |
|---|---|---:|---:|
| <full_suite> | test/features/epub_opening_performance_sheet_test.dart | 121 | 5 |
| test/features/epub_opening_performance_sheet_test.dart | test/features/epub_opening_performance_sheet_test.dart | 121 | 5 |

## Analyzer diagnostics
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\audio\mp3_playback.dart:127:59 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\mp3_playback.dart:160:26 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\mp3_playback.dart:161:64 - prefer_interpolation_to_compose_strings
-    info - Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' - lib\audio\mp3_playback.dart:341:7 - use_null_aware_elements
-    info - Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' - lib\audio\mp3_playback.dart:342:7 - use_null_aware_elements
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:57:24 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:101:24 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:138:30 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:191:21 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:191:42 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:229:9 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\audio\openai_speech_engine.dart:276:50 - curly_braces_in_flow_control_structures
- warning - Unnecessary cast. Try removing the cast - lib\audio\openai_speech_engine.dart:296:20 - unnecessary_cast
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._requestFocus') to initialize the field - lib\audio\reader_media_handler.dart:20:8 - prefer_initializing_formal
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\audio\reader_media_handler.dart:142:34 - unnecessary_non_null_assertion
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\audio\reader_media_handler.dart:181:34 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\audio\reader_media_handler.dart:198:61 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\audio\reader_media_handler.dart:201:63 - curly_braces_in_flow_control_structures
-    info - Unnecessary use of multiple underscores. Try using '_' - lib\audio\reader_media_handler.dart:214:62 - unnecessary_underscores
-    info - Unnecessary use of multiple underscores. Try using '_' - lib\audio\reader_media_handler.dart:266:56 - unnecessary_underscores
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._engine') to initialize the field - lib\audio\reader_player.dart:42:8 - prefer_initializing_formals
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._segments') to initialize the field - lib\audio\reader_player.dart:43:8 - prefer_initializing_formals
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\reader_player.dart:205:9 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\secret_vault.dart:20:12 - prefer_interpolation_to_compose_strings
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._root') to initialize the field - lib\audio\speech_audio_cache.dart:30:46 - prefer_initializing_formals
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\speech_audio_cache.dart:58:34 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\speech_audio_cache.dart:88:7 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\speech_audio_cache.dart:88:25 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\speech_engine_factory.dart:33:11 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_embedded_content.dart:68:45 - curly_braces_in_flow_control_structures
-    info - Statements in a while should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_embedded_content.dart:78:62 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_navigation.dart:69:35 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_navigation.dart:124:37 - curly_braces_in_flow_control_structures
-    info - Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' - lib\data\epub_reader_preflight.dart:67:5 - use_null_aware_elements
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_structural_markup.dart:98:63 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_structural_markup.dart:123:25 - curly_braces_in_flow_control_structures
- warning - Unused import: 'dart:convert'. Try removing the import directive - lib\data\epub_text_extractor.dart:1:8 - unused_import
-    info - Use 'isEmpty' instead of 'length' to test whether the collection is empty. Try rewriting the expression to use 'isEmpty' - lib\data\epub_text_extractor.dart:91:9 - prefer_is_empty
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_text_extractor.dart:171:39 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\data\epub_text_extractor.dart:213:31 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_text_extractor.dart:327:33 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_text_extractor.dart:381:47 - curly_braces_in_flow_control_structures
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\data\epub_text_extractor.dart:525:35 - unnecessary_non_null_assertion
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\data\epub_text_extractor.dart:527:55 - unnecessary_non_null_assertion
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\data\epub_text_extractor.dart:596:46 - prefer_interpolation_to_compose_strings
-    info - 'dispose' is deprecated and shouldn't be used. Call close() instead. Try replacing the use of the deprecated member with the replacement - lib\data\library_store.dart:404:10 - deprecated_member_use
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\library_store.dart:462:46 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\library_store.dart:475:45 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\data\library_store.dart:545:32 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\data\library_store.dart:549:28 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\library_store.dart:979:68 - curly_braces_in_flow_control_structures
-    info - 'dispose' is deprecated and shouldn't be used. Call close() instead. Try replacing the use of the deprecated member with the replacement - lib\data\library_store.dart:1981:10 - deprecated_member_use
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\cast_span.dart:173:56 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\cast_span.dart:217:61 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\cast_span.dart:224:65 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\cast_span.dart:270:43 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\cast_span.dart:272:41 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\cast_span.dart:276:44 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\cast_span.dart:279:43 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\cast_span.dart:281:41 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\cast_span.dart:292:43 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\cast_span.dart:294:41 - curly_braces_in_flow_control_structures
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\domain\dialogue_segmenter.dart:119:29 - unnecessary_non_null_assertion
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_inspector.dart:108:45 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_inspector.dart:118:63 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_inspector.dart:124:32 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_inspector.dart:129:59 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_inspector.dart:134:52 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_inspector.dart:142:67 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_review.dart:78:51 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_review.dart:81:58 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_review.dart:89:50 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_review.dart:93:34 - curly_braces_in_flow_control_structures
-    info - Statements in a while should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_review.dart:142:46 - curly_braces_in_flow_control_structures
-    info - Statements in a while should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_review.dart:177:55 - curly_braces_in_flow_control_structures
-    info - Statements in a while should be enclosed in a block. Try wrapping the statement in a block - lib\domain\dialogue_turn_review.dart:178:59 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\epub_anchor_context.dart:56:60 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\epub_anchor_context.dart:58:31 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\epub_anchor_context.dart:69:55 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\epub_anchor_context.dart:76:40 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\epub_anchor_context.dart:78:33 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\epub_anchor_context.dart:80:32 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\domain\speech_segment.dart:190:44 - curly_braces_in_flow_control_structures
-   error - The getter 'platform' isn't defined for the type 'FilePicker'. Try importing the library that defines 'platform', correcting the name to the name of an existing getter, or defining a getter or field named 'plat
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\features\reader\cast_merge_screen.dart:58:69 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:72:23 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:73:13 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:80:20 - prefer_interpolation_to_compose_strings
-    info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the depreca
-    info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the depreca
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:159:18 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:160:17 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:161:18 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:162:17 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:173:20 - prefer_interpolation_to_compose_strings
-    info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the depreca
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:188:34 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:194:37 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:194:69 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\features\reader\cast_merge_screen.dart:196:29 - prefer_interpolation_to_compose_strings

Raw stdout/stderr logs are saved locally and are never committed.