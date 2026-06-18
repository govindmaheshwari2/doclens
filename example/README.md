# doclens_example

Showcase app for the
[`doclens`](https://pub.dev/packages/doclens)
plugin.

The home screen is a three-option picker between the package's three
shipping flows:

| Option | What it shows |
|---|---|
| **Drop-in scanner** | `await DoclensScreen.scan(context)` — one line of code returns a polished scanner with live preview, auto-capture, and a built-in review screen. |
| **Branded scanner** | `DoclensView` mounted with custom builders — animated coral halo, gradient shutter, live diagnostic readout. A reference for "we control every pixel." |
| **System scanner** | `await DoclensPlatform.instance.scanWithNativeUI(...)` — full-screen OS-native document scanner (iOS Vision document camera, Android ML Kit document scanner). |

The drop-in entry navigates to a small `_ReturnedResult` page after
capture so you can see exactly what `ScanResult` was emitted.

### Extract text (OCR)

Every flow can pull the text out of a scan with
`DoclensPlatform.instance.recognizeText(imagePath: …)`:

- **Drop-in** result page has an **Extract text · OCR** bar.
- **Multi-page batch** — tap any page thumbnail.
- **Branded** review screen — the `Aa` action next to retake / crop.
- **System scanner** — tap any returned page.

All of them open one shared, reusable sheet (`lib/ocr_sheet.dart`,
`showOcrSheet(context, path)`) that runs recognition on-device, then shows
the full transcript (with copy-to-clipboard) and a per-line breakdown with
confidence. It's a single themeable widget you can lift straight into your
own app.

The branded entry lives in `lib/styles/branded_style.dart` — a single
file you can copy into your own app and re-brand.

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
