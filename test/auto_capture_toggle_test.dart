import 'dart:async';

import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// A quad centered and sized so StatusClassifier returns `aligned`.
const _alignedQuad = Quad(
  topLeft: Offset(0.2, 0.2),
  topRight: Offset(0.8, 0.2),
  bottomRight: Offset(0.8, 0.8),
  bottomLeft: Offset(0.2, 0.8),
);

class _FakePlatform extends DoclensPlatform with MockPlatformInterfaceMixin {
  final _controller = StreamController<DetectionEvent>.broadcast();
  int captureCalls = 0;

  void emit(DetectionEvent e) => _controller.add(e);

  @override
  Future<int> initialize(ScannerConfig config) async => 1;

  @override
  Stream<DetectionEvent> detectionEvents() => _controller.stream;

  @override
  Future<void> focusAt(Offset point) async {}

  @override
  Future<ScanResult> capture() async {
    captureCalls++;
    return ScanResult.fromMap({
      'rawImagePath': '/tmp/x.jpg',
      'quad': _alignedQuad.toMap(),
      'rawImageSize': [100.0, 100.0],
    });
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlatform platform;
  setUp(() {
    platform = _FakePlatform();
    DoclensPlatform.instance = platform;
  });

  const config = ScannerConfig(
    enableSharpnessGate: false,
    enableAutoCaptureConfirmation: false,
    autoCaptureStabilityDuration: Duration.zero,
  );

  DetectionEvent aligned() => const DetectionEvent(quad: _alignedQuad);

  test('autoCapture is seeded from the config', () {
    expect(DoclensController(config: config).autoCapture, isTrue);
    expect(
      DoclensController(
        config: const ScannerConfig(enableAutoCapture: false),
      ).autoCapture,
      isFalse,
    );
  });

  test('disabling at runtime stops capturing without a restart', () async {
    final c = DoclensController(config: config);
    await c.initialize();
    c.autoCapture = false;

    for (var i = 0; i < 4; i++) {
      platform.emit(aligned());
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(platform.captureCalls, 0);
    c.dispose();
  });

  test('enabling at runtime resumes capturing without a restart', () async {
    final c = DoclensController(
      config: const ScannerConfig(
        enableAutoCapture: false,
        enableSharpnessGate: false,
        enableAutoCaptureConfirmation: false,
        autoCaptureStabilityDuration: Duration.zero,
      ),
    );
    await c.initialize();

    platform.emit(aligned());
    platform.emit(aligned());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(platform.captureCalls, 0);

    final captured = c.autoCaptureStream.first;
    c.autoCapture = true;
    platform.emit(aligned());
    platform.emit(aligned());
    await captured;

    expect(platform.captureCalls, 1);
    c.dispose();
  });
}
