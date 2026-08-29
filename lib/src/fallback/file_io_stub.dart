import 'dart:typed_data';

import '../models.dart';

/// Whether path-based file access is available on this platform. Always
/// `false` on web.
const bool fileIoAvailable = false;

const String _webMessage =
    'doclens: file-path operations are not available on web. The live '
    'scanner and path-based warp/rotate/detect require a native platform. '
    'On web, decode your imported image to bytes and use the pure-Dart '
    'PerspectiveWarp / EditCornersScreen building blocks directly.';

Future<Uint8List> readFileBytes(String path) =>
    throw const ScannerUnavailableException(_webMessage);

Future<String> writeTempImage(Uint8List bytes, String extension) =>
    throw const ScannerUnavailableException(_webMessage);
