# doclens_example

Showcase app for the
[`doclens`](https://pub.dev/packages/doclens)
plugin.

The home screen is a two-option picker between the package's two shipping
flows:

| Option | What it shows |
|---|---|
| **Drop-in scanner** | `await DoclensScreen.scan(context)` — one line of code returns a polished scanner with live preview, auto-capture, and a built-in review screen. |
| **System scanner** | `await DoclensPlatform.instance.scanWithNativeUI(...)` — full-screen native OS document scanner (iOS Vision document camera, Android ML Kit document scanner). |

The drop-in entry navigates to a small `_ReturnedResult` page after capture
so you can see exactly what `ScanResult` was emitted.

The system scanner entry lives in `lib/styles/native_os_style.dart` —
auto-launches the modal on push, then shows a multi-page list of cropped
images.

## Running

```bash
flutter pub get
flutter run
```

A physical device is recommended — the iOS simulator has no rear camera
and Vision will not detect anything in it; the Android emulator's
virtual scene works but quality is limited.

## Platform setup (already done in this example)

### iOS

`ios/Runner/Info.plist` declares:

```xml
<key>NSCameraUsageDescription</key>
<string>Used to scan documents</string>
```

Minimum deployment target is **iOS 13.0** (raised in `ios/Podfile`).

### Android

`AndroidManifest.xml` is unchanged — the plugin merges in the
`android.permission.CAMERA` declaration automatically. ML Kit's Document
Scanner is delivered on demand by Google Play services.

## Building your own UI

This example deliberately ships only the drop-in widget and the
system-scanner option. If you want a fully custom UI, you can:

1. Construct your own `DoclensController`.
2. Mount a `DoclensView` widget with custom builders for the overlay,
   shutter, flash button, and low-light hint.
3. Push your own review screen on capture.

See the plugin's README for the full builder slot API.
