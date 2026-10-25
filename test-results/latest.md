# EReader test report

* Result: **FAIL**
* Source: 7c89dfc8008fa123a544b9a70f95a653563c5834 (feature/m0-flutter-foundation)
* Run: 20261025T201001Z-7c89dfc8-a63603
* Cases: 641 passed, 0 failed, 7 errors, 0 skipped
* Test files discovered: 76

## All commands
| Command | Exit | Seconds | Timeout |
|---|---:|---:|---|
| flutter-version | 0 | 2.1 | False |
| dart-version | 0 | 0.9 | False |
| pub-get | 0 | 2.8 | False |
| format-check | 1 | 2.6 | False |
| flutter-analyze | 1 | 15.3 | False |
| flutter-test-all | 1 | 45.7 | False |
| individual-0001 | 0 | 7.8 | False |
| individual-0002 | 0 | 6.6 | False |
| individual-0003 | 0 | 8.1 | False |
| individual-0004 | 0 | 7.4 | False |
| individual-0005 | 0 | 6.1 | False |
| individual-0006 | 0 | 7.2 | False |
| individual-0007 | 0 | 5.8 | False |
| individual-0008 | 0 | 6.5 | False |
| individual-0009 | 0 | 6.3 | False |
| individual-0010 | 0 | 7.5 | False |
| individual-0011 | 0 | 7.8 | False |
| individual-0012 | 0 | 6.1 | False |
| individual-0013 | 0 | 6.5 | False |
| individual-0014 | 0 | 5.3 | False |
| individual-0015 | 0 | 5.4 | False |
| individual-0016 | 0 | 4.9 | False |
| individual-0017 | 0 | 8.3 | False |
| individual-0018 | 0 | 6.9 | False |
| individual-0019 | 0 | 6.2 | False |
| individual-0020 | 0 | 5.9 | False |
| individual-0021 | 0 | 5.3 | False |
| individual-0022 | 0 | 5 | False |
| individual-0023 | 0 | 6.3 | False |
| individual-0024 | 0 | 6 | False |
| individual-0025 | 0 | 5.9 | False |
| individual-0026 | 0 | 5.8 | False |
| individual-0027 | 0 | 5.7 | False |
| individual-0028 | 0 | 5.6 | False |
| individual-0029 | 1 | 6.5 | False |
| individual-0030 | 0 | 5.7 | False |
| individual-0031 | 0 | 5.7 | False |
| individual-0032 | 0 | 11.1 | False |
| individual-0033 | 0 | 6.8 | False |
| individual-0034 | 0 | 6.7 | False |
| individual-0035 | 0 | 5.7 | False |
| individual-0036 | 0 | 5.9 | False |
| individual-0037 | 0 | 4.8 | False |
| individual-0038 | 0 | 8.5 | False |
| individual-0039 | 0 | 6.5 | False |
| individual-0040 | 0 | 4.8 | False |
| individual-0041 | 0 | 5.2 | False |
| individual-0042 | 0 | 5.4 | False |
| individual-0043 | 0 | 5.3 | False |
| individual-0044 | 0 | 6.1 | False |
| individual-0045 | 0 | 5.1 | False |
| individual-0046 | 0 | 4.9 | False |
| individual-0047 | 0 | 5.4 | False |
| individual-0048 | 0 | 6.6 | False |
| individual-0049 | 0 | 5.9 | False |
| individual-0050 | 0 | 5.7 | False |
| individual-0051 | 0 | 5.1 | False |
| individual-0052 | 0 | 5.2 | False |
| individual-0053 | 0 | 4.9 | False |
| individual-0054 | 0 | 4.7 | False |
| individual-0055 | 0 | 4.8 | False |
| individual-0056 | 0 | 4.9 | False |
| individual-0057 | 0 | 4.4 | False |
| individual-0058 | 1 | 10.6 | False |
| individual-0059 | 0 | 6.1 | False |
| individual-0060 | 0 | 7.5 | False |
| individual-0061 | 0 | 6.7 | False |
| individual-0062 | 0 | 5.8 | False |
| individual-0063 | 0 | 6.5 | False |
| individual-0064 | 0 | 10.5 | False |
| individual-0065 | 0 | 6.8 | False |
| individual-0066 | 0 | 5.7 | False |
| individual-0067 | 0 | 5.8 | False |
| individual-0068 | 0 | 10.1 | False |
| individual-0069 | 0 | 5.9 | False |
| individual-0070 | 0 | 5.5 | False |
| individual-0071 | 0 | 5.8 | False |
| individual-0072 | 0 | 5.7 | False |
| individual-0073 | 0 | 6.2 | False |
| individual-0074 | 0 | 5.6 | False |
| individual-0075 | 0 | 5.5 | False |
| individual-0076 | 0 | 5.3 | False |

## Failures (complete list in JSON)
| Test file | Test case | Type |
|---|---|---|
| test/data/epub_reader_preflight_test.dart | independent preflights cannot cancel each other | compile_or_runtime |
| test/features/book_source_search_widget_test.dart | EPUB search dialog has a bounded scrollable results viewport | runtime |
| test/features/book_source_search_widget_test.dart | EPUB source search navigates to silent caption source offset | runtime |
| test/features/book_source_search_widget_test.dart | EPUB search begins near reading position before wrapping | runtime |
| test/features/book_source_search_widget_test.dart | changing EPUB search query resets the result page | runtime |
| test/features/book_source_search_widget_test.dart | EPUB full-source search can open page three and return | runtime |
| test/features/book_source_search_widget_test.dart | closed search dialog never navigates or starts playback | runtime |

## Source locations of compilation/load errors (safe metadata)
| Test file | Source file | Line | Column |
|---|---|---:|---:|
| <full_suite> | lib/features/reader/reading_tools.dart | 115 | 16 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 23 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 23 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 25 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 55 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 55 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 56 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 84 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 84 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 85 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 119 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 119 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 120 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 149 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 149 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 150 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 177 | 18 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 177 | 5 |
| <full_suite> | test/features/book_source_search_widget_test.dart | 178 | 18 |
| test/features/book_source_search_widget_test.dart | lib/features/reader/reading_tools.dart | 115 | 16 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 23 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 23 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 25 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 55 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 55 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 56 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 84 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 84 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 85 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 119 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 119 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 120 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 149 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 149 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 150 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 177 | 18 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 177 | 5 |
| test/features/book_source_search_widget_test.dart | test/features/book_source_search_widget_test.dart | 178 | 18 |

## Files requiring Dart format (repository paths only)
- lib/audio/mp3_playback.dart
- lib/audio/narration_recovery_binding.dart
- lib/audio/openai_speech_engine.dart
- lib/audio/reader_lifecycle_policy.dart
- lib/audio/reader_media_handler.dart
- lib/audio/reader_player.dart
- lib/audio/secret_vault.dart
- lib/audio/sherpa_vits_engine.dart
- lib/audio/sherpa_vits_worker.dart
- lib/audio/speech_audio_cache.dart
- lib/audio/speech_engine_factory.dart
- lib/data/book_decoder.dart
- lib/data/epub_anchor_integrity.dart
- lib/data/epub_embedded_content.dart
- lib/data/epub_html_preprocess.dart
- lib/data/epub_import_diagnostics.dart
- lib/data/epub_inline_style.dart
- lib/data/epub_navigation.dart
- lib/data/epub_progress_recovery.dart
- lib/data/epub_reader_preflight.dart
- lib/data/epub_structural_markup.dart
- lib/data/epub_text_decoder.dart
- lib/data/epub_text_extractor.dart
- lib/data/library_store.dart
- lib/data/offline_voice_pack.dart
- lib/data/picked_book_import.dart
- lib/domain/alias_candidate.dart
- lib/domain/book.dart
- lib/domain/book_search.dart
- lib/domain/cast_merge.dart
- lib/domain/cast_span.dart
- lib/domain/character_candidate.dart
- lib/domain/cloud_speech_consent.dart
- lib/domain/dialogue_segmenter.dart
- lib/domain/dialogue_turn_inspector.dart
- lib/domain/dialogue_turn_review.dart
- lib/domain/epub_anchor_context.dart
- lib/domain/library_catalog.dart
- lib/domain/llm_analysis_consent.dart
- lib/domain/llm_cast_proposals.dart
- lib/domain/narrative_reference.dart
- lib/domain/pronunciation_rule.dart
- lib/domain/reading_anchor.dart
- lib/domain/speech_preferences.dart
- lib/domain/speech_segment.dart
- lib/domain/voice_cast.dart
- lib/features/library/library_screen.dart
- lib/features/reader/cast_merge_screen.dart
- lib/features/reader/dialogue_analysis_screen.dart
- lib/features/reader/dialogue_turn_review_screen.dart
- lib/features/reader/epub_chapter_navigation.dart
- lib/features/reader/epub_frame_sampler.dart
- lib/features/reader/epub_link_history.dart
- lib/features/reader/epub_note_preview_sheet.dart
- lib/features/reader/epub_opening_performance_sheet.dart
- lib/features/reader/epub_paragraph_tile.dart
- lib/features/reader/epub_progressive_layout.dart
- lib/features/reader/epub_visual_layout.dart
- lib/features/reader/pronunciation_screen.dart
- lib/features/reader/reader_screen.dart
- lib/features/reader/reading_tools.dart
- lib/features/reader/speech_provider_screen.dart
- lib/features/reader/voice_cast_screen.dart
- lib/llm/conversation_speaker_inspector.dart
- lib/llm/dialogue_analysis_plan.dart
- lib/llm/historical_character_concordance.dart
- lib/llm/historical_character_mention.dart
- lib/llm/narrative_antecedent_finder.dart
- lib/llm/openai_alias_reconciler.dart
- lib/llm/openai_character_discoverer.dart
- lib/llm/openai_dialogue_analyzer.dart
- lib/llm/openai_reference_resolver.dart
- lib/main.dart
- test/audio/cloud_prefetch_test.dart
- test/audio/mp3_preload_test.dart
- test/audio/narration_recovery_binding_test.dart
- test/audio/native_stop_timeout_test.dart
- test/audio/openai_speech_engine_test.dart
- test/audio/rapid_playback_navigation_test.dart
- test/audio/reader_lifecycle_policy_test.dart
- test/audio/reader_media_handler_test.dart
- test/audio/reader_player_test.dart
- test/audio/sherpa_vits_engine_test.dart
- test/audio/sherpa_vits_factory_gate_test.dart
- test/audio/sherpa_vits_worker_test.dart
- test/audio/sleep_timer_test.dart
- test/audio/speech_audio_cache_test.dart
- test/config/android_manifest_bootstrap_test.dart
- test/config/offline_voice_pack_structure_test.dart
- test/data/book_decoder_test.dart
- test/data/cast_merge_test.dart
- test/data/dialogue_turn_review_store_test.dart
- test/data/epub_anchor_integrity_test.dart
- test/data/epub_bounded_file_test.dart
- test/data/epub_embedded_content_test.dart
- test/data/epub_encoding_integration_test.dart
- test/data/epub_import_diagnostics_test.dart
- test/data/epub_inline_style_test.dart
- test/data/epub_legacy_notes_test.dart
- test/data/epub_navigation_test.dart
- test/data/epub_progress_recovery_test.dart
- test/data/epub_reader_preflight_test.dart
- test/data/epub_text_decoder_test.dart
- test/data/epub_text_extractor_test.dart
- test/data/library_store_test.dart
- test/data/narration_crash_recovery_test.dart
- test/data/narrative_reference_test.dart
- test/data/offline_voice_pack_test.dart
- test/data/pdf_visual_resume_test.dart
- test/data/picked_book_import_test.dart
- test/data/reading_anchor_test.dart
- test/data/recent_book_resume_test.dart
- test/domain/alias_candidate_test.dart
- test/domain/book_search_test.dart
- test/domain/cast_span_test.dart
- test/domain/character_candidate_test.dart
- test/domain/cloud_speech_consent_test.dart
- test/domain/cross_chunk_cast_test.dart
- test/domain/dialogue_segmenter_test.dart
- test/domain/dialogue_turn_inspector_test.dart
- test/domain/dialogue_turn_review_test.dart
- test/domain/epub_anchor_context_test.dart
- test/domain/library_catalog_test.dart
- test/domain/llm_cast_proposals_test.dart
- test/domain/pronunciation_rule_test.dart
- test/domain/speech_preferences_test.dart
- test/domain/speech_segment_test.dart
- test/domain/voice_cast_test.dart
- test/features/book_source_search_widget_test.dart
- test/features/epub_chapter_navigation_test.dart
- test/features/epub_diagnostics_sheet_test.dart
- test/features/epub_frame_sampler_test.dart
- test/features/epub_link_history_test.dart
- test/features/epub_note_preview_sheet_test.dart
- test/features/epub_opening_performance_sheet_test.dart
- test/features/epub_paragraph_tile_test.dart
- test/features/epub_progressive_layout_test.dart
- test/features/epub_visual_layout_test.dart
- test/features/library_catalog_widget_test.dart
- test/llm/conversation_speaker_inspector_test.dart
- test/llm/dialogue_analysis_plan_test.dart
- test/llm/historical_character_concordance_test.dart
- test/llm/narrative_antecedent_finder_test.dart
- test/llm/openai_alias_reconciler_test.dart
- test/llm/openai_character_discoverer_test.dart
- test/llm/openai_dialogue_analyzer_test.dart
- test/llm/openai_reference_resolver_test.dart

## Analyzer diagnostics
- warning - Unnecessary cast. Try removing the cast - lib/audio/openai_speech_engine.dart:296:20 - unnecessary_cast
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib/audio/reader_media_handler.dart:142:34 - unnecessary_non_null_assertion
- warning - Unused import: 'dart:convert'. Try removing the import directive - lib/data/epub_text_extractor.dart:1:8 - unused_import
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib/data/epub_text_extractor.dart:525:35 - unnecessary_non_null_assertion
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib/data/epub_text_extractor.dart:527:55 - unnecessary_non_null_assertion
- warning - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator - lib/domain/dialogue_segmenter.dart:150:29 - unnecessary_non_null_assertion
- warning - Unused import: '../../domain/voice_cast.dart'. Try removing the import directive - lib/features/reader/reader_screen.dart:28:8 - unused_import
- warning - Unused import: 'dart:convert'. Try removing the import directive - test/data/epub_legacy_notes_test.dart:1:8 - unused_import
- warning - Unused import: 'package:ereader/domain/book.dart'. Try removing the import directive - test/llm/historical_character_concordance_test.dart:6:8 - unused_import
- warning - Unused import: 'package:ereader/domain/cast_span.dart'. Try removing the import directive - test/llm/openai_reference_resolver_test.dart:4:8 - unused_import
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
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._requestFocus') to initialize the field - lib/audio/reader_media_handler.dart:20:8 - prefer_initializing_formal
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/audio/reader_media_handler.dart:181:34 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/audio/reader_media_handler.dart:198:61 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/audio/reader_media_handler.dart:201:63 - curly_braces_in_flow_control_structures
-    info - Unnecessary use of multiple underscores. Try using '_' - lib/audio/reader_media_handler.dart:214:62 - unnecessary_underscores
-    info - Unnecessary use of multiple underscores. Try using '_' - lib/audio/reader_media_handler.dart:266:56 - unnecessary_underscores
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._engine') to initialize the field - lib/audio/reader_player.dart:42:8 - prefer_initializing_formals
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._segments') to initialize the field - lib/audio/reader_player.dart:43:8 - prefer_initializing_formals
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/reader_player.dart:205:9 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/secret_vault.dart:20:12 - prefer_interpolation_to_compose_strings
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._synthesizer') to initialize the field - lib/audio/sherpa_vits_engine.dart:94:9 - prefer_initializing_formals
-    info - Use an initializing formal to assign a parameter to a field. Try using an initialing formal ('this._root') to initialize the field - lib/audio/speech_audio_cache.dart:30:46 - prefer_initializing_formals
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/speech_audio_cache.dart:58:34 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/speech_audio_cache.dart:88:7 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/speech_audio_cache.dart:88:25 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/audio/speech_engine_factory.dart:61:11 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_embedded_content.dart:68:45 - curly_braces_in_flow_control_structures
-    info - Statements in a while should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_embedded_content.dart:78:62 - curly_braces_in_flow_control_structures
-    info - Angle brackets will be interpreted as HTML. Try using backticks around the content with angle brackets, or try replacing `<` with `&lt;` and `>` with `&gt;` - lib/data/epub_html_preprocess.dart:3:5 - unintended
-    info - Angle brackets will be interpreted as HTML. Try using backticks around the content with angle brackets, or try replacing `<` with `&lt;` and `>` with `&gt;` - lib/data/epub_html_preprocess.dart:3:28 - unintende
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_navigation.dart:69:35 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_navigation.dart:124:37 - curly_braces_in_flow_control_structures
-    info - Use the null-aware marker '?' rather than a null check via an 'if'. Try using '?' - lib/data/epub_reader_preflight.dart:67:5 - use_null_aware_elements
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_structural_markup.dart:98:63 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_structural_markup.dart:123:25 - curly_braces_in_flow_control_structures
-    info - Use 'isEmpty' instead of 'length' to test whether the collection is empty. Try rewriting the expression to use 'isEmpty' - lib/data/epub_text_extractor.dart:91:9 - prefer_is_empty
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_text_extractor.dart:171:39 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/data/epub_text_extractor.dart:213:31 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_text_extractor.dart:327:33 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/epub_text_extractor.dart:381:47 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/data/epub_text_extractor.dart:596:46 - prefer_interpolation_to_compose_strings
-    info - 'dispose' is deprecated and shouldn't be used. Call close() instead. Try replacing the use of the deprecated member with the replacement - lib/data/library_store.dart:404:10 - deprecated_member_use
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/library_store.dart:462:46 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/library_store.dart:475:45 - curly_braces_in_flow_control_structures
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/data/library_store.dart:545:32 - prefer_interpolation_to_compose_strings
-    info - Use interpolation to compose strings and values. Try using string interpolation to build the composite string - lib/data/library_store.dart:549:28 - prefer_interpolation_to_compose_strings
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/data/library_store.dart:979:68 - curly_braces_in_flow_control_structures
-    info - 'dispose' is deprecated and shouldn't be used. Call close() instead. Try replacing the use of the deprecated member with the replacement - lib/data/library_store.dart:1981:10 - deprecated_member_use
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/book_search.dart:90:61 - curly_braces_in_flow_control_structures
-    info - Statements in an if should be enclosed in a block. Try wrapping the statement in a block - lib/domain/book_search.dart:93:59 - curly_braces_in_flow_control_structures
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

Raw stdout/stderr logs are saved locally and are never committed.