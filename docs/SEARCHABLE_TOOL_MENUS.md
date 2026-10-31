# Searchable reader and library tool menus — 2026-10-31

## User-visible behavior

- Both the book reader and library use the same categorized action sheet.
- When a menu contains at least eight actions, a compact Find a tool field appears below its title. Smaller menus keep their previous compact presentation **when opened by touch**. Ctrl/Cmd+K always opens the searchable reader palette, including shorter visual PDF menus.
- Matching is local, instant, case-insensitive and accepts multiple words. Each word may match the group name, action label or descriptive subtitle.
- Groups with no matched commands disappear. A live count announces nonempty filtered matches to screen readers; section labels are semantics headings. An empty result has a clear explanation and the search can be reset with one tap.
- Searching never invokes an action: the existing ID is returned only after tapping an enabled action. Disabled commands remain disabled and the selected marker is retained.
- The search field does not autofocus when opened from a toolbar (the Android keyboard does not cover the menu on opening); **Ctrl/Cmd+K** opens it focused for immediate keyboard input. The sheet uses keyboard insets and a bounded scrollable action list.
- No book file, source anchor, TTS state, consent, SQLite data, network request, or cloud key is modified.

## Source and tests

- lib/features/shared/organized_action_sheet.dart contains the pure filtering function and keyboard-aware search presentation.
- test/features/organized_action_sheet_search_test.dart verifies multi-word and case-insensitive matching, original object/state retention, disabled actions, reset, live result count, keyboard autofocus and compact-menu fallback, including short PDF-like palettes.
- Existing test/features/organized_action_sheet_widget_test.dart and reader menu/library catalog tests remain regression gates.

## Verification status / manual acceptance

Code and test cases have been committed on feature/m0-flutter-foundation; **no Dart/Flutter SDK or native Windows/Android runtime is available here, so these cases have not been executed**.

Before promotion:
1. Run the existing local Flutter analyzer and tests (including both organized-action-sheet test files), recording actual failures.
2. On Android, open the larger Reader and Library tool menus; type a search, dismiss the keyboard, clear the query and select a filtered action.
3. Check a small popup, a narrow phone with the virtual keyboard and Windows desktop keyboard navigation/screen-reader labels, including live result count/heading semantics and Ctrl+K immediate typing.
4. Confirm selecting a disabled action is impossible and that filtering does not accidentally trigger speech or a network operation.

This is a UI increment; it does not change the qualitative milestone percentage or complete the native verification gates.
