import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'offline_voice_pack.dart';

/// Curated, converted sherpa-onnx VITS voice. NEVER download before
/// explicit user consent. This pinned archive includes the pre-converted
/// Paola ONNX, tokens.txt and complete eSpeak-NG phonemizer data.
///
/// Source and published SHA-256:
/// https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models
/// sha256 digest obtained from GitHub's release asset metadata.
/// The underlying Piper voice is also hosted by rhasspy/piper-voices.
/// Publisher/model/data licensing still requires user review.
class PiperPaolaCatalog {
  static const id = 'piper-paola-it-medium';
  static const name = 'Paola (italiano, qualità media)';
  static const locale = 'it-IT';
  static const archiveName = 'vits-piper-it_IT-paola-medium.tar.bz2';
  static const archiveUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      'vits-piper-it_IT-paola-medium.tar.bz2';
  static const sha256Digest =
      '7541f75778afa164e44e34baaef63befad7698595df26a95ca944b63ef1a16b4';
  static const maxDownloadBytes = 85 * 1024 * 1024;
  static const maxPhonemizerFiles = 2048;
  static const maxPhonemizerBytes = 64 * 1024 * 1024;

  /// Kept separate for pure unit tests; never provides unverified model
  /// bytes to the native engine.
  static bool verifyArchiveDigest(String digest) =>
      digest.toLowerCase() == sha256Digest;

  static bool allowedPhonemizerPath(String name) {
    if (!name.startsWith('espeak-ng-data/') || name.length > 180) {
      return false;
    }
    final elements = name.split('/');
    return elements.length >= 2 &&
        elements.every((part) =>
            part.isNotEmpty && part != '.' && part != '..' &&
            !part.endsWith('.') &&
            RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(part) &&
            !RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
                caseSensitive: false).hasMatch(part));
  }
}

/// Stream from one explicitly trusted release URL into private temporary
/// storage. Never buffers the 67MB model in app memory, saves API secrets,
/// or fetches arbitrary user-supplied URLs.
Future<void> downloadPiperPaolaArchive(
    File destination, {
    void Function(int bytes, int? total)? onProgress,
    HttpClient Function()? clientFactory,
}) async {
  final client = clientFactory?.call() ?? HttpClient();
  client.connectionTimeout = const Duration(seconds: 20);
  client.idleTimeout = const Duration(seconds: 30);
  client.maxConnectionsPerHost = 1;
  IOSink? sink;
  try {
    final request = await client.getUrl(Uri.parse(PiperPaolaCatalog.archiveUrl))
        .timeout(const Duration(seconds: 30));
    request.headers.set(HttpHeaders.userAgentHeader, 'EReader/0.1 voice-import');
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok ||
        response.redirects.length > 5 ||
        response.redirects.any((item) =>
            item.location.scheme != 'https')) {
      throw const FormatException('Piper download unavailable or unsafe');
    }
    final length = response.contentLength;
    if (length > PiperPaolaCatalog.maxDownloadBytes) {
      throw const FormatException('Voice download exceeds size limit');
    }
    var count = 0;
    sink = destination.openWrite();
    await for (final chunk in response.timeout(const Duration(seconds: 45))) {
      count += chunk.length;
      if (count > PiperPaolaCatalog.maxDownloadBytes) {
        throw const FormatException('Voice download exceeds size limit');
      }
      sink.add(chunk);
      onProgress?.call(count, length >= 0 ? length : null);
    }
    await sink.flush();
    await sink.close();
    sink = null;
    if (count < 1024 * 1024) {
      throw const FormatException('Downloaded voice archive is incomplete');
    }
  } finally {
    try { await sink?.close(); } catch (_) {}
    client.close(force: true);
  }
}

/// An independent file digest is checked before decompressing even one tar
/// member. This protects Windows tar from remote archive replacement.
Future<void> verifyPiperPaolaArchive(File file) async {
  final len = await file.length();
  if (len <= 1024 * 1024 ||
      len > PiperPaolaCatalog.maxDownloadBytes) {
    throw const FormatException('Invalid Piper model archive size');
  }
  final digest = (await sha256.bind(file.openRead()).first).toString();
  if (!PiperPaolaCatalog.verifyArchiveDigest(digest)) {
    throw const FormatException('Piper archive checksum mismatch');
  }
}

/// Returns the installed, hashed pack. Only Windows has the built-in
/// tar.exe required to extract this pinned bzip2 archive. Imported data
/// stays private and no application code/plugin executable is downloaded.
///
/// Extracting is permitted only AFTER the exact SHA-256 check. No shell is
/// invoked, all destination files are rechecked by OfflineVoicePackImporter,
/// and staging is deleted on success or failure.
Future<InstalledOfflineVoicePack> installCuratedPiperPaola({
  required Directory modelsDirectory,
  required Directory stagingParent,
  void Function(int bytes, int? total)? onProgress,
  Future<void> Function(File destination)? downloadOverride,
  Future<ProcessResult> Function(String executable, List<String> arguments)?
      extractOverride,
}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Automatic Piper installation requires Windows');
  }
  await modelsDirectory.create(recursive: true);
  final existing = Directory(p.join(modelsDirectory.path, PiperPaolaCatalog.id));
  if (await existing.exists()) {
    return loadInstalledOfflineVoicePack(
      packId: PiperPaolaCatalog.id, modelsDirectory: modelsDirectory,
    );
  }
  await stagingParent.create(recursive: true);
  final stage = await stagingParent.createTemp('.paola-install-');
  try {
    final archive = File(p.join(stage.path, PiperPaolaCatalog.archiveName));
    if (downloadOverride == null) {
      await downloadPiperPaolaArchive(archive, onProgress: onProgress);
    } else {
      await downloadOverride(archive);
    }
    await verifyPiperPaolaArchive(archive);

    final unpack = Directory(p.join(stage.path, 'unpacked'));
    await unpack.create();
    final args = ['-xjf', archive.path, '-C', unpack.path];
    final result = extractOverride == null
        ? await Process.run('tar.exe', args).timeout(const Duration(minutes: 4))
        : await extractOverride('tar.exe', args);
    if (result.exitCode != 0) {
      throw const FormatException('Windows tar could not unpack Piper voice');
    }
    final modelDir = Directory(p.join(unpack.path,
        'vits-piper-it_IT-paola-medium'));
    final model = File(p.join(modelDir.path, 'it_IT-paola-medium.onnx'));
    final tokens = File(p.join(modelDir.path, 'tokens.txt'));
    final espeak = Directory(p.join(modelDir.path, 'espeak-ng-data'));
    if (!await model.exists() || !await tokens.exists() ||
        !await espeak.exists()) {
      throw const FormatException('Piper archive is missing model assets');
    }
    final phonemizerResources = <OfflineVoiceResource>[];
    var phonemizerBytes = 0;
    await for (final entity in espeak.list(
        recursive: true, followLinks: false)) {
      final type = await FileSystemEntity.type(
          entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) continue;
      if (type != FileSystemEntityType.file) {
        throw const FormatException('Voice archive contains a link');
      }
      final name = p.relative(entity.path, from: modelDir.path)
          .replaceAll('\\', '/');
      if (!PiperPaolaCatalog.allowedPhonemizerPath(name)) {
        throw const FormatException('Unsafe or unsupported phonemizer path');
      }
      final len = await File(entity.path).length();
      phonemizerBytes += len;
      if (len <= 0 || len > 8 * 1024 * 1024 ||
          phonemizerBytes > PiperPaolaCatalog.maxPhonemizerBytes ||
          phonemizerResources.length >= PiperPaolaCatalog.maxPhonemizerFiles) {
        throw const FormatException('Excessive Piper phonemizer resources');
      }
      final digest = (await sha256.bind(File(entity.path).openRead()).first)
          .toString();
      phonemizerResources.add(
          OfflineVoiceResource(relativePath: name, sha256: digest));
    }
    phonemizerResources.sort(
        (a, b) => a.relativePath.compareTo(b.relativePath));
    if (phonemizerResources.isEmpty) {
      throw const FormatException('Piper phonemizer assets missing');
    }

    // Install the same vetted converted archive via the pre-existing,
    // atomic and bounded voice-pack importer. No external code is executed.
    final prepared = Directory(p.join(stage.path, 'prepared'));
    await prepared.create();
    await model.copy(p.join(prepared.path, 'model.onnx'));
    await tokens.copy(p.join(prepared.path, 'tokens.txt'));
    // Avoid copying the phonemizer tree twice before installation.
    await espeak.rename(p.join(prepared.path, 'espeak-ng-data'));
    final manifest = OfflineVoicePackManifest(
      id: PiperPaolaCatalog.id,
      displayName: PiperPaolaCatalog.name,
      locale: PiperPaolaCatalog.locale,
      // rhasspy/piper-voices model repository: MIT.
      // Voice dataset separately declares CC0; users review both.
      licenseId: 'MIT',
      modelSha256: (await sha256.bind(
          File(p.join(prepared.path, 'model.onnx')).openRead()).first)
          .toString(),
      tokensSha256: (await sha256.bind(
          File(p.join(prepared.path, 'tokens.txt')).openRead()).first)
          .toString(),
      phonemizerResources: phonemizerResources,
    );
    manifest.validate();
    return installOfflineVoicePack(
        manifest: manifest,
        sourceDirectory: prepared,
        modelsDirectory: modelsDirectory);
  } finally {
    try {
      if (await stage.exists()) await stage.delete(recursive: true);
    } on FileSystemException {
      // A locked file is never left in user-supplied paths.
    }
  }
}
