# Contributing to BackupDuck

Read [architecture](docs/architecture.md), the [design system](design/README.md)
and [development conventions](AGENTS.md) before changing native hosts or Rust.
This repository is source available under the license in `LICENSE`.

## Development

Rust is pinned by `rust-toolchain.toml`. Native builds also require the corresponding
platform SDK. See [installation](docs/installation.md) for iOS source setup.

```sh
cargo test --workspace --locked
python3 scripts/export-design-tokens.py --check
python3 scripts/audit-public.py --documentation
node --test site/tests/*.test.mjs
```

Existing CI covers Rust, native builds, generated colors and website checks.
For UI changes, run relevant native interaction/layout checks and inspect rendered
windows; follow [UI checks](design/iteration-checklist.md). Do not run synthetic
storage or cleanup fixtures against a physical device's existing application data.

## Pull requests

Explain the problem, resulting behavior, affected platforms and relevant checks.
Document intentional platform differences and unverified system behavior. Include
synthetic visual examples when useful; omit personal photos, credentials, device
identifiers, machine paths and development diaries.

Update reusable components, design contracts and affected prototypes together.
Public documentation uses English; localized product strings and clearly labeled
translated user guides are retained. See [public-source policy](docs/public-source-policy.md).

Android and Windows senders are unfinished and outside the 0.3.0 UI baseline.
Do not present their prototypes or experimental modules as released applications.
Release operations require separate authorization; see [releasing](docs/releasing.md).
