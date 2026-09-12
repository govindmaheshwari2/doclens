import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'method_channel_platform.dart';
import 'platform_interface.dart';

/// Web registration entrypoint.
///
/// doclens has no native web implementation — the live camera scanner is
/// mobile-only ([DoclensPlatform.supportsLiveScan]) and the compute methods
/// (warp/rotate/detect/OCR) already fall back to pure Dart in
/// [MethodChannelDoclens] when no platform channel answers. Registering the
/// same class here just marks the plugin as web-supported so
/// `flutter build web` and pub.dev stop warning about a missing platform.
class DoclensWeb extends MethodChannelDoclens {
  static void registerWith(Registrar registrar) {
    DoclensPlatform.instance = DoclensWeb();
  }
}
