---
name: moongfx
description: "2D drawing in MoonBit: build paths (lines, quadratics, cubics, arcs, rounded rectangles), fill them under the winding or even-odd rule, stroke them with joins, caps, miter limits and dashes, paint with solid colours, linear and radial gradients or images, clip and transform through a Canvas, and rasterise into an RGBA frame buffer or a GPU batch. Use it for charts, widgets, icons, headless image output and screenshot comparison."
---

# moongfx

Paths in, pixels or batches out. Three packages: `moonbitstack/moongfx` for the
drawing contract, `moonbitstack/moongfx/soft` for the software backend, and
`moonbitstack/moongfx/gpu` for the batch format a GPU backend uploads.

```bash
moon add moonbitstack/moongfx
```

## Draw shapes into a frame buffer

A `Canvas` takes a path, a paint and, if you are stroking, a `Stroke`. The
software backend owns the pixels.

```moonbit
let surface = @soft.Surface::new(240, 120)
let canvas = @moongfx.Canvas::new(surface)
canvas.clear(@moonrgba.Color::rgb(250, 250, 248))
canvas.fill_rounded_rect(
  { min_x: 10.0, min_y: 10.0, max_x: 230.0, max_y: 110.0 },
  @moongfx.Corners::same(14.0),
  @moongfx.linear(
    @moonmath.Vec2::new(10.0, 10.0),
    @moonmath.Vec2::new(230.0, 110.0),
    @moongfx.Gradient::two(@moonrgba.Color::rgb(250, 200, 80), @moonrgba.Color::rgb(200, 60, 120)),
  ),
)
let image = surface.to_image()
assert_eq(image.width.to_int(), 240)
```

## Tessellate without drawing

`fill` and `stroke` return triangles, which is what you want on a GPU or when
you are measuring rather than looking.

```moonbit
let path = @moongfx.Path::builder()
  .move_to(@moonmath.Vec2::new(0.0, 0.0))
  .line_to(@moonmath.Vec2::new(40.0, 0.0))
  .line_to(@moonmath.Vec2::new(40.0, 40.0))
  .close()
  .build()
let filled = @moongfx.fill(path)
let outlined = @moongfx.stroke(
  path,
  @moongfx.Stroke::new(4.0).with_join(@moongfx.Round).with_cap(@moongfx.Round),
)
assert_eq(filled.length(), 2)
assert_eq(outlined.length() > 0, true)
```

## Draw text

Rasterise each glyph once into a shelf atlas, then draw a run as quads that
sample that one texture. `DemoFace` is built in; feed `GlyphSource` from a font
library to use a real face instead.

```moonbit
let surface = @soft.Surface::new(160, 32)
let canvas = @moongfx.Canvas::new(surface)
let cache = @moongfx.GlyphCache::new(@moongfx.DemoFace::new())
let advance = canvas.fill_text(
  @moonmath.Vec2::new(4.0, 24.0),
  "HI",
  16.0,
  @moongfx.solid(@moonrgba.Color::rgb(0, 0, 0)),
  cache,
)
assert_eq(advance, 24.0)
```

## Rules that bite

- Coordinates are y-down pixels; a positive angle turns clockwise on screen.
- A fill's triangles never overlap, so a translucent fill inks its area once.
  Two separate `fill` calls do overlap, and their alphas compose.
- A clip is coverage, not geometry: a soft edge in the clip stays soft.
- `Canvas::save` records the transform and the clip depth; `restore` undoes
  both. Forgetting `restore` after a clip narrows everything that follows.
- Flattening tolerance is in drawing units, so choose it after the transform,
  or pass `flatten=` per call.
- `Surface` holds premultiplied pixels; `pixel` and `to_image` unpremultiply for
  you, but `surface.pixels` is the premultiplied buffer.
- A stroked closed path is an annulus: no caps, and the seam is not inked twice.
- `Stroke::with_tolerance` can only tighten the flattening of the curves; the
  tolerance passed to `stroke` is the ceiling.
