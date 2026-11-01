import 'package:ereader/features/reader/reader_return_to_narration_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('return button is accessible and does not control playback',
      (tester) async {
    var returns = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        floatingActionButton: ReaderReturnToNarrationButton(
          onReturn: () => returns++,
        ),
      ),
    ));
    final returnButton =
        find.byKey(const ValueKey('reader-return-to-narration'));
    expect(returnButton, findsOneWidget);
    final button = tester.widget<FloatingActionButton>(returnButton);
    expect(button.tooltip, 'Return to narrated passage');
    expect(returns, 0);
    await tester.tap(returnButton);
    await tester.pump();
    expect(returns, 1);
    expect(tester.takeException(), isNull);
  });
}
