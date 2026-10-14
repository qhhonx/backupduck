# Thumbnail and motion experiments

These tools measure a committed baseline against the working source and analyse
local recordings. Generated projects, traces and media belong in ignored `build/`
storage. They are not uploaded. Use a disposable simulator containing synthetic
Photos fixtures; never clear a physical user's library to run a benchmark.

## Cache benchmark

```
python3 scripts/benchmark-thumbnails.py --device SIMULATOR_UDID \
  --baseline BASELINE_COMMIT --output build/cache-comparison
```

Requires Xcode, XcodeGen, the repository's Rust build dependencies and at least
120 synthetic Photos assets. The generated isolated application extracts the
committed pipeline and compares it with the candidate on the same assets. A
controlled asynchronous loader isolates cache and scheduler overhead from iCloud,
PhotoKit decoding and device storage. Patterned images exercise JPEG work.

Three rounds alternate strategy order. Scenarios cover cold dense requests,
memory revisits, five concurrent owners of each rendition, cancellation, larger
cover requests, small and large-cover disk population and disk revisits after clearing memory. Exported
JSON includes elapsed time, first/final latency percentiles, completed requests,
loader starts and process resident bytes. Check completion counts and loader
starts alongside latency: dropping disk writes can deceptively improve timings.
Process resident bytes are not isolated strategy memory or an iPhone peak-memory
measurement. Cold PhotoKit/iCloud performance requires separate device profiling.

Rendition keys include stable asset identity, edit revision, pixel tier and crop
mode. Ownership tests cover cancelling one subscriber while another survives,
burst writes, clear invalidation and retaining sharper transition pixels.

## Recording analysis

```
xcrun swift scripts/sample-motion.swift INPUT_MOVIE build/motion-frames START END 60
python3 scripts/analyze-motion.py --frames build/motion-frames \
  --output build/motion-report --config LOCAL_CONFIG_JSON
python3 scripts/tests/test_motion_analysis.py
```

The sampler saves actual source timestamps and removes repeated decoded frames.
The analyser requires NumPy and Pillow. It reports frame changes, uniform-area
candidates, complete timestamped contact sheets and optional template tracks.
White photographs, sky, legitimate final-row gaps and system surfaces can trigger
uniform-area flags; each flagged interval needs review.

Configuration example (rectangles are original frame pixels, content is normalized):

```json
{
  "content": [0, 0.14, 1, 0.9],
  "tracks": [{
    "name": "moving_photo",
    "reference": "REFERENCE_FRAME.jpg",
    "template": [80, 300, 200, 430],
    "search": [0, 200, 600, 900],
    "analysis_scale": 0.25,
    "scales": [0.8, 0.9, 1, 1.1],
    "start": 2,
    "end": 3
  }],
  "release_windows": [{
    "track": "moving_photo", "property": "y",
    "start": 2.2, "end": 2.8, "min_score": 0.8
  }]
}
```

High-pass normalized correlation tracks position and sampled scale. Contrast is
an image projection proxy, not true layer alpha. Low scores, repeated similar
photos, clipping, changing glass and insufficient scale resolution can invalidate
tracks. Fit manually reviewed autonomous intervals independently from held-gesture
intervals. The candidates are ease-in/out powers, smoothstep, cosine and damped spring responses; a best
fit does not establish the proprietary implementation or uniqueness of a curve.
Record release-boundary uncertainty and validate another interval before treating
parameters as a general rule. The synthetic test recovers a known ease-out curve.
