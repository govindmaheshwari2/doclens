# Tuning

The brief mandates tuning auto-capture / status thresholds on at least 20
real bills, receipts, and documents across varied angles, lighting, and
backgrounds, with the goal of:

- **False-positive rate < 5%** (auto-capture fires when no paper is in
  frame, or on something that is not the document)
- **Missed-capture rate < 5%** (paper held steady for 2 s, auto-capture
  does not fire)

## Starting defaults

Set in `ScannerConfig`:

| Param | Default | Rationale |
|---|---|---|
| `detectionThrottleHz` | 12 | Vision/Sobel cost on mid-range devices |
| `autoCaptureCornerThreshold` | 8.0 px | Loose enough for handheld jitter |
| `autoCaptureStabilityDuration` | 1500 ms | Filters reframing, stays responsive |
| `StatusClassifier.minArea` | 0.10 | Below = "too far" |
| `StatusClassifier.maxArea` | 0.85 | Above = "too close" |
| `StatusClassifier.maxAspectSkew` | 0.35 | Above = "tilted" |

## Methodology (when running the tuning pass)

For each document/scenario:

1. Hold the device approximately as a user would (slight handheld jitter).
2. Wait for stable detection, observe `autoCaptureStream` event.
3. Record: did it fire? Was it on the document? Was it within 3 s?
4. Sweep angles: 0°, 15°, 30°. Lighting: bright, normal, dim. Backgrounds:
   plain, busy, glossy.

Aggregate the FP / FN rates, then bisect the threshold around its default
to find a per-platform sweet spot. Document the chosen values here.

## Result table (TBD on real-device pass)

| Scenario | False positives | Missed captures | Notes |
|---|---|---|---|
| Bill / plain bg / bright | | | |
| Bill / busy bg / normal | | | |
| Receipt / plain / dim | | | |
| Book page / angled 30° | | | |
| Glossy magazine / bright | | | |
| ... 15 more scenarios | | | |

Once filled in, commit alongside the verification videos in
`verification/`.
