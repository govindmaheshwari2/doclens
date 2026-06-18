import 'package:doclens/src/sharpness_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('null sharpness is treated as focus-ready (degrade gracefully)', () {
    final t = SharpnessTracker(floor: 8.0);
    expect(t.update(null), isTrue);
  });

  test('below floor is never ready even if it is the max seen', () {
    final t = SharpnessTracker(floor: 8.0);
    t.update(1.0);
    t.update(2.0);
    expect(t.update(3.0), isFalse);
  });

  test('a single spurious sharp frame mid-hunt is not ready (needs samples)', () {
    final t = SharpnessTracker(floor: 8.0);
    // First sample above floor, but <3 samples seen -> not ready yet.
    expect(t.update(50.0), isFalse);
  });

  test('plateau at the top of the window is ready', () {
    final t = SharpnessTracker(floor: 8.0);
    t.update(20.0);
    t.update(40.0);
    t.update(60.0);
    // 60 is the recent max and above floor -> ready.
    expect(t.update(60.0), isTrue);
  });

  test('a frame far below recent max is not ready (still hunting)', () {
    final t = SharpnessTracker(floor: 8.0);
    t.update(20.0);
    t.update(40.0);
    t.update(90.0);
    // 30 is above floor but only 33% of recent max 90 -> not ready.
    expect(t.update(30.0), isFalse);
  });

  test('reset clears history', () {
    final t = SharpnessTracker(floor: 8.0);
    t.update(20.0);
    t.update(40.0);
    t.update(60.0);
    t.reset();
    expect(t.update(60.0), isFalse); // <3 samples again
  });
}
