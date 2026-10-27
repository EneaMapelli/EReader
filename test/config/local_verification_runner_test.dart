import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source checks only; Windows PowerShell must be executed on the user's PC.
/// Avoid accidentally converting the local-only test command into a
/// publishing or app-building workflow.
void main() {
  test('local suite explicitly disables report publication', () async {
    final runner = await File('tool/verify-local.ps1').readAsString();
    expect(runner, contains("'run-all-tests.ps1'),'-NoPublish'"));
    expect(runner, contains("'tool/offline_vits_soak_test.dart'"));
    expect(runner, contains("'run-example-corpus.ps1'"));
    expect(runner, contains("'run-offline-voice-qualification.ps1'"));
    expect(runner, contains('if ($NativeVoiceSourceFolder -and '
        '-not $AcceptNativeRisk)'));
    expect(runner, contains("publication='disabled'"));
    expect(runner, contains("windowsBuild='not-executed'"));
    expect(runner, contains("githubActions='not-triggered'"));
    expect(runner, isNot(contains("'flutter','build'")));
    expect(runner, isNot(contains("'build','windows'")));
    expect(runner, isNot(contains('gh workflow run')));
    expect(runner, isNot(contains('git push origin')));
    expect(runner, isNot(contains('git add --')));
    expect(runner, isNot(contains("'PublishSummary'")));
  });

  test('full-suite raw output stays ignored and manual guide exists',
      () async {
    final runner = await File('tool/verify-local.ps1').readAsString();
    final ignore = await File('.gitignore').readAsString();
    final guide =
        await File('docs/LOCAL_VERIFICATION_GUIDE.md').readAsString();

    expect(runner, contains('.local-test-results'));
    expect(runner, contains("'.stdout.log'"));
    expect(runner, contains("'.stderr.log'"));
    expect(ignore, contains('.local-test-results/'));
    expect(guide, contains('-NoPublish'));
    expect(guide, contains('-SoakIterations 500'));
    expect(guide, contains('-IncludeCorpus -DeepCorpus'));
    expect(guide, contains('-AcceptNativeRisk'));
    expect(guide, contains('NON aggiungere -PublishSummary'));
  });
}
