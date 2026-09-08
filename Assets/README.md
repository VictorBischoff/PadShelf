# App artwork

`AppIcon.png` is the original master artwork created with the built-in image-generation tool. `PadShelf.icns` is packaged from this PNG using Apple's `sips` and `iconutil`; the build script regenerates the required icon sizes. No creative edits are applied during icon packaging.

## Generation prompt

Use case: logo-brand. Create a polished macOS app icon for PadShelf, a native audio sample organizer with a 12-pad sampler layout. Square 1024x1024 raster icon. A single charcoal-black rounded-square app tile, front facing, centered with modest transparent outer margin, containing exactly twelve tactile softly rounded sampler pads arranged in 3 columns and 4 rows. The pads have warm burnt-orange illuminated faces with subtle depth, precise spacing, and tasteful soft reflections on a dark graphite casing. Minimal premium music-production utility aesthetic, clean silhouette readable at small Dock sizes, restrained studio lighting, no perspective distortion. No text, letters, numbers, logos, brand marks, extra objects, background scenery, watermark or mockup. Genuine transparent background outside the rounded-square tile. The app's established palette is charcoal and vivid warm orange.

The returned master image is retained at its original resolution; the requested size is part of the generation prompt. The icon bundle contains sizes from 16 px through 1024 px.
