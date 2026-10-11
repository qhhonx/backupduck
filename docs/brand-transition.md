# BackupDuck · 备份鸭

PhotoBridge is now BackupDuck (备份鸭 in Simplified Chinese). The same project
and Git history continue under [qhhonx/backupduck](https://github.com/qhhonx/backupduck).
The website is [backupduck.app](https://backupduck.app).

## Existing installations

The new iOS, macOS and Android application identity is `app.backupduck`.
This is a new installation, not an in-place update of PhotoBridge. Install
BackupDuck manually and grant its permissions, then pair the sender and Pixel
again. There is no automatic import of the old pairing or transfer database.

Keep the old app and your original library until the new setup has been checked.
Installing BackupDuck does not uninstall PhotoBridge or delete its photos.
Stop backup and receiving in the old apps before starting the new pair, so two
independent setups do not run simultaneously. A new history may resend photos;
Google Photos duplicate handling is separate and is not guaranteed by this app.

On Pixel, gallery copies newly created by BackupDuck use its own folder. Enable
backup for that folder in Google Photos and verify cloud results separately.
Accessibility-based space management, if used, needs permission for the new app.
Existing PhotoBridge gallery and cloud copies are not renamed or modified.

A [Simplified Chinese guide](brand-transition.zh-CN.md) is also available.

## Coordinated release candidate

The first coordinated release is `0.2.0-rc.1`. All senders and receivers must
install the new app and pair again. There is no old-protocol compatibility layer.
Apple project names, Android packages, Rust crates and the C ABI use BackupDuck.
Protocol version 2 uses `/v2/` routes, `x-backupduck-*` headers,
`application/x-backupduck-bundle`, the `BDCK0002` envelope, and
`_backupduck._tcp` discovery. App-owned metadata and export identifiers use the
new name; fallback delivery filenames use `BD_`. Image and video payloads remain
unchanged by this naming update. Release artifacts use
`BackupDuck-<version>-arm64.zip` and `.apk`.

iOS uses the numeric App Store version `0.2.0`; the build and release metadata
identify the RC stage. Existing apps and already saved photos are not modified.

The website demonstration currently shows the earlier PhotoBridge appearance;
its workflow is the same, but it is not a screenshot of the current release.
