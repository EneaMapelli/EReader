import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// One strictly relative phonemizer file. Directories/ZIP extraction are
/// never trusted: each allowed asset is copied independently and hashed.
class OfflineVoiceResource {
  const OfflineVoiceResource({required this.relativePath, required this.sha256});
  final String relativePath;
  final String sha256;
}

/// Describes a VITS/Piper model explicitly approved by the user.
///
/// Hashes are a *consistency check against the supplied manifest*, not proof
/// that a model comes from a trusted publisher. Licensing is never inferred
/// from a filename and there is no automatic network/model download.
class OfflineVoicePackManifest {
  const OfflineVoicePackManifest({
    required this.id,
    required this.displayName,
    required this.locale,
    required this.licenseId,
    required this.modelSha256,
    required this.tokensSha256,
    this.phonemizerResources = const [],
  });

  final String id;
  final String displayName;
  final String locale;
  final String licenseId;
  final String modelSha256;
  final String tokensSha256;
  final List<OfflineVoiceResource> phonemizerResources;

  /// Persist only explicit configuration and expected checksums, never the
  /// source file paths, book content or API keys.
  Map<String, Object> toJson() => {
    'version': 1,
    'id': id,
    'displayName': displayName,
    'locale': locale,
    'licenseId': licenseId,
    'modelSha256': modelSha256,
    'tokensSha256': tokensSha256,
    'phonemizerResources': [
      for (final file in phonemizerResources)
        {'relativePath': file.relativePath, 'sha256': file.sha256},
    ],
  };

  factory OfflineVoicePackManifest.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['phonemizerResources'] is! List) {
      throw const FormatException('Unsupported offline voice manifest');
    }
    final resources = <OfflineVoiceResource>[];
    for (final entry in json['phonemizerResources'] as List) {
      if (entry is! Map || entry['relativePath'] is! String ||
          entry['sha256'] is! String) {
        throw const FormatException('Invalid phonemizer manifest entry');
      }
      resources.add(OfflineVoiceResource(
        relativePath: entry['relativePath'] as String,
        sha256: entry['sha256'] as String,
      ));
    }
    final metadata = OfflineVoicePackManifest(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      locale: json['locale'] as String,
      licenseId: json['licenseId'] as String,
      modelSha256: json['modelSha256'] as String,
      tokensSha256: json['tokensSha256'] as String,
      phonemizerResources: resources,
    );
    metadata.validate();
    return metadata;
  }

  void validate() {
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$').hasMatch(id)) {
      throw const FormatException('Invalid offline voice pack ID');
    }
    if (displayName.trim().isEmpty || displayName.length > 120) {
      throw const FormatException('Invalid offline voice pack display name');
    }
    if (!RegExp(r'^[a-zA-Z]{2,8}([-_][a-zA-Z0-9]{2,8})?$')
        .hasMatch(locale)) {
      throw const FormatException('Invalid offline voice locale');
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9.()+-]{0,79}$')
        .hasMatch(licenseId)) {
      throw const FormatException('Explicit model license identifier required');
    }
    final digest = RegExp(r'^[a-f0-9]{64}$');
    if (!digest.hasMatch(modelSha256) || !digest.hasMatch(tokensSha256)) {
      throw const FormatException('Expected lowercase SHA-256 file digests');
    }
    if (phonemizerResources.length > 2048) {
      throw const FormatException('Excessive offline phonemizer file count');
    }
    final names = <String>{};
    // Windows reserved device basenames must not be created as files.
    final reserved = RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
      caseSensitive: false,
    );
    for (final asset in phonemizerResources) {
      final name = asset.relativePath;
      final parts = name.split('/');
      if (name.length > 180 || parts.length < 2 ||
          parts.first != 'espeak-ng-data' ||
          parts.any((part) => part.isEmpty || part == '.' ||
              part == '..' || part.endsWith('.') ||
              reserved.hasMatch(part) || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(part)) ||
          !names.add(name.toLowerCase()) || !digest.hasMatch(asset.sha256)) {
        throw const FormatException('Unsafe offline phonemizer manifest entry');
      }
    }
  }
}

class InstalledOfflineVoicePack {
  const InstalledOfflineVoicePack({
    required this.manifest,
    required this.modelPath,
    required this.tokensPath,
  });

  final OfflineVoicePackManifest manifest;
  final String modelPath;
  final String tokensPath;

  /// Only explicit SHA-verified resources live under this phonemizer tree.
  /// An empty manifest means the runtime must not assume eSpeak is present.
  String? get phonemizerDataDir => manifest.phonemizerResources.isEmpty
      ? null : p.join(p.dirname(modelPath), 'espeak-ng-data');
}

Future<int> _copyVerifiedFile(
  File source,
  File destination, {
  required String expectedDigest,
  required int maxBytes,
}) async {
  // Reject symbolic links: installing a pack must not follow an unexpected
  // external file, even if a previous path check succeeded.
  if (await FileSystemEntity.type(source.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('Offline voice source is not a regular file');
  }
  final length = await source.length();
  if (length < 1 || length > maxBytes) {
    throw const FormatException('Offline voice file exceeds size budget');
  }

  Digest? digest;
  final digestSink = ChunkedConversionSink<Digest>.withCallback((digests) {
    if (digests.length != 1) {
      throw const FormatException('Invalid SHA-256 digest stream');
    }
    digest = digests.single;
  });
  final hashInput = sha256.startChunkedConversion(digestSink);
  final out = destination.openWrite();
  var written = 0;
  try {
    await for (final part in source.openRead()) {
      if (part.length > maxBytes - written) {
        throw const FormatException('Offline voice file grew beyond budget');
      }
      hashInput.add(part);
      out.add(part);
      written += part.length;
    }
    hashInput.close();
    await out.flush();
    await out.close();
    if (written < 1 || digest.toString() != expectedDigest) {
      throw const FormatException('Offline voice SHA-256 mismatch');
    }
    return written;
  } catch (_) {
    await out.close();
    rethrow;
  }
}

/// Stages the two required VITS model files and any explicitly listed,
/// SHA-verified phonemizer files. The native sherpa runtime is NOT started
/// here and the model is NOT shown as a selectable TTS provider.
///
/// Installation is all-or-nothing inside [modelsDirectory]: no unverified
/// files survive failure. A previously installed voice is reverified instead
/// of silently overwritten. Each asset is copied and hashed as a stream,
/// never loaded as a giant in-memory byte array.
Future<InstalledOfflineVoicePack> installOfflineVoicePack({
  required OfflineVoicePackManifest manifest,
  required Directory sourceDirectory,
  required Directory modelsDirectory,
  int maxModelBytes = 600 * 1024 * 1024,
  int maxTokensBytes = 4 * 1024 * 1024,
  int maxPhonemizerBytes = 64 * 1024 * 1024,
}) async {
  manifest.validate();
  if (maxModelBytes < 1 || maxModelBytes > 600 * 1024 * 1024 ||
      maxTokensBytes < 1 || maxTokensBytes > 4 * 1024 * 1024 ||
      maxPhonemizerBytes < 1 ||
      maxPhonemizerBytes > 64 * 1024 * 1024) {
    throw const FormatException('Invalid offline model byte budgets');
  }
  await modelsDirectory.create(recursive: true);
  final target = Directory(p.join(modelsDirectory.path, manifest.id));

  Future<void> copyPhonemizerResources(Directory from, Directory to) async {
    var totalBytes = 0;
    for (final resource in manifest.phonemizerResources) {
      final parts = resource.relativePath.split('/');
      var parent = from.path;
      // Refuse symlinked parents, not just symlinked regular files.
      for (final folder in parts.take(parts.length - 1)) {
        parent = p.join(parent, folder);
        if (await FileSystemEntity.type(parent, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw const FormatException('Invalid phonemizer source directory');
        }
      }
      final source = File(p.joinAll([from.path, ...parts]));
      final destination = File(p.joinAll([to.path, ...parts]));
      await destination.parent.create(recursive: true);
      final remaining = maxPhonemizerBytes - totalBytes;
      if (remaining < 1) {
        throw const FormatException('Offline phonemizer budget exhausted');
      }
      totalBytes += await _copyVerifiedFile(
        source, destination,
        expectedDigest: resource.sha256,
        maxBytes: remaining < 8 * 1024 * 1024
            ? remaining : 8 * 1024 * 1024,
      );
    }
  }

  Future<InstalledOfflineVoicePack> verify(Directory where) async {
    // Reuse the same size/hash checks on installed files. The recheck uses a
    // private ephemeral verification directory and does not alter the pack.
    if (await FileSystemEntity.type(where.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('Offline voice pack directory is unsafe');
    }
    final verifyDir = await modelsDirectory.createTemp('.check-');
    try {
      await _copyVerifiedFile(
        File(p.join(where.path, 'model.onnx')),
        File(p.join(verifyDir.path, 'model.onnx')),
        expectedDigest: manifest.modelSha256,
        maxBytes: maxModelBytes,
      );
      await _copyVerifiedFile(
        File(p.join(where.path, 'tokens.txt')),
        File(p.join(verifyDir.path, 'tokens.txt')),
        expectedDigest: manifest.tokensSha256,
        maxBytes: maxTokensBytes,
      );
      await copyPhonemizerResources(where, verifyDir);
      return InstalledOfflineVoicePack(
        manifest: manifest,
        modelPath: p.join(where.path, 'model.onnx'),
        tokensPath: p.join(where.path, 'tokens.txt'),
      );
    } finally {
      if (await verifyDir.exists()) {
        await verifyDir.delete(recursive: true);
      }
    }
  }

  if (await FileSystemEntity.type(target.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return verify(target);
  }
  final temporary = await modelsDirectory.createTemp('.install-');
  try {
    await _copyVerifiedFile(
      File(p.join(sourceDirectory.path, 'model.onnx')),
      File(p.join(temporary.path, 'model.onnx')),
      expectedDigest: manifest.modelSha256,
      maxBytes: maxModelBytes,
    );
    await _copyVerifiedFile(
      File(p.join(sourceDirectory.path, 'tokens.txt')),
      File(p.join(temporary.path, 'tokens.txt')),
      expectedDigest: manifest.tokensSha256,
      maxBytes: maxTokensBytes,
    );
    await copyPhonemizerResources(sourceDirectory, temporary);
    // Atomic within the same models directory. Do not replace a previously
    // installed model even if another installation raced this operation.
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return verify(target);
    }
    await temporary.rename(target.path);
    return InstalledOfflineVoicePack(
      manifest: manifest,
      modelPath: p.join(target.path, 'model.onnx'),
      tokensPath: p.join(target.path, 'tokens.txt'),
    );
  } finally {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}
