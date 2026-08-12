# App icon

`AppIcon.svg` is the source of truth. `AppIcon.icns` is generated from it and is
what [`build.sh`](../build.sh) copies into the bundle (`CFBundleIconFile = AppIcon`).

## Regenerating `AppIcon.icns`

Render the SVG to the sizes macOS wants, then pack them:

```bash
python3 -c "
import cairosvg
for px in (16,32,64,128,256,512,1024):
    cairosvg.svg2png(url='Resources/AppIcon.svg', write_to='/tmp/icon.iconset/%d.png'%px, output_width=px, output_height=px)
"
```

The `.iconset` folder needs Apple's exact filenames — `icon_16x16.png`,
`icon_16x16@2x.png` (32px), `icon_32x32.png`, `icon_32x32@2x.png` (64px), and so
on up to `icon_512x512@2x.png` (1024px). Then:

```bash
iconutil -c icns /tmp/icon.iconset -o Resources/AppIcon.icns
```

macOS caches icons aggressively. After swapping the file, `touch` the built
bundle — otherwise Finder and System Settings keep showing the old one and it
looks like the change didn't take.

## Replacing it with generated artwork

If you'd rather have a rendered icon than the flat vector, the prompt below is
tuned for it. Two things matter more than style: the shackle gap has to survive
at 16px, and the artwork needs generous padding or macOS's own rounding will
crop into it.

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

Then convert the result:

```bash
sips -z 1024 1024 icon.png --out /tmp/icon.iconset/icon_512x512@2x.png
```

Generate the remaining sizes from the same PNG the same way, then run `iconutil`
as above. Check it at 16px before committing — detail that reads beautifully at
512 usually turns to mud, which is why the vector here stays this plain.
