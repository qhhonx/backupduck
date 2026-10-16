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

Release builds target the simulator’s arm64 architecture. Three rounds rotate
strategy order. Scenarios cover cold dense requests,
memory revisits, five concurrent owners of each rendition, cancellation, larger
cover requests, small and large-cover disk population and disk revisits after clearing memory. Exported
JSON includes elapsed time, first/final latency percentiles, completed requests,
loader starts and process resident bytes. Check completion counts and loader
starts alongside latency: dropping disk writes can deceptively improve timings.
Process resident bytes are not isolated strategy memory or an iPhone peak-memory
measurement. Cold PhotoKit/iCloud performance requires separate device profiling.

### Optional Nuke comparison (experimental)

```
python3 scripts/benchmark-thumbnails.py --device SIMULATOR_UDID \
  --baseline 3d21049 --nuke --output build/nuke-comparison
```

This adds Nuke 13.2.0 only to the generated test project. It does not add a
production dependency. Use `--nuke-path PATH` to reuse an unmodified local checkout at exactly that tag.
The generated project and raw measurements remain in ignored output. Compare
completed requests, loader starts and foreground latency before drawing a
performance conclusion; a lower default concurrency limit is a configuration
difference, not evidence of a slower cache implementation.

The test-only adapter uses Nuke's asynchronous image resource to accept Photos
images directly, avoiding a compulsory JPEG round trip on each cold request.
Both Nuke variants use a 64 MiB image cache, a 256 MiB disk budget, stable
asset/revision/size/crop keys and JPEG quality 0.86. `nuke_default` preserves
default worker counts; it is not an entirely unconfigured pipeline. `nuke_tuned`
uses 24 loading and six encoding workers plus native display preparation.
Disk persistence is explicitly configured as `storeEncodedImages` and must be
verified by completion counts and zero loader starts on reopened-cache revisits.
The adapter flushes and reopens DataCache so staging memory cannot masquerade as
disk. Verify cancellation and bounded memory before proposing production use.

The ordinary warm/revisit scenarios use requests, not Nuke ImagePrefetcher.
`visible_during_prefetch` primes low-priority speculative work and then requests
24 other viewport images at foreground priority. The committed baseline retains
its original scheduling; the candidate and Nuke adapters use their respective
priority APIs. Main-queue timer gaps measure scheduling contention, not rendered
frame rate. All strategies must complete every uncancelled request, and reopened
disk/memory revisits must start zero acquisition requests.
Controlled-loader results cannot rank real PhotoKit adapters without measuring
their acquisition, first display, decode, eviction, disk durability and scrolling
behavior separately. Existing baseline/candidate results predate this extension.

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
