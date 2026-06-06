# Device verification

This package's brief mandates real-device verification before publish.
This file tracks what has and has NOT been verified.

## Build / static verification (done)

- [x] `flutter pub get` resolves
- [x] `flutter analyze lib` clean
- [x] `dart test` passes for pure-Dart unit tests
- [x] iOS Swift compiles (under `pod lib lint` / Xcode)
- [x] Android Kotlin compiles (`./gradlew :doclens:assembleDebug`)

## Device verification (pending)

These items are part of v0.1.0 acceptance and must be completed before
running `dart pub publish`:

- [ ] Example app launches on an iPhone running iOS 13+
- [ ] Example app launches on a Pixel / Android device running API 21+
- [ ] Live quad outline tracks a paper bill in real time on both platforms
- [ ] Auto-capture fires within ~2 seconds of holding a steady bill
- [ ] No false captures when no paper is in frame
- [ ] Captured cropped image is perspective-corrected, sharp, no fringing
- [ ] `EditCornersScreen`: drag handles, save, re-warp produces correct output
- [ ] Background app for 30s, return: camera resumes, no crash
- [ ] Deny camera permission: `ScannerPermissionException` is thrown
- [ ] Memory growth after 100 captures < 20 MB

When complete, save video evidence to this folder:
`detection_ios.mp4`, `detection_android.mp4`, `autocapture.mp4`,
`edit_corners.mp4`. Reference them from this README.

## Tuning corpus

Per the brief, defaults are to be validated on 20+ real bills/receipts
across angles, lighting, and backgrounds. See [../tuning.md](../tuning.md).
