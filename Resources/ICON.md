# App icon

`AppIcon.png` is the source of truth — a 1024×1024 RGBA master. `AppIcon.icns` is
generated from it and is what [`build.sh`](../build.sh) copies into the bundle
(`CFBundleIconFile = AppIcon`).

The artwork was generated from the prompt below and then cleaned up: image models
return an opaque rectangle, which is not an app icon. Two things had to change.

**The background had to be knocked out.** The render sat on a light grey field
with a drop shadow under the tile. Left alone that ships as a grey square in
every dark-mode context. The tile was isolated by saturation — it is strongly
purple while the background and its shadow are near-grey, so a saturation
threshold finds the tile's exact bounds and excludes the shadow — then a
supersampled rounded-rectangle mask cut the corners to transparent.

**It is deliberately full-bleed.** Apple's own convention insets the tile to
about 824px inside a 1024px canvas, leaving transparent padding. This icon
instead fills the canvas edge to edge, by preference. If you ever restore the
padding, it is a one-line change — paste an 824px tile at offset (100, 100) onto
a transparent 1024 canvas — but don't "fix" it back thinking it was an oversight.

The measured corner radius of the generated tile was 22.96% of its width, which
is near enough to Apple's squircle that the mask matches without visible slivers.
If you regenerate the art, re-measure rather than assuming that number.

## Regenerating `AppIcon.icns`

Render `AppIcon.png` down to the sizes macOS wants, using Apple's exact
filenames — `icon_16x16.png`, `icon_16x16@2x.png` (32px), `icon_32x32.png`,
`icon_32x32@2x.png` (64px), and so on up to `icon_512x512@2x.png` (1024px) — then
pack them:

```bash
iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
```

macOS caches icons aggressively. After swapping the file, `touch` the built
bundle — otherwise Finder and System Settings keep showing the old one and it
looks like the change didn't take.

To confirm macOS actually resolves the new icon rather than trusting that the
file is in place, ask it: `NSWorkspace.shared.icon(forFile:)` on the built
bundle, drawn to a PNG. If it returns a generic document page, the `.icns` or the
`CFBundleIconFile` key isn't being picked up.

## The generation prompt

> A macOS application icon for a utility called "Open Anyway". Centered on a
> rounded-square (squircle) tile in the macOS Big Sur / Tahoe style, filling
> about 80% of a square canvas with even padding on all sides. The tile is a
> smooth violet-to-indigo gradient, lighter at the top-left and deeper at the
> bottom-right, with a soft glass-like sheen across the upper third. Sitting on
> it is a single open padlock, pure white, clean and geometric with generously
> rounded ends: a solid rounded-rectangle body with a small keyhole knocked out
> of it, and a thick U-shaped shackle above, hinged into the body's top right
> and swung open so its free end hangs clear on the left with an obvious gap.
> Flat, confident, iconographic — no text, no lettering, no drop shadow beneath
> the tile, no photorealism, no background scene. Square 1:1, 1024x1024,
> centered composition.

Steer it with the terms that carry the meaning: **"open padlock, shackle swung
open with a visible gap"** is the whole idea. Models default to a closed lock,
which says the opposite of what this app does.

Whatever comes back, check it at 16px before committing. That gap is the only
thing separating this from every other lock glyph, and at 16px a closed lock and
an open one are about two pixels apart.
