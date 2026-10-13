# iPhone and iPad interface reference

This interactive reference uses synthetic media, metadata, devices and outcomes.
It does not connect to a receiver or establish native implementation coverage.

The maintained contracts are [visual foundations](../backupduck-v1/specification.md),
[component rules](../ui-content-rules.md), [motion](../backupduck-v1/motion.md) and
[UI checks](../iteration-checklist.md). Use these current rules when historical
preview styling differs. Catalog entries reference implementation sources and
list design states, not counts of successful physical-device tests.

Keep platform controls native. Compare the same data and state in the prototype
and actual host; inspect action order, density, visible alignment, cancellation,
error/retry and parent-state preservation. Device observations and limitations
belong in contributor-facing [validation](../../docs/native-validation.md).

## Legacy navigation surface

Use the solid-surface review mode for iOS 17/18 navigation. All four root tabs
share an opaque semantic surface in both standard and scroll-edge states.
The media viewport respects legacy safe areas; newer native floating chrome may
extend over scroll content. Inspect contrast over bright and dark thumbnails,
not only empty pages. The fallback does not replace native tab interaction.

## Media interaction reference

The [focused Apple media reference](../apple-media-interactions.html) supersedes
older inline album switches and simple preview examples for these flows. Its
[contract](../apple-media-interactions.md) defines separate searchable scope
editors, shared consent sheets, dark media browsing, an information drawer/sidebar
and anchored continuous density changes. Check the native host independently.
