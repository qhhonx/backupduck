# UI change checks

Apply these checks to the platforms and states affected by a change. Do not
regenerate unrelated screenshot matrices without a reason.

1. Preserve the source, backup, receiver and settings information structure and
   make primary actions clear.
2. Reuse semantic tokens and shared components. Run
   `python3 scripts/export-design-tokens.py --check`; regenerate after token changes.
   Run `python3 scripts/check-design-literals.py`; update its baseline when a
   change removes literal colors or text sizes.
3. Keep receipt, gallery publication and cloud upload distinct. Never invent
   dates, progress, temperature or storage readings.
4. Inspect component combinations: first/last rows, untitled groups, heading
   gaps, control alignment, wrapping and action areas.
5. Check light/dark, narrow layouts, large text and long localized content.
   During UI iterations, check light and dark only; large text (one step
   above the default size: Android 1.15, iOS the first larger Dynamic Type
   size) is checked once in the release verification.
   Respect reduced motion, reduced transparency, contrast and platform fallbacks.
6. Preserve selection, scrolling, sorting, paging and thumbnail identity during
   background updates. Progress must not add a layout row.
7. Exercise cancellation, failure, retry and restart where affected. Durable
   submission must not wait for original export inside a modal dialog.
8. Run relevant native builds and existing interaction/layout checks. Separate
   synthetic fixtures, real API checks and physical-device observations.
9. Update the specification and components in the same
   change. Describe intentional platform differences and remaining limits in
   the pull request.
10. Follow the [public-source policy](../docs/public-source-policy.md). Keep
    personal acceptance records and temporary evidence out of commits.

Automation detects covered regressions; inspect rendered text, icons and feedback
in the active window rather than relying only on view rectangles or text lookup.

On Android, review the design catalog (`app.backupduck.catalog`) on the physical
Pixel XL with synthetic scenarios, in Chinese and English; never inject fixtures
or run cleanup tests in a real installation. Exercise real transitions: saving
reads the persisted result, failure preserves drafts, cancellation restores the
parent, and short feedback appears in the active window rather than a covered
one. Record physical-device behaviour separately: permissions and system
returns, keyboard, TalkBack, long reception and Google Photos integration are
not established by catalog screenshots. For notifications, inspect the actual
shade and lock screen; system templates own typography and placement.

For media work, first study complete reference interactions and write the expected
start, drag, reversal and settled states. Check a held partial page drag, a
mid-library pinch, information open/close after zoom, and returning to the same
grid context. Inspect shared consent and preference components in both native
hosts. Passing endpoint assertions cannot establish motion quality; preserve a
synthetic native recording and inspect intermediate frames as separate evidence.
