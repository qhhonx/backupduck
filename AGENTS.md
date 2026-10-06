# BackupDuck development conventions

## Product UI and interaction

Before changing a product interface, read `design/README.md`,
`design/backupduck-v1/specification.md` and `design/backupduck-v1/motion.md`.
The approved design baseline is v1.1. Match the page structure, action hierarchy,
state semantics and light/dark behavior; use platform-native controls and materials.

- Colors come from `design/backupduck-v1/tokens.json`. Run
  `python3 scripts/export-design-tokens.py` after changing them; do not edit the
  generated Apple, Android or browser color files. CI checks generated output.
- Reuse shared design components before adding page-specific styling. Do not use
  a WebView for native photo grids or transfer lists. Preserve virtualization,
  thumbnail cancellation/cache, paging, stable IDs and scroll/selection state.
- Receipt, successful Pixel gallery publication and Google Photos cloud upload
  are separate facts. Never present receipt alone as gallery or cloud success.
  Do not invent missing dates, progress, device temperature or storage readings.
- Keep activity/progress geometry stable. Progress is an overlay, not an extra
  layout row; errors remain actionable and visible. Automatic backup settings
  and pausing the current queue must have distinct labels and behavior.
- Yellow is a brand/illustration or labeled storage-category accent. Use the
  semantic success, attention and failure colors for state, with text and icons.
- Apple system materials must respect Reduce Transparency/Increase Contrast and
  fall back on older systems. Android/browser use solid surfaces; old Pixel
  performance takes precedence over decoration.

## Verification and intentional design changes

Follow `design/iteration-checklist.md` for the affected platforms. Run relevant
native builds and existing interaction/layout tests. Capture representative
light/dark, small-screen and failure states using synthetic data; keep private
photos, pairing credentials and account details out of fixtures and the repo.

If an iteration changes a design rule, update the specification, tokens/components
and relevant reference images together, record the reason/version, and explicitly
describe the change in the PR. A prototype is a reference, not proof of native
behavior or performance. Report outstanding real-device checks honestly.

For Android UI work, follow `design/android-v1.2/native-acceptance.md` before
handoff. Extract component and state contracts from prototype source, verify
feedback in the current window, and inspect actual native screenshots. Run the
covered emulator checks with `scripts/verify-android-ui.py`; extend them when a
new component or state is implemented. Report which flows remain uncovered and
which Pixel checks are pending. Do not treat compilation, text existence or
non-overlapping View rectangles as complete visual acceptance.
