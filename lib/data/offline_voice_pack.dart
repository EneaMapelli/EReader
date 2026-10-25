import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

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
  });

  final String id;
  final String displayName;
  final String locale;
  final String licenseId;
  final String modelSha256;
  final String tokensSha256;

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
}

Future<void> _copyVerifiedFile(
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
  } catch (_) {
    await out.close();
    rethrow;
  }
}

/// Stages exactly two user-provided local assets for a VITS/Piper model:
/// model.onnx and tokens.txt. The native sherpa-onnx runtime is NOT started
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
}) async {
  manifest.validate();
  if (maxModelBytes < 1 || maxModelBytes > 600 * 1024 * 1024 ||
      maxTokensBytes < 1 || maxTokensBytes > 4 * 1024 * 1024) {
    throw const FormatException('Invalid offline model byte budgets');
  }
  await modelsDirectory.create(recursive: true);
  final target = Directory(p.join(modelsDirectory.path, manifest.id));
  Future<InstalledOfflineVoicePack> verify(Directory where) async {
    // Reuse the same size/hash checks on installed files. The recheck uses a
    // private ephemeral verification directory and does not alter the pack.
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

  if (await target.exists()) return verify(target);
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
    // Atomic within the same models directory. Do not replace a previously
    // installed model even if another installation raced this operation.
    if (await target.exists()) {
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
