import 'dart:async';
import 'dart:io';

/// Short, user-facing summaries of offline voice operations. No raw
/// exceptions, absolute filesystem paths, archive URLs, model contents,
/// credentials or book passages are ever forwarded to the UI.
enum OfflineVoiceOperation { inspectFolder, installFolder, installPaola, remove }

enum OfflineVoiceFailureKind {
  integrity,
  incomplete,
  invalidMetadata,
  unsafeFiles,
  sizeLimit,
  conflict,
  download,
  extraction,
  noSpace,
  accessDenied,
  lockedFiles,
  unsupported,
  io,
  unexpected,
}

class OfflineVoiceFailure {
  const OfflineVoiceFailure({
    required this.kind,
    required this.summary,
    required this.nextStep,
  });

  final OfflineVoiceFailureKind kind;
  final String summary;
  final String nextStep;

  String get message => '$summary $nextStep';
}

/// Translate ONLY known internal errors into stable actions. Never append
/// error.toString(), OS messages, model identifiers or file paths. A generic
/// fallback is used for unknown exceptions, including ones carrying
/// untrusted user-supplied strings.
OfflineVoiceFailure diagnoseOfflineVoiceFailure(
  Object error, {
  required OfflineVoiceOperation operation,
}) {
  final action = switch (operation) {
    OfflineVoiceOperation.inspectFolder =>
      'Cannot inspect this voice folder.',
    OfflineVoiceOperation.installFolder =>
      'Voice installation rejected.',
    OfflineVoiceOperation.installPaola =>
      'Paola could not be installed.',
    OfflineVoiceOperation.remove =>
      'Unable to remove the voice.',
  };

  OfflineVoiceFailure identified(
      OfflineVoiceFailureKind kind, String explanation, String nextStep) =>
      OfflineVoiceFailure(
        kind: kind,
        summary: '$action $explanation',
        nextStep: nextStep,
      );

  if (error is FormatException) {
    final message = error.message;
    if (message == 'Offline voice SHA-256 mismatch' ||
        message == 'Piper archive checksum mismatch' ||
        message == 'Voice manifest changed after approval' ||
        message == 'Installed voice manifest does not match' ||
        message == 'Offline voice metadata changed') {
      return identified(
        OfflineVoiceFailureKind.integrity,
        'The selected voice files do not match the expected checksums or metadata.',
        'Verify the original source and expected hashes before retrying.',
      );
    }
    if (message == 'Piper archive is missing model assets' ||
        message == 'Piper phonemizer assets missing' ||
        message == 'Missing files in offline voice pack' ||
        message == 'Missing verified voice pack manifest' ||
        message == 'Offline voice source is not a regular file' ||
        message == 'Downloaded voice archive is incomplete' ||
        message == 'Offline voice pack is not installed') {
      return identified(
        OfflineVoiceFailureKind.incomplete,
        'One or more required model files are missing or incomplete.',
        'Choose a complete, supported voice package and try again.',
      );
    }
    if (message == 'Windows tar could not unpack Piper voice') {
      return identified(
        OfflineVoiceFailureKind.extraction,
        'Windows could not extract the verified model archive.',
        'Check that tar.exe works and that temporary disk space is available.',
      );
    }
    if (message == 'Piper download unavailable or unsafe') {
      return identified(
        OfflineVoiceFailureKind.download,
        'The approved model download was unavailable or rejected.',
        'Check the network and retry later; no unverified model was enabled.',
      );
    }
    if (message == 'Voice download exceeds size limit' ||
        message == 'Invalid Piper model archive size' ||
        message == 'Excessive Piper phonemizer resources' ||
        message == 'Offline voice file exceeds size budget' ||
        message == 'Offline voice file grew beyond budget' ||
        message == 'Offline voice source exceeds size limit' ||
        message == 'Offline phonemizer size limit exceeded' ||
        message == 'Offline phonemizer budget exhausted' ||
        message == 'Excessive offline phonemizer file count' ||
        message == 'Offline voice manifest too large') {
      return identified(
        OfflineVoiceFailureKind.sizeLimit,
        'The package exceeds the supported file-size or resource limits.',
        'Use a smaller compatible model; do not bypass the integrity limits.',
      );
    }
    if (message == 'Offline voice contains unsafe files' ||
        message == 'Voice archive contains a link' ||
        message == 'Unsafe or unsupported phonemizer path' ||
        message == 'Unsafe offline phonemizer manifest entry' ||
        message == 'Offline voice contains an unsafe link' ||
        message == 'Unexpected file in offline voice pack' ||
        message == 'Invalid phonemizer source directory' ||
        message == 'Unsafe phonemizer subdirectory' ||
        message == 'Offline voice pack directory is unsafe') {
      return identified(
        OfflineVoiceFailureKind.unsafeFiles,
        'The package has unsafe or unexpected files or links.',
        'Inspect the source package; EReader will not follow unsafe paths.',
      );
    }
    if (message == 'Voice pack identity changed' ||
        message == 'Offline model asset changed after verification') {
      return identified(
        OfflineVoiceFailureKind.conflict,
        'The installed model changed during verification.',
        'Recheck the local model before trying the operation again.',
      );
    }
    return identified(
      OfflineVoiceFailureKind.invalidMetadata,
      'The voice manifest or package metadata could not be validated.',
      'Check the package format, language, license and required filenames.',
    );
  }

  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    if (code == 28 || code == 112) {
      return identified(
        OfflineVoiceFailureKind.noSpace,
        'The device appears to have insufficient free disk space.',
        'Free space on the model volume and retry.',
      );
    }
    if (code == 13 || code == 5) {
      return identified(
        OfflineVoiceFailureKind.accessDenied,
        'The operating system denied access to a model file.',
        'Check folder permissions and retry with a writable app location.',
      );
    }
    if (code == 32 || code == 33) {
      return identified(
        OfflineVoiceFailureKind.lockedFiles,
        'A model file appears to be open in another process.',
        'Close other readers or previews and retry after audio stops.',
      );
    }
    return identified(
      OfflineVoiceFailureKind.io,
      'A local file operation did not complete.',
      'Check available disk space, file access and whether the model is in use.',
    );
  }

  if (error is SocketException ||
      error is HttpException ||
      error is HandshakeException ||
      error is TimeoutException) {
    return identified(
      OfflineVoiceFailureKind.download,
      'The connection or request failed.',
      'Check the network and retry; no model was activated.',
    );
  }
  if (error is ProcessException &&
      operation == OfflineVoiceOperation.installPaola) {
    return identified(
      OfflineVoiceFailureKind.extraction,
      'The Windows archive extractor could not start.',
      'Verify tar.exe is available and try again.',
    );
  }
  if (error is UnsupportedError) {
    return identified(
      OfflineVoiceFailureKind.unsupported,
      'This model operation is not supported on this device.',
      'Use the supported desktop import flow.',
    );
  }

  return identified(
    OfflineVoiceFailureKind.unexpected,
    'The operation did not complete.',
    'Check the local model and try again. No automatic cloud fallback was used.',
  );
}
