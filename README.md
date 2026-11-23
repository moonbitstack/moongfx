<p align="center">
  <svg width="120" height="120" viewBox="0 0 120 120" role="img" aria-label="moongfx">
    <rect x="0" y="0" width="120" height="120" rx="24" fill="#12141c"/>
    <circle cx="60" cy="60" r="34" fill="#e2584a"/>
    <path d="M60 18 L70 46 L100 46 L76 64 L85 92 L60 74 L35 92 L44 64 L20 46 L50 46 Z" fill="none" stroke="#8fd4c4" stroke-width="3" stroke-linejoin="round"/>
    <circle cx="60" cy="60" r="10" fill="#f2c14e"/>
  </svg>
</p>

<h1 align="center">moongfx</h1>

<p align="center">Two-dimensional drawing for MoonBit: paths, fill and stroke tessellation, a glyph atlas, and a software rasteriser that reads back the pixels it drew.</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#a-first-drawing">First drawing</a> ·
  <a href="#paths">Paths</a> ·
  <a href="#filling">Filling</a> ·
  <a href="#stroking">Stroking</a> ·
  <a href="#paints">Paints</a> ·
  <a href="#clipping-and-transforms">Clipping</a> ·
  <a href="#text">Text</a> ·
  <a href="#backends">Backends</a> ·
  <a href="#api">API</a>
</p>

---

## Install

```bash
moon add moonbitstack/moongfx
```

One import gives you the drawing contract; the software backend lives in its own package, so a program that only tessellates never pulls in a frame buffer.

| Package | What it holds |
| :-- | :-- |
| `moonbitstack/moongfx` | Paths, tessellation, paints, masks, clipping, the glyph atlas, and the `Canvas` and `Backend` contracts |
| `moonbitstack/moongfx/soft` | The software backend: an RGBA frame buffer with antialiasing, gradients, images and clips |
| `moonbitstack/moongfx/gpu` | The batch format a GPU backend uploads: vertices, index ranges, draw calls, textures |

## A first drawing

A canvas needs something to draw into. The software backend is one; it owns the pixels and hands them back as a `Surface`.

```moonbit
let surface = @soft.Surface::new(120, 80)
let canvas = @moongfx.Canvas::new(surface)
canvas.clear(@moonrgba.Color::rgb(250, 248, 244))
canvas.fill_circle(
  @moonmath.Vec2::new(60.0, 40.0),
  28.0,
  @moongfx.solid(@moonrgba.Color::rgb(226, 88, 74)),
)
let (r, g, b, a) = surface.pixel(60, 40)
assert_eq(r > 0.8, true)
assert_eq(a > 0.99, true)
```

Coordinates are in pixels with y pointing down, the convention a screen uses, and one unit is one pixel until a transform says otherwise. Geometry is `Float` — 32-bit — which is what makes a path comparable with what another rasteriser draws from the same numbers.

## Paths

A path is a list of straight and curved steps. The builder chains, and the shape helpers cover what a chart or a widget actually draws.

```moonbit
let badge = @moongfx.Path::builder()
  .rounded_rect(
    { min_x: 8.0, min_y: 8.0, max_x: 108.0, max_y: 64.0 },
    @moongfx.Corners::same(12.0),
  )
  .build()
let curve = @moongfx.Path::builder()
  .move_to(@moonmath.Vec2::new(0.0, 40.0))
  .quad_to(@moonmath.Vec2::new(30.0, 0.0), @moonmath.Vec2::new(60.0, 40.0))
  .cubic_to(
    @moonmath.Vec2::new(75.0, 60.0),
    @moonmath.Vec2::new(90.0, 20.0),
    @moonmath.Vec2::new(110.0, 40.0),
  )
  .build()
assert_eq(badge.is_empty(), false)
assert_eq(curve.bounds().width() > 100.0, true)
```

An arc stays an arc rather than becoming a chain of curves, so its bounds are exact and its flattening is exact too. `arc_to` takes the endpoint form an SVG `A` command uses and turns it into cubics, because an ellipse under a skew is still an ellipse.

```moonbit
let quarter = @moongfx.Path::builder()
  .move_to(@moonmath.Vec2::new(10.0, 0.0))
  .arc_to(10.0, 10.0, 0.0, false, true, @moonmath.Vec2::new(0.0, 10.0))
  .build()
assert_eq(quarter.bounds().max_x <= 10.001, true)
```

### Flattening

Curves are split into straight segments before they reach a tessellator, and how closely they follow the curve is a tolerance you choose. Three presets cover the ordinary cases; they are named, not magic numbers.

```moonbit
let circle = @moongfx.Path::builder()
  .circle(@moonmath.Vec2::new(0.0, 0.0), 100.0)
  .build()
let coarse = circle.flatten(flatten=@moongfx.coarse)
let fine = circle.flatten(flatten=@moongfx.fine)
assert_eq(fine[0].points().length() > coarse[0].points().length(), true)
```

## Filling

A fill becomes triangles that cover exactly the inside, with no overlap, so a translucent fill inks its area once. The two rules every 2D format has are both here.

```moonbit
let star = @moongfx.Path::builder()
  .move_to(@moonmath.Vec2::new(60.0, 10.0))
  .line_to(@moonmath.Vec2::new(95.0, 120.0))
  .line_to(@moonmath.Vec2::new(5.0, 50.0))
  .line_to(@moonmath.Vec2::new(115.0, 50.0))
  .line_to(@moonmath.Vec2::new(25.0, 120.0))
  .close()
  .build()
let filled = @moongfx.fill(star)
let holed = @moongfx.fill(star, rule=@moongfx.EvenOdd)
assert_eq(filled.length() > 0, true)
assert_eq(holed.length() < filled.length(), true)
```

A subpath wound the other way punches a hole, which is how a ring or a window is drawn:

```moonbit
let ring = @moongfx.Path::builder()
  .circle(@moonmath.Vec2::new(50.0, 50.0), 40.0)
  .move_to(@moonmath.Vec2::new(70.0, 50.0))
  .arc(@moonmath.Vec2::new(50.0, 50.0), 20.0, 0.0, -6.283185307179586)
  .close()
  .build()
let triangles = @moongfx.fill(ring)
let mut area : Double = 0.0
for triangle in triangles {
  area = area + triangle.area().to_double().abs()
}
assert_eq(area > 3000.0 && area < 4000.0, true)
```

## Stroking

A stroke is wider than a hairline, turns its corners the way you ask, and can be dashed. The outline is built first and then filled, which is what keeps a sharp corner from being inked twice.

```moonbit
let zigzag = @moongfx.Path::builder()
  .move_to(@moonmath.Vec2::new(0.0, 0.0))
  .line_to(@moonmath.Vec2::new(40.0, -20.0))
  .line_to(@moonmath.Vec2::new(80.0, 20.0))
  .build()
let rounded = @moongfx.Stroke::new(8.0)
  .with_join(@moongfx.Round)
  .with_cap(@moongfx.Round)
let outlined = @moongfx.stroke(zigzag, rounded)
assert_eq(outlined.length() > 0, true)
```

| Knob | What it does |
| :-- | :-- |
| `width` | The width of the line, in drawing units |
| `join` | `Miter`, `Bevel` or `Round`, for the outside of a corner |
| `cap` | `Butt`, `Square` or `Round`, for the end of an open path |
| `miter_limit` | How far a miter may reach before it is bevelled instead, as a multiple of the width |
| `dash` | Lengths alternating on and off, with `dash_offset` for the phase |
| `tolerance` | How closely the outline follows a curve |

```moonbit
let dashed = @moongfx.Stroke::new(6.0).with_dashes([12.0, 8.0], offset=4.0)
let dashed_triangles = @moongfx.stroke(zigzag, dashed)
assert_eq(dashed_triangles.length() > 0, true)
```

## Paints

Solid colours, linear and radial gradients, and images all fill the same way: a paint answers "what colour here" in device space, so a backend only has to shade.

```moonbit
let ramp = @moongfx.Gradient::new([
  { offset: 0.0, color: @moonrgba.Color::rgb(250, 200, 80) },
  { offset: 0.5, color: @moonrgba.Color::rgb(232, 120, 90) },
  { offset: 1.0, color: @moonrgba.Color::rgb(90, 120, 220) },
])
let sweep = @moongfx.linear(
  @moonmath.Vec2::new(0.0, 0.0),
  @moonmath.Vec2::new(100.0, 0.0),
  ramp,
)
let (red, _, _, _) = sweep.sample(@moonmath.Vec2::new(0.0, 0.0))
assert_eq(red > 0.9, true)
```

A gradient spreads its ends three ways: `Pad` holds the first and last colour, `Repeat` starts the ramp again, and `Reflect` runs it backwards on every other turn.

```moonbit
let tiled = @moongfx.Gradient::new(
  [
    { offset: 0.0, color: @moonrgba.Color::rgb(0, 0, 0) },
    { offset: 1.0, color: @moonrgba.Color::rgb(255, 255, 255) },
  ],
  spread=@moongfx.Repeat,
)
let stripes = @moongfx.linear(
  @moonmath.Vec2::new(0.0, 0.0),
  @moonmath.Vec2::new(10.0, 0.0),
  tiled,
)
let (shade, _, _, _) = stripes.sample(@moonmath.Vec2::new(2.5, 0.0))
assert_eq(shade > 0.2 && shade < 0.3, true)
```

A radial gradient takes a centre, a radius and an optional focus; the colour at a point is the one where the ray from the focus crosses the circle, which is the highlight a radial gradient is usually used for.

```moonbit
let glow = @moongfx.radial(
  @moonmath.Vec2::new(50.0, 50.0),
  40.0,
  @moongfx.Gradient::two(@moonrgba.Color::rgb(255, 255, 255), @moonrgba.Color::rgb(20, 30, 60)),
)
let (edge, _, _, _) = glow.sample(@moonmath.Vec2::new(90.0, 50.0))
assert_eq(edge < 0.2, true)
```

An image is a paint through a transform, so it can be scaled, turned or skewed like anything else:

```moonbit
let bytes : Array[Byte] = [
  b'\xFF', b'\x00', b'\x00', b'\xFF',
]
let dot = try {
  @moonimage.Image::of(1, 1, @moonimage.PixelFormat::Rgba8, Bytes::from_array(bytes))
} catch {
  _ => @moonimage.Image::new(1, 1, @moonimage.PixelFormat::Rgba8)
}
let tile = @moongfx.Texture({
  image: dot,
  transform: @moonmath.Affine2::from_scale(@moonmath.Vec2::new(8.0, 8.0)),
  filter: @moongfx.Nearest,
})
let (r, _, _, _) = tile.sample(@moonmath.Vec2::new(4.0, 4.0))
assert_eq(r > 0.9, true)
```

## Clipping and transforms

A canvas keeps a transform stack and a clip stack. Both apply to everything drawn after them, and both are undone by `restore`.

```moonbit
let surface = @soft.Surface::new(100, 100)
let canvas = @moongfx.Canvas::new(surface)
canvas.save()
canvas.translate(50.0, 50.0)
canvas.rotate(0.5)
canvas.clip(
  @moongfx.Path::builder().circle(@moonmath.Vec2::new(0.0, 0.0), 30.0).build(),
)
canvas.fill_rect(
  { min_x: -40.0, min_y: -40.0, max_x: 40.0, max_y: 40.0 },
  @moongfx.solid(@moonrgba.Color::rgb(40, 44, 60)),
)
canvas.restore()
let (_, _, _, inside) = surface.pixel(50, 50)
let (_, _, _, outside) = surface.pixel(2, 2)
assert_eq(inside > 0.9, true)
assert_eq(outside, 0.0)
```

A clip is rasterised into an eight-bit coverage mask, and a backend multiplies it into every pixel it writes. That is the same arithmetic on the CPU and on a GPU, so a clipped shape looks the same whichever backend drew it.

## Text

Glyphs are rasterised once, packed into a shelf atlas, and then drawn as quads that sample one texture. The atlas grows while it can and is cleared when it cannot, so a long run of text never runs out of room.

```moonbit
let surface = @soft.Surface::new(200, 40)
let canvas = @moongfx.Canvas::new(surface)
let face = @moongfx.DemoFace::new()
let cache = @moongfx.GlyphCache::new(face)
let ink = @moongfx.solid(@moonrgba.Color::rgb(20, 20, 30))
let advance = canvas.fill_text(@moonmath.Vec2::new(8.0, 30.0), "MOON", 24.0, ink, cache)
assert_eq(advance, 72.0)
assert_eq(cache.misses() > 0, true)
```

`DemoFace` is a five by seven face built into the library, so that text can be drawn, and compared against a reference, with no font file and no I/O. Any font library can feed the atlas instead: `GlyphSource` asks for coverage at a size and nothing else, which is exactly what a parser and a rasteriser produce.

## Backends

`Canvas` never touches a pixel. It moves a path into device space, tessellates it, rasterises a clip, and hands a backend triangles and masks. The software backend fills a frame buffer; the `gpu` package is the format the next one will upload.

```moonbit
let builder = @gpu.BatchBuilder::new()
let square = @moongfx.Path::builder()
  .rect({ min_x: 0.0, min_y: 0.0, max_x: 16.0, max_y: 16.0 })
  .build()
builder.fill(@moongfx.fill(square), @moongfx.solid(@moonrgba.Color::rgb(80, 120, 200)))
let batch = builder.build()
assert_eq(batch.triangle_count(), 2)
assert_eq(batch.draw_count(), 1)
assert_eq(batch.indices.length(), 6)
```

A batch is a vertex buffer, an index buffer, and one draw call per paint. A draw call names the paint, the texture it samples — a glyph atlas, a clip mask, a photograph — and the clip in force. Nothing in it is specific to one graphics API.

### Reading a surface back

`Surface::to_image` unpremultiplies and hands over an image, which `moonimage` can encode. That is how the reference images were made and compared.

```moonbit
let surface = @soft.Surface::new(8, 8)
let canvas = @moongfx.Canvas::new(surface)
canvas.clear(@moonrgba.Color::rgb(255, 255, 255))
let image = surface.to_image()
assert_eq(image.width.to_int(), 8)
assert_eq(image.format, @moonimage.PixelFormat::Rgba8)
```

## Conformance

Six scenes — fills with holes, joins and dashes, gradients, glyphs, clips, curves — are drawn twice: once by this library's software backend, and once by tiny-skia from the same coordinates. The two are compared pixel by pixel in premultiplied space; the reference images and the program that draws them are in `integration/` and `scripts/refs/`.

| Scene | Mean difference | Worst pixel |
| :-- | --: | --: |
| fill | 0.00045 | 0.15 |
| stroke | 0.00105 | 0.69 |
| gradient | 0.00028 | 0.25 |
| text | 0.00000 | 0.00 |
| clip | 0.00014 | 0.20 |
| curves | 0.00067 | 0.29 |

The worst pixel is one on an edge, where the two sides sample differently: this rasteriser takes eight samples down each pixel row where the reference integrates exactly, and a round join is a chain of chords at the stroke's flattening tolerance where the reference draws an arc. The `text` scene agrees to the last bit because the atlas, the blit and the reference all draw the same rectangles.

## API

### Types

| Type | Where | What it is |
| :-- | :-- | :-- |
| `Path` | `moongfx` | A sequence of `MoveTo`, `LineTo`, `QuadTo`, `CubicTo`, `Arc` and `Close` steps |
| `PathBuilder` | `moongfx` | Chains the steps and the shape helpers into a `Path` |
| `Arc` | `moongfx` | A circular arc: centre, radius, start angle, sweep |
| `Corners` | `moongfx` | Four corner radii, for a rounded rectangle |
| `Bounds` | `moongfx` | An axis-aligned box, possibly empty |
| `Triangle` | `moongfx` | Three corners; what a backend fills |
| `FillRule` | `moongfx` | `NonZero` or `EvenOdd` |
| `Flatten` | `moongfx` | A flattening tolerance, with `coarse`, `standard` and `fine` presets |
| `Stroke` | `moongfx` | Width, join, cap, miter limit, dashes, tolerance |
| `Join`, `Cap` | `moongfx` | The corner and end styles |
| `Paint` | `moongfx` | `Solid`, `Linear`, `Radial` or `Texture` |
| `Gradient`, `Stop`, `Spread` | `moongfx` | The colours of a ramp and what happens past its ends |
| `LinearGradient`, `RadialGradient` | `moongfx` | Geometry and a ramp |
| `ImagePattern`, `Filter` | `moongfx` | An image, where it lands, how it is resampled |
| `Mask` | `moongfx` | Eight-bit coverage: a clip, or a rasterised glyph |
| `Quad` | `moongfx` | Four corners in device space |
| `Canvas` | `moongfx` | Transform stack, clip stack, and the drawing calls |
| `Backend` | `moongfx` | What a rasteriser implements |
| `Atlas`, `Region`, `Shelf` | `moongfx` | Shelf packing for coverage |
| `Glyph`, `GlyphSource`, `GlyphCache`, `GlyphKey`, `GlyphEntry` | `moongfx` | Rasterised glyphs and the cache that packs them |
| `DemoFace` | `moongfx` | A built-in five by seven face |
| `Surface` | `moongfx/soft` | The frame buffer, with `pixel` and `to_image` |
| `Batch`, `BatchBuilder`, `DrawCall`, `Vertex`, `Texture` | `moongfx/gpu` | What a GPU backend uploads |

### Functions

| Function | What it does |
| :-- | :-- |
| `fill(path, rule~, flatten~)` | The path as triangles |
| `stroke(path, stroke, flatten~)` | The stroke as triangles |
| `fill_contours(contours, rule)` | The same, from polygons you already have |
| `rasterize(triangles, width, height)` | The triangles as a coverage mask |
| `solid`, `linear`, `radial` | The paints that are not an image |
| `measure_text(cache, text, size)` | How wide a run will be |
| `Canvas::fill`, `Canvas::stroke_path`, `Canvas::clip` | Draw through a canvas |
| `Canvas::fill_text` | Draw a run, returning the advance |

## What it is not

No window, no event loop, no device. This is the drawing half of a UI toolkit: it turns paths, glyphs and paints into pixels or into a batch, and leaves the pixels to whoever owns a window and the batch to whoever owns a GPU.

## License

Apache-2.0.
