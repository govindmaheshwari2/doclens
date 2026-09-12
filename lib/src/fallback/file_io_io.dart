import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Whether path-based file access is available on this platform. Always
/// `true` where `dart:io` exists (mobile + desktop).
const bool fileIoAvailable = true;

/// An [ImageProvider] for a path on disk. Mobile/desktop only — see
/// [fileIoAvailable].
ImageProvider imageProviderForPath(String path) => FileImage(File(path));

/// Deletes the file at [path], ignoring the result.
Future<void> deleteFile(String path) => File(path).delete();

Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();

/// Write [bytes] to a uniquely named temp file with the given [extension]
/// (no leading dot) and return its path. Mirrors where native writes its
/// scratch captures — the system temp dir.
Future<String> writeTempImage(Uint8List bytes, String extension) async {
  final dir = Directory.systemTemp;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final rand = identityHashCode(bytes) & 0xffffff;
  final path = '${dir.path}/doclens_$stamp$rand.$extension';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
