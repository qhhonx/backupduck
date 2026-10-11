# Android native UI verification

1. Inventory actual entry points, secondary pages, forms, dialogs and system
   transitions. Include normal, empty, busy, failure, cancellation and retry states.
2. Extract contracts for content order, fixed/scrolling regions, typography,
   spacing, icon alignment, action priority and feedback ownership.
3. Implement shared components first. Check actual icon/text rendering with
   English, Chinese, multiline content and enlarged system text.
4. Exercise real transitions. Save reads persisted results; failure preserves
   drafts; cancellation restores the parent. Clipboard and short feedback must
   be visible in the active dialog, not a covered underlying window.
5. Run `python3 scripts/verify-android-ui.py --serial emulator-5554` with an
   isolated emulator and validation package. Inspect light/dark, 411 dp normal
   text and 320 dp enlarged text, with synthetic data.
6. Record physical-device behavior separately: permissions/system returns,
   keyboard, TalkBack, long reception and Google Photos integration are not
   established by a prototype or emulator screenshot.

Generated evidence remains local. A passing build, text lookup or non-overlapping
view rectangle does not prove that the rendered content is complete and aligned.
Do not inject fixture histories or perform cleanup tests in a real installation.
Extend existing checks for new states and shared component defects.
