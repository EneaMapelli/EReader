import 'package:flutter/material.dart';

/// One-tap return to the CURRENT speech cursor after reading elsewhere.
/// Never starts, pauses or seeks playback itself.
class ReaderReturnToNarrationButton extends StatelessWidget {
  const ReaderReturnToNarrationButton({
    super.key,
    required this.onReturn,
  });

  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) => FloatingActionButton.small(
        key: const ValueKey('reader-return-to-narration'),
        heroTag: 'reader-return-to-narration-fab',
        tooltip: 'Return to narrated passage',
        onPressed: onReturn,
        child: const Icon(Icons.my_location),
      );
}
