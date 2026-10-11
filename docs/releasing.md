# Release operations

## Public source preparation

Follow [the public-source policy](public-source-policy.md). Contributor-facing
documentation uses English; localized product strings and explicitly labeled
translated user guides remain available. Preserve personal development evidence
outside the release tree and remove tracked internal records from the candidate
commit. Review prototypes, assets, links and source comments as well as Markdown.

Run `python3 scripts/audit-public.py --documentation` before staging, then
`python3 scripts/audit-public.py --staged --documentation` against the entire
candidate index. Resolve findings before publication. Deleting a working file or
adding an ignore pattern does not remove it from existing public Git history.
Do not rewrite published history during routine release preparation.

## Version and publication

`release.json` is the release source of truth. Increase `version` and monotonically
increase `build`, update release notes, then push main. The publication workflow
validates and builds Mac and Android, signs artifacts, assembles checksums and
publishes a complete GitHub release. Existing published versions are immutable;
pushing unrelated changes does not replace them. Never reuse or lower a build.

The primary website is prepared for GitHub Pages at `https://backupduck.app`.
The Pages workflow generates `releases.json` and preserves the published signed
`appcast.xml` byte for byte. It only offers complete published releases, never
an unpublished version from `release.json`. A failed build retains the prior
website deployment. The app publication workflow triggers a fresh Pages build
through `workflow_run`, including releases created with `GITHUB_TOKEN`.

The previous Vercel host remains a compatibility service for installed clients
that still use its update URLs. Keep its `/api/releases` and `/appcast.xml`
handlers until those clients no longer need them. See [website hosting](website-hosting.md)
for deployment, domain setup and migration verification.

## Signing

Repository Actions secrets:

- `SPARKLE_PRIVATE_KEY`: base64 Ed25519 seed for signed Mac updates and feeds.
- `BACKUPDUCK_ANDROID_KEYSTORE_BASE64`: dedicated BackupDuck Android release keystore, base64 encoded.
- `BACKUPDUCK_ANDROID_KEYSTORE_PASSWORD`: password for that keystore. The signing entry is detected automatically; use `ANDROID_KEY_ALIAS` only if the store contains multiple keys.

Never commit these values. Back them up offline: losing the Android key prevents
updates to existing installations; losing the Sparkle key also breaks updates for
ad hoc signed Mac installations. Public trust material is in app configuration.
The Mac package has an ad hoc integrity signature and is not Apple-notarized.

Android RC.2 starts the BackupDuck signing identity (`CN=BackupDuck,
OU=Release, O=BackupDuck`). Its public fingerprint is pinned in
`assets/android-signing-cert.sha256`. RC.1 used the earlier signing identity;
an RC.1 installation requires a fresh install to switch certificates. Do not
erase retained originals or existing receiver records without preserving them.

For local release builds, set `BACKUPDUCK_RELEASE=1`; local development signing
identities must not enter public packages. See scripts/package-release.sh and
scripts/verify-release.py for verification. iOS uses each developer's own team;
no personal iOS signing material is provided by CI.

## Acceptance

Inspect the ordinary production `/appcast.xml`, not only a cache-busted endpoint.
Verify its exact bytes/signature and release build, download both published files,
compare SHA256SUMS, and exercise native update checks. Keep release and website
failures visible; do not mark deployment complete from a queued action alone.

## Production installation acceptance

Install and inspect the actual production packages before publishing. Android
uses `app.backupduck`, a non-debuggable Release APK and the certificate pinned in
`assets/android-signing-cert.sha256`; fail the pre-install check if any differs.
An isolated validation package is supplemental evidence, not release acceptance.
macOS must use the release app bundle; iOS must use the Release configuration
with the existing authorized signing identity. Verify installed version/build,
launch, retained data and visible UI separately. Never uninstall an existing app
to resolve a signing mismatch without explicit approval.
