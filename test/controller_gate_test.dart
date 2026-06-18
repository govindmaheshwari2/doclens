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
  int focusCalls = 0;
  int captureCalls = 0;

  void emit(DetectionEvent e) => _controller.add(e);

  @override
  Future<int> initialize(ScannerConfig config) async => 1;

  @override
  Stream<DetectionEvent> detectionEvents() => _controller.stream;

  @override
  Future<void> focusAt(Offset point) async => focusCalls++;

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

  DetectionEvent aligned({double? sharpness}) =>
      DetectionEvent(quad: _alignedQuad, sharpness: sharpness);

  test('gate disabled -> blurry aligned frame still captures (legacy)', () async {
    final c = DoclensController(
      config: const ScannerConfig(
        enableSharpnessGate: false,
        enableAutoCaptureConfirmation: false,
        autoCaptureStabilityDuration: Duration.zero,
      ),
    );
    await c.initialize();
    final captured = c.autoCaptureStream.first;
    platform.emit(aligned(sharpness: 0.1)); // very blurry
    platform.emit(aligned(sharpness: 0.1));
    await captured;
    expect(platform.captureCalls, 1);
    c.dispose();
  });

  test('gate enabled -> blurry aligned frame does NOT capture', () async {
    final c = DoclensController(
      config: const ScannerConfig(
        enableSharpnessGate: true,
        enableAutoCaptureConfirmation: false,
        autoCaptureStabilityDuration: Duration.zero,
        autoCaptureFocusTimeout: Duration(seconds: 30),
      ),
    );
    await c.initialize();
    for (var i = 0; i < 5; i++) {
      platform.emit(aligned(sharpness: 0.1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(platform.captureCalls, 0);
    expect(platform.focusCalls, greaterThanOrEqualTo(1)); // focus-lock requested
    c.dispose();
  });

  test('gate enabled -> sharp plateau captures', () async {
    final c = DoclensController(
      config: const ScannerConfig(
        enableSharpnessGate: true,
        enableAutoCaptureConfirmation: false,
        autoCaptureStabilityDuration: Duration.zero,
        autoCaptureFocusTimeout: Duration(seconds: 30),
      ),
    );
    await c.initialize();
    final captured = c.autoCaptureStream.first;
    for (final s in [20.0, 40.0, 60.0, 60.0]) {
      platform.emit(aligned(sharpness: s));
    }
    await captured;
    expect(platform.captureCalls, 1);
    c.dispose();
  });

  test('gate enabled -> timeout fires capture even while blurry', () async {
    final c = DoclensController(
      config: const ScannerConfig(
        enableSharpnessGate: true,
        enableAutoCaptureConfirmation: false,
        autoCaptureStabilityDuration: Duration.zero,
        autoCaptureFocusTimeout: Duration(milliseconds: 80),
      ),
    );
    await c.initialize();
    final captured = c.autoCaptureStream.first;
    // Keep feeding blurry frames; the deadline should fire anyway.
    Timer.periodic(const Duration(milliseconds: 15), (t) {
      if (c.isCapturing) {
        t.cancel();
        return;
      }
      platform.emit(aligned(sharpness: 0.1));
    });
    await captured;
    expect(platform.captureCalls, 1);
    c.dispose();
  });
}
