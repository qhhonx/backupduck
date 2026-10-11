# BackupDuck icon

BackupDuck / 备份鸭 uses an ivory square with a yellow duck, orange bill and blue landscape wing. The simple silhouette connects the duck character to photos and stays legible at small sizes.

The final source is `AppIcon.png`, generated with the built-in image tool. Platform copies are resized from that same source; Android adaptive icons keep the mark in a safe central area and derive monochrome templates from the same original pixels.

Prompt: one square native app icon; simple friendly yellow duck in profile; tiny navy eye and orange bill; photo-card body and blue landscape wing; opaque warm ivory background; no lettering, mockup, border or extra symbols.

The website sample memories contain generated scenery, not user-library photos. The demonstration video illustrates an earlier version of the same application.

Menu-bar/system-chrome icons derive their mark from `assets/AppIcon.png`. Remove the ivory background, merge the original warm body and bill into one system tint, and preserve the original blue wing and eye as transparent negative space. Never redraw or substitute a similar duck. `scripts/export-menu-bar-icon.swift` exports the same alpha mask to the Mac 20pt PDF, the prototype PNG/SVG, and the Android monochrome bitmap. The PDF embeds the high-resolution mask; it is not a newly drawn vector logo. Full-color launch icons remain unchanged. Re-run the exporter after an approved source change, and inspect the small mark beside neighboring system symbols in light/dark appearances.

Android notifications use density-specific 24 dp PNG alpha masks with a 21 dp mark, exported from the same original pixels. Do not reuse theme-dependent outline drawables as notification small icons.
