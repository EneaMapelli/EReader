import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'manual_voice_install_staging.dart';

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
              reserved.hasMatch(part) || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(part) &&
              part != '!v') ||
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

const _voiceManifestFile = 'voice-pack.json';

Future<OfflineVoicePackManifest> _readPersistedVoiceManifest(
    Directory directory) async {
  final file = File(p.join(directory.path, _voiceManifestFile));
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('Missing verified voice pack manifest');
  }
  final length = await file.length();
  if (length < 2 || length > 1024 * 1024) {
    throw const FormatException('Offline voice manifest too large');
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Offline voice manifest must be an object');
  }
  return OfflineVoicePackManifest.fromJson(decoded);
}

Future<void> _verifyPackContents(
    Directory directory, OfflineVoicePackManifest manifest) async {
  final expectedFiles = <String>{
    'model.onnx',
    'tokens.txt',
    _voiceManifestFile,
    for (final file in manifest.phonemizerResources) file.relativePath,
  };
  final expectedDirectories = <String>{};
  for (final resource in manifest.phonemizerResources) {
    final parts = resource.relativePath.split('/');
    for (var i = 1; i < parts.length; i++) {
      expectedDirectories.add(parts.take(i).join('/'));
    }
  }
  var filesSeen = 0;
  await for (final item in directory.list(
      recursive: true, followLinks: false)) {
    final relative =
        p.relative(item.path, from: directory.path).replaceAll('\\', '/');
    final type =
        await FileSystemEntity.type(item.path, followLinks: false);
    if (type == FileSystemEntityType.file && expectedFiles.contains(relative)) {
      filesSeen++;
    } else if (type == FileSystemEntityType.directory &&
        expectedDirectories.contains(relative)) {
      continue;
    } else {
      throw const FormatException('Unexpected file in offline voice pack');
    }
    if (filesSeen > expectedFiles.length) {
      throw const FormatException('Excessive files in offline voice pack');
    }
  }
  if (filesSeen != expectedFiles.length) {
    throw const FormatException('Missing files in offline voice pack');
  }
}

Future<int> _copyVerifiedFile(
  File source,
  File? destination, {
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
  final out = destination?.openWrite();
  var written = 0;
  try {
    await for (final part in source.openRead()) {
      if (part.length > maxBytes - written) {
        throw const FormatException('Offline voice file grew beyond budget');
      }
      hashInput.add(part);
      out?.add(part);
      written += part.length;
    }
    hashInput.close();
    if (out != null) {
      await out.flush();
      await out.close();
    }
    if (written < 1 || digest.toString() != expectedDigest) {
      throw const FormatException('Offline voice SHA-256 mismatch');
    }
    return written;
  } catch (_) {
    if (out != null) await out.close();
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

  Future<void> copyPhonemizerResources(Directory from, Directory? to) async {
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
      final destination =
          to == null ? null : File(p.joinAll([to.path, ...parts]));
      if (destination != null) {
        await destination.parent.create(recursive: true);
      }
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
    // Rehash the installed files as streams without duplicating a large
    // ONNX file on disk. A changed manifest or unexpected extra file is
    // rejected before any native runtime can use this directory.
    if (await FileSystemEntity.type(where.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('Offline voice pack directory is unsafe');
    }
    final stored = await _readPersistedVoiceManifest(where);
    if (jsonEncode(stored.toJson()) != jsonEncode(manifest.toJson())) {
      throw const FormatException('Installed voice manifest does not match');
    }
    await _verifyPackContents(where, manifest);
    await _copyVerifiedFile(
      File(p.join(where.path, 'model.onnx')), null,
      expectedDigest: manifest.modelSha256, maxBytes: maxModelBytes,
    );
    await _copyVerifiedFile(
      File(p.join(where.path, 'tokens.txt')), null,
      expectedDigest: manifest.tokensSha256, maxBytes: maxTokensBytes,
    );
    await copyPhonemizerResources(where, null);
    return InstalledOfflineVoicePack(
      manifest: manifest,
      modelPath: p.join(where.path, 'model.onnx'),
      tokensPath: p.join(where.path, 'tokens.txt'),
    );
  }

  if (await FileSystemEntity.type(target.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return verify(target);
  }
  final staging = await ManualVoiceInstallStaging.create(modelsDirectory);
  final temporary = staging.payload;
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
    await File(p.join(temporary.path, _voiceManifestFile))
        .writeAsString(jsonEncode(manifest.toJson()), flush: true);
    await _verifyPackContents(temporary, manifest);
    // Atomic within the same models directory. Do not replace a previously
    // installed model even if another installation raced this operation.
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      // The verification must settle inside try before deleting staging.
      return await verify(target);
    }
    await temporary.rename(target.path);
    return InstalledOfflineVoicePack(
      manifest: manifest,
      modelPath: p.join(target.path, 'model.onnx'),
      tokensPath: p.join(target.path, 'tokens.txt'),
    );
  } finally {
    await staging.finish();
  }
}

/// Reopen a previously installed voice after process restart. The embedded
/// manifest is read from the application's private directory, and every
/// model, token and phonemizer asset is rehashed before it is returned.
///
/// [packId] is validated before it becomes part of a filesystem path; no
/// model is downloaded, loaded into FFI, or made automatically selectable.
Future<InstalledOfflineVoicePack> loadInstalledOfflineVoicePack({
  required String packId,
  required Directory modelsDirectory,
  OfflineVoicePackManifest? expectedManifest,
}) async {
  if (!RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$').hasMatch(packId)) {
    throw const FormatException('Invalid offline voice ID');
  }
  final target = Directory(p.join(modelsDirectory.path, packId));
  if (await FileSystemEntity.type(target.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const FormatException('Offline voice pack is not installed');
  }
  final manifest = await _readPersistedVoiceManifest(target);
  if (manifest.id != packId) {
    throw const FormatException('Voice pack identity changed');
  }
  // On-disk hashes alone cannot authenticate themselves: when the caller
  // retained an independently trusted manifest, require a byte-for-byte
  // match before making a model available to native FFI.
  if (expectedManifest != null) {
    expectedManifest.validate();
    if (jsonEncode(expectedManifest.toJson()) !=
        jsonEncode(manifest.toJson())) {
      throw const FormatException('Offline voice metadata changed');
    }
  }
  return installOfflineVoicePack(
    manifest: manifest,
    sourceDirectory: target,
    modelsDirectory: modelsDirectory,
  );
}

/// Sanitized catalog entry. An invalid pack is visible as unavailable rather
/// than silently disappearing or being passed to native inference.
class OfflineVoicePackInspection {
  const OfflineVoicePackInspection({
    required this.id,
    required this.ready,
    this.installed,
    this.verifiedDiskBytes,
  });

  final String id;
  final bool ready;
  final InstalledOfflineVoicePack? installed;
  /// Only known pack files counted AFTER the SHA-256 inspection succeeded.
  /// Null for damaged/unknown packs; never a claim about whole disk usage.
  final int? verifiedDiskBytes;
}

/// Human-readable, deterministic size labels for a local-only diagnostic.
/// These are logical file bytes, not allocated filesystem blocks.
String offlineVoiceSizeLabel(int bytes) {
  if (bytes < 0) throw ArgumentError.value(bytes, 'bytes');
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
}

int verifiedOfflineVoiceTotalBytes(
    Iterable<OfflineVoicePackInspection> packs) {
  var total = 0;
  for (final pack in packs) {
    if (pack.ready && pack.verifiedDiskBytes != null) {
      total += pack.verifiedDiskBytes!;
    }
  }
  return total;
}

/// Count only files the manifest permits, and only after the complete
/// on-disk hash check. Avoid recursive directory-size traversal or scanning
/// other application files; a removed/swapped asset invalidates inspection.
Future<int> _verifiedOfflineVoiceFileBytes(
    InstalledOfflineVoicePack pack) async {
  final root = p.dirname(pack.modelPath);
  final files = <File>[
    File(pack.modelPath),
    File(pack.tokensPath),
    File(p.join(root, _voiceManifestFile)),
    for (final resource in pack.manifest.phonemizerResources)
      File(p.joinAll([root, ...resource.relativePath.split('/')])),
  ];
  var total = 0;
  for (final file in files) {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('Offline model asset changed after verification');
    }
    total += await file.length();
  }
  return total;
}

/// Return primary language tags from SHA-verified, installed local packs.
/// Invalid packs have unknown metadata and remain visible as warnings.
String? offlinePackLanguage(OfflineVoicePackInspection entry) {
  final installed = entry.installed;
  if (!entry.ready || installed == null) return null;
  return installed.manifest.locale
      .trim().toLowerCase().replaceAll('_', '-').split('-').first;
}

List<String> installedOfflineVoiceLanguages(
    Iterable<OfflineVoicePackInspection> packs) {
  final languages = <String>{};
  for (final pack in packs) {
    final language = offlinePackLanguage(pack);
    if (language != null) languages.add(language);
  }
  return List<String>.unmodifiable(languages.toList()..sort());
}

/// A failed pack is always visible: a language filter must not hide model
/// corruption or create the appearance of a successfully verified model.
List<OfflineVoicePackInspection> filterInstalledOfflineVoicePacks(
    Iterable<OfflineVoicePackInspection> packs, String? language) =>
    List<OfflineVoicePackInspection>.unmodifiable([
      for (final pack in packs)
        if (language == null ||
            !pack.ready ||
            offlinePackLanguage(pack) == language.toLowerCase())
          pack,
    ]);

/// Inspect only the model whose ID was affected by a user operation.
/// Null means the model directory is absent. A present but invalid model
/// remains visible as unavailable; no other large ONNX files are rehashed.
/// This does not accept arbitrary filesystem paths or enable native inference.
Future<OfflineVoicePackInspection?> inspectSingleOfflineVoicePack({
  required String packId,
  required Directory modelsDirectory,
}) async {
  if (!RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$').hasMatch(packId)) {
    throw const FormatException('Invalid offline voice ID');
  }
  final dir = p.join(modelsDirectory.path, packId);
  if (await FileSystemEntity.type(dir, followLinks: false) ==
      FileSystemEntityType.notFound) return null;
  try {
    final verified = await loadInstalledOfflineVoicePack(
      packId: packId, modelsDirectory: modelsDirectory,
    );
    final bytes = await _verifiedOfflineVoiceFileBytes(verified);
    return OfflineVoicePackInspection(
      id: packId, ready: true, installed: verified,
      verifiedDiskBytes: bytes,
    );
  } catch (_) {
    // Preserve a damaged or unexpectedly changed model as unavailable.
    // A later full refresh can reverify every voice in the catalog.
    return OfflineVoicePackInspection(id: packId, ready: false);
  }
}

/// Merge just one inspected voice into an existing immutable catalog,
/// preserving other verification results and stable lexicographic ordering.
/// A null replacement means this exact voice was removed.
List<OfflineVoicePackInspection> mergeOfflineVoicePackInspection(
    Iterable<OfflineVoicePackInspection> current,
    String packId,
    OfflineVoicePackInspection? replacement) {
  if (replacement != null && replacement.id != packId) {
    throw ArgumentError.value(replacement.id, 'replacement.id');
  }
  final byId = <String, OfflineVoicePackInspection>{
    for (final item in current)
      if (item.id != packId) item.id: item,
    if (replacement != null) packId: replacement,
  };
  final keys = byId.keys.toList()..sort();
  return List<OfflineVoicePackInspection>.unmodifiable(
    [for (final key in keys) byId[key]!],
  );
}

/// Explicitly inspect locally installed voices for a future model-manager UI.
/// This is not called during ordinary reading: SHA-256 verification of a
/// large model is intentionally opt-in and can consume CPU/disk IO.
/// Hidden staging directories are ignored, while corrupt named packs are
/// surfaced without leaking filesystem paths or raw native error text.
Future<List<OfflineVoicePackInspection>> inspectOfflineVoicePacks({
  required Directory modelsDirectory,
  int maxEntries = 128,
}) async {
  if (maxEntries < 1 || maxEntries > 256) {
    throw ArgumentError.value(maxEntries, 'maxEntries');
  }
  if (!await modelsDirectory.exists()) return const [];
  final entries = <OfflineVoicePackInspection>[];
  var checked = 0;
  await for (final entity in modelsDirectory.list(followLinks: false)) {
    final id = p.basename(entity.path);
    if (id.startsWith('.')) continue; // Interrupted private staging work.
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$').hasMatch(id)) {
      continue; // Never interpret arbitrary names as voice identities.
    }
    if (++checked > maxEntries) {
      throw const FormatException('Excessive local voice pack count');
    }
    try {
      final inspected = await inspectSingleOfflineVoicePack(
        packId: id, modelsDirectory: modelsDirectory,
      );
      if (inspected != null) entries.add(inspected);
    } catch (_) {
      entries.add(OfflineVoicePackInspection(id: id, ready: false));
    }
  }
  entries.sort((a, b) => a.id.compareTo(b.id));
  return List<OfflineVoicePackInspection>.unmodifiable(entries);
}


/// Remove exactly one private offline voice pack, never a caller-supplied
/// arbitrary path. Does not contact cloud providers or modify book records.
///
/// Returns false for an already-absent pack. A non-directory pack or an
/// unexpected symlink inside it is rejected rather than traversed. An
/// application cannot safely remove an active native ONNX model on all
/// platforms, so the model-manager UI keeps this experimental TTS provider
/// disabled and requires explicit confirmation before calling this method.
Future<bool> removeInstalledOfflineVoicePack({
  required String packId,
  required Directory modelsDirectory,
}) async {
  if (!RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$').hasMatch(packId)) {
    throw const FormatException('Invalid offline voice ID');
  }
  final path = p.join(modelsDirectory.path, packId);
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return false;
  if (type != FileSystemEntityType.directory) {
    throw const FormatException('Offline voice is not a directory');
  }
  final folder = Directory(path);
  // Never traverse unexpected links in an untrusted/corrupt model folder.
  await for (final entry in folder.list(
      recursive: true, followLinks: false)) {
    if (await FileSystemEntity.type(entry.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('Offline voice contains an unsafe link');
    }
  }
  // Moving inside the same app-private volume prevents a new inspection
  // from selecting this pack while its files are being removed.
  final holding = await modelsDirectory.createTemp('.removing-');
  try {
    await folder.rename(p.join(holding.path, packId));
    await holding.delete(recursive: true);
    return true;
  } finally {
    if (await holding.exists()) {
      // A failed deletion still remains isolated under an ignored private
      // staging name; do not expose it as an installed model on next scan.
      try {
        await holding.delete(recursive: true);
      } on FileSystemException {
        // A Windows decoder can hold model handles briefly; the operation
        // fails instead of silently removing an unrelated directory.
      }
    }
  }
}


/// A local folder selected by the user, checked for a complete and bounded
/// manifest. The manifest is self-declared: this step does NOT authenticate
/// its publisher or grant a voice license.
class OfflineVoiceImportPreview {
  const OfflineVoiceImportPreview({
    required this.manifest,
    required this.sourceDirectory,
    required this.totalBytes,
  });

  final OfflineVoicePackManifest manifest;
  final Directory sourceDirectory;
  final int totalBytes;
}

/// Preview an explicitly selected folder before consent and installation.
/// Reading the small manifest and file metadata does not run native inference,
/// follow links, perform network requests, or copy potentially large ONNX
/// assets. SHA-256 is verified by [installOfflineVoicePack] after approval.
Future<OfflineVoiceImportPreview> inspectOfflineVoiceImportFolder({
  required Directory sourceDirectory,
}) async {
  if (await FileSystemEntity.type(
          sourceDirectory.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const FormatException('Offline voice source must be a directory');
  }
  final manifest = await _readPersistedVoiceManifest(sourceDirectory);
  await _verifyPackContents(sourceDirectory, manifest);

  Future<int> regularSize(String relative, int maxBytes) async {
    final file = File(p.join(sourceDirectory.path, relative));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('Offline voice contains unsafe files');
    }
    final bytes = await file.length();
    if (bytes < 1 || bytes > maxBytes) {
      throw const FormatException('Offline voice source exceeds size limit');
    }
    return bytes;
  }

  var total = await regularSize('model.onnx', 600 * 1024 * 1024);
  total += await regularSize('tokens.txt', 4 * 1024 * 1024);
  var phonemizerSize = 0;
  for (final resource in manifest.phonemizerResources) {
    final parts = resource.relativePath.split('/');
    var ancestor = sourceDirectory.path;
    for (final segment in parts.take(parts.length - 1)) {
      ancestor = p.join(ancestor, segment);
      if (await FileSystemEntity.type(ancestor, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const FormatException('Unsafe phonemizer subdirectory');
      }
    }
    phonemizerSize += await regularSize(
      resource.relativePath, 8 * 1024 * 1024,
    );
    if (phonemizerSize > 64 * 1024 * 1024) {
      throw const FormatException('Offline phonemizer size limit exceeded');
    }
  }
  total += phonemizerSize;
  return OfflineVoiceImportPreview(
    manifest: manifest, sourceDirectory: sourceDirectory,
    totalBytes: total,
  );
}

/// Approve and install the *same* selected folder. Files are revalidated,
/// size-capped and streamed through SHA-256 by the canonical installer,
/// so a file changed between preview and approval is rejected.
Future<InstalledOfflineVoicePack> installPreviewedOfflineVoicePack({
  required OfflineVoiceImportPreview preview,
  required Directory modelsDirectory,
}) async {
  final fresh = await inspectOfflineVoiceImportFolder(
    sourceDirectory: preview.sourceDirectory,
  );
  if (jsonEncode(fresh.manifest.toJson()) !=
      jsonEncode(preview.manifest.toJson())) {
    throw const FormatException('Voice manifest changed after approval');
  }
  return installOfflineVoicePack(
    manifest: preview.manifest,
    sourceDirectory: preview.sourceDirectory,
    modelsDirectory: modelsDirectory,
  );
}
