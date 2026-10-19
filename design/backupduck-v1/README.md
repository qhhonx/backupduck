# Shared design foundations

`tokens.json` supplies brand primaries, the accent seed, neutral and state roles,
the illustration palette, semantic text styles, spacing, radius and motion, as
described in the [design constitution](../constitution.md#color).
`scripts/export-design-tokens.py` generates `apps/apple/Shared/DuckTokens.swift`,
the Android `duck_*` resources (including a fixed Material 3 scheme seeded from
wing blue) and `crates/native/src/dashboard/tokens.css`. The `legacy` block keeps
the 0.3.0 palette under its original names until pages migrate to the roles.

`scripts/check-design-literals.py` fails when native page code adds literal
colors or text sizes. Existing ones are counted in
[`../literal-baseline.json`](../literal-baseline.json), which may only shrink.

The historical four-platform prototype in `index.html` illustrates the visual
language with synthetic data. Current platform references and component contracts
are listed in [the design index](../README.md). An older prototype may differ from
the current native baseline; update affected references when changing components.

Read [foundations](specification.md), [motion](motion.md) and
[component rules](../ui-content-rules.md) before implementing UI changes.
