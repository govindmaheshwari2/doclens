/// Platform-conditional file access for the fallback engine.
///
/// The public scanner API is path-based (`String imagePath`), which requires a
/// real filesystem. That exists on mobile and desktop (`dart:io`) but not on
/// web, so this indirection lets the library compile everywhere: on web the
/// stub throws a clear [ScannerUnavailableException] instead of failing to
/// build against `dart:io`.
export 'file_io_stub.dart' if (dart.library.io) 'file_io_io.dart';
