# Shared design foundations

`tokens.json` supplies brand primaries, the accent seed, neutral and state roles,
the illustration palette, semantic text styles, spacing, radius and motion, as
described in the [design constitution](../constitution.md#color).
`scripts/export-design-tokens.py` generates `apps/apple/Shared/DuckTokens.swift`,
the Android `duck_*` resources (including a fixed Material 3 scheme seeded from
wing blue) and `crates/native/src/dashboard/tokens.css`. New code uses the generated role tokens
(`DuckRole`, `duck_role_*`).

`scripts/check-design-literals.py` fails when native page code adds literal
colors or text sizes. Existing ones are counted in
[`../literal-baseline.json`](../literal-baseline.json), which may only shrink.

Android interactive targets are at least 48 dp. These are platform density
contracts, not interchangeable CSS pixels.

Read the [constitution](../constitution.md), [motion](motion.md) and
[component rules](../ui-content-rules.md) before implementing UI changes.
