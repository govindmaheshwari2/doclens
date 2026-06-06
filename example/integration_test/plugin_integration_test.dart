// Integration tests for doclens.
//
// No mocks. These tests require a real device with a working camera.
// They will skip cleanly on simulators where no camera is available.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:doclens/doclens.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initialize → dispose lifecycle on a real device',
      (tester) async {
    final controller = DoclensController();
    try {
      await controller.initialize();
      expect(controller.isInitialized, isTrue);
      expect(controller.textureId, isNotNull);
    } on ScannerPermissionException {
      // Skip on simulators / when permission denied.
      return;
    } on ScannerUnavailableException {
      return;
    }
    await controller.dispose();
  });
}
