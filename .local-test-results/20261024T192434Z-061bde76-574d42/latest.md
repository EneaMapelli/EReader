# EReader test report

* Result: **FAIL**
* Source: 061bde763ef321d6af828d45aaad080ad7264b42 (feature/m0-flutter-foundation)
* Run: 20261024T192434Z-061bde76-574d42
* Cases: 434 passed, 23 failed, 8 errors, 0 skipped
* Test files discovered: 61

## All commands
| Command | Exit | Seconds | Timeout |
|---|---:|---:|---|
| flutter-version |  | 2.2 | False |
| dart-version |  | 1 | False |
| pub-get |  | 2.4 | False |
| format-check |  | 2 | False |
| flutter-analyze |  | 18.9 | False |
| flutter-test-all |  | 42.7 | False |
| individual-0001 |  | 5 | False |
| individual-0002 |  | 5.1 | False |
| individual-0003 |  | 36.6 | False |
| individual-0004 |  | 5.4 | False |
| individual-0005 |  | 5.1 | False |
| individual-0006 |  | 34.8 | False |
| individual-0007 |  | 4.8 | False |
| individual-0008 |  | 6.1 | False |
| individual-0009 |  | 4.9 | False |
| individual-0010 |  | 4.5 | False |
| individual-0011 |  | 4.7 | False |
| individual-0012 |  | 7.2 | False |
| individual-0013 |  | 6.2 | False |
| individual-0014 |  | 5.6 | False |
| individual-0015 |  | 5.2 | False |
| individual-0016 |  | 5.4 | False |
| individual-0017 |  | 5 | False |
| individual-0018 |  | 5.3 | False |
| individual-0019 |  | 5.2 | False |
| individual-0020 |  | 5.3 | False |
| individual-0021 |  | 5.3 | False |
| individual-0022 |  | 5 | False |
| individual-0023 |  | 5.1 | False |
| individual-0024 |  | 5.6 | False |
| individual-0025 |  | 8.4 | False |
| individual-0026 |  | 5.6 | False |
| individual-0027 |  | 5.8 | False |
| individual-0028 |  | 5.8 | False |
| individual-0029 |  | 6.3 | False |
| individual-0030 |  | 6.1 | False |
| individual-0031 |  | 5.4 | False |
| individual-0032 |  | 5.3 | False |
| individual-0033 |  | 5.1 | False |
| individual-0034 |  | 6.1 | False |
| individual-0035 |  | 5.9 | False |
| individual-0036 |  | 5.3 | False |
| individual-0037 |  | 5.4 | False |
| individual-0038 |  | 4.7 | False |
| individual-0039 |  | 4.4 | False |
| individual-0040 |  | 5 | False |
| individual-0041 |  | 4.7 | False |
| individual-0042 |  | 4.4 | False |
| individual-0043 |  | 4.3 | False |
| individual-0044 |  | 4.4 | False |
| individual-0045 |  | 4.2 | False |
| individual-0046 |  | 4.6 | False |
| individual-0047 |  | 4.4 | False |
| individual-0048 |  | 6.9 | False |
| individual-0049 |  | 5.4 | False |
| individual-0050 |  | 4.3 | False |
| individual-0051 |  | 5.8 | False |
| individual-0052 |  | 9.6 | False |
| individual-0053 |  | 5.3 | False |
| individual-0054 |  | 5.1 | False |
| individual-0055 |  | 5 | False |
| individual-0056 |  | 4.4 | False |
| individual-0057 |  | 5.4 | False |
| individual-0058 |  | 4.7 | False |
| individual-0059 |  | 4.6 | False |
| individual-0060 |  | 4.4 | False |
| individual-0061 |  | 4.4 | False |

## Failures (complete list in JSON)
| Test file | Test case | Type |
|---|---|---|
| E:/GitHub/EReader/test/audio/cloud_prefetch_test.dart | opted-in prefetch waits until current audio is ready | assertion |
| E:/GitHub/EReader/test/audio/cloud_prefetch_test.dart | prefetch snapshots the NEXT character voice without switching now | assertion |
| E:/GitHub/EReader/test/audio/mp3_preload_test.dart | stop invalidates staged audio and removes private files | assertion |
| E:/GitHub/EReader/test/audio/mp3_preload_test.dart | dispose releases both native decoders and all temp MP3 files | assertion |
| E:/GitHub/EReader/test/audio/mp3_preload_test.dart | staged next clip loads on a second player and plays only once | assertion |
| E:/GitHub/EReader/test/audio/mp3_preload_test.dart | an older slow decoder load must not erase newer warmed MP3 | assertion |
| E:/GitHub/EReader/test/audio/mp3_preload_test.dart | old clip finalizer cannot stop a new playing clip after seek | assertion |
| E:/GitHub/EReader/test/audio/mp3_preload_test.dart | different rate must not use previously decoded speed settings | assertion |
| E:/GitHub/EReader/test/audio/mp3_preload_test.dart | only one future clip may be staged at a time | assertion |
| E:/GitHub/EReader/test/audio/mp3_preload_test.dart | stop during slow native warm-load leaves no playable stale MP3 | assertion |
| E:/GitHub/EReader/test/audio/narration_recovery_binding_test.dart | pause preserves marker until native stop completes, then clears | assertion |
| E:/GitHub/EReader/test/audio/narration_recovery_binding_test.dart | uncertain native Stop retains recovery checkpoint after dispose | assertion |
| E:/GitHub/EReader/test/audio/narration_recovery_binding_test.dart | binding can only attach once and dispose is idempotent | timeout |
| E:/GitHub/EReader/test/audio/native_stop_timeout_test.dart | Android remote Play refuses uncertain Stop without acquiring focus | assertion |
| E:/GitHub/EReader/test/audio/rapid_playback_navigation_test.dart | direct Play supersedes a blocked seek without a late jump | timeout |
| E:/GitHub/EReader/test/audio/reader_media_handler_test.dart | direct player Pause releases Android focus after native stop | assertion |
| E:/GitHub/EReader/test/audio/reader_media_handler_test.dart | failed native stop still clears focus after settled failure | assertion |
| E:/GitHub/EReader/test/audio/reader_player_test.dart | unsupported character voice falls back without extra narration | assertion |
| E:/GitHub/EReader/test/data/epub_navigation_test.dart | oversize note falls back to safe link navigation and preserves source | assertion |
| E:/GitHub/EReader/test/data/epub_text_extractor_test.dart | scripts, NAV and metadata never become styled reading content | assertion |
| E:/GitHub/EReader/test/domain/cross_chunk_cast_test.dart | unknown tags are never inherited across quote/narrator boundaries | assertion |
| E:/GitHub/EReader/test/domain/cross_chunk_cast_test.dart | one approved long quote retains voice across multiple TTS chunks | assertion |
| E:/GitHub/EReader/test/features/epub_chapter_navigation_test.dart | loading E:/GitHub/EReader/test/features/epub_chapter_navigation_test.dart | compile_or_runtime |
| E:/GitHub/EReader/test/features/epub_visual_layout_test.dart | spine boundaries prevent adjacent paragraphs from merging | assertion |
| E:/GitHub/EReader/test/llm/dialogue_analysis_plan_test.dart | multiple earlier context segments retain chronological evidence order | assertion |
| E:/GitHub/EReader/test/llm/historical_character_concordance_test.dart | loading E:/GitHub/EReader/test/llm/historical_character_concordance_test.dart | compile_or_runtime |
| E:/GitHub/EReader/test/llm/narrative_antecedent_finder_test.dart | prior name and alias map to one most-recent cue per person | assertion |
| E:/GitHub/EReader/test/llm/openai_alias_reconciler_test.dart | loading E:/GitHub/EReader/test/llm/openai_alias_reconciler_test.dart | compile_or_runtime |
| E:/GitHub/EReader/test/llm/openai_character_discoverer_test.dart | loading E:/GitHub/EReader/test/llm/openai_character_discoverer_test.dart | compile_or_runtime |
| E:/GitHub/EReader/test/llm/openai_dialogue_analyzer_test.dart | loading E:/GitHub/EReader/test/llm/openai_dialogue_analyzer_test.dart | compile_or_runtime |
| E:/GitHub/EReader/test/llm/openai_reference_resolver_test.dart | loading E:/GitHub/EReader/test/llm/openai_reference_resolver_test.dart | compile_or_runtime |

## Analyzer diagnostics
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\audio\mp3_playback.dart:99:59 - curly_braces_in_flow_control_structures
-    info - The 'if' statement could be replaced by a null-aware assignment. Try using the '??=' operator to conditionally assign a value - lib\audio\mp3_playback.dart:106:7 - prefer_conditional_assignment
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\mp3_playback.dart:125:24 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\mp3_playback.dart:126:62 - prefer_interpolation_to_compose_strings
-    info - Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' - lib\audio\mp3_playback.dart:257:30 - use_null_aware_elements
-    info - Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' - lib\audio\mp3_playback.dart:258:9 - use_null_aware_elements
-    info - Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' - lib\audio\mp3_playback.dart:272:30 - use_null_aware_elements
-    info - Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' - lib\audio\mp3_playback.dart:273:9 - use_null_aware_elements
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:57:24 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:101:24 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:138:30 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:181:21 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:181:42 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\openai_speech_engine.dart:219:9 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\audio\openai_speech_engine.dart:266:50 - curly_braces_in_flow_control_structures
- warning - Unnecessary cast. Try removing the cast - lib\audio\openai_speech_engine.dart:286:20 - unnecessary_cast
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._requestFocus') to initialize the field - lib\audio\reader_media_handler.dart:20:8 - prefer_initializing_formal
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\audio\reader_media_handler.dart:142:34 - unnecessary_non_null_assertion
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\audio\reader_media_handler.dart:181:34 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\audio\reader_media_handler.dart:198:61 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\audio\reader_media_handler.dart:201:63 - curly_braces_in_flow_control_structures
-    info - Unnecessary use of multiple underscores. Try using '_' - lib\audio\reader_media_handler.dart:214:62 - unnecessary_underscores
-    info - Unnecessary use of multiple underscores. Try using '_' - lib\audio\reader_media_handler.dart:266:56 - unnecessary_underscores
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._engine') to initialize the field - lib\audio\reader_player.dart:42:8 - prefer_initializing_formals
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._segments') to initialize the field - lib\audio\reader_player.dart:43:8 - prefer_initializing_formals
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\audio\reader_player.dart:200:9 - prefer_interpolation_to_compose_strings
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
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_structural_markup.dart:98:63 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_structural_markup.dart:123:25 - curly_braces_in_flow_control_structures
- warning - Unused import: 'dart:convert'. Try removing the import directive - lib\data\epub_text_extractor.dart:1:8 - unused_import
-    info - Use 'isEmpty' instead of 'length' to test whether the collection is empty. Try rewriting the expression to use 'isEmpty' - lib\data\epub_text_extractor.dart:90:9 - prefer_is_empty
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_text_extractor.dart:170:39 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\data\epub_text_extractor.dart:212:31 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_text_extractor.dart:326:33 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib\data\epub_text_extractor.dart:380:47 - curly_braces_in_flow_control_structures
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\data\epub_text_extractor.dart:524:35 - unnecessary_non_null_assertion
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib\data\epub_text_extractor.dart:526:55 - unnecessary_non_null_assertion
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib\data\epub_text_extractor.dart:595:46 - prefer_interpolation_to_compose_strings
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

Raw stdout/stderr logs are saved locally and are never committed.