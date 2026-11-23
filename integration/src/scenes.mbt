// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The size every scene is drawn at, matching the generator in `scripts/refs`.
let scene_size : Int32 = 256

///|
/// A fresh transparent surface at scene size.
fn scene_surface() -> @soft.Surface {
  @soft.Surface::new(scene_size, scene_size)
}

///|
/// A colour from eight-bit channels, the way the reference generator writes one.
fn colour(r : Int32, g : Int32, b : Int32) -> @moonrgba.Color {
  @moonrgba.Color::rgb(r, g, b)
}

///|
/// A point, to keep the scene code readable.
fn at(x : Float, y : Float) -> @moonmath.Vec2 {
  @moonmath.Vec2::new(x, y)
}

///|
/// A rectangle, optionally wound the other way so that it punches a hole.
fn rect_path(
  x : Float,
  y : Float,
  w : Float,
  h : Float,
  reversed : Bool,
) -> @moongfx.Path {
  let builder = @moongfx.Path::builder()
  if reversed {
    let _ = builder
      .move_to(at(x, y))
      .line_to(at(x, y + h))
      .line_to(at(x + w, y + h))
      .line_to(at(x + w, y))
  } else {
    let _ = builder
      .move_to(at(x, y))
      .line_to(at(x + w, y))
      .line_to(at(x + w, y + h))
      .line_to(at(x, y + h))
  }
  let _ = builder.close()
  builder.build()
}

///|
/// A circle as four cubic steps, wound either way.
///
/// The reference generator has no arc primitive, so the scenes spell a circle out
/// as cubics on both sides. A quarter circle with this control length stays
/// within a fortieth of a percent of the true radius, far below one pixel.
fn circle_path(
  cx : Float,
  cy : Float,
  r : Float,
  reversed : Bool,
) -> @moongfx.Path {
  let k : Float = 0.5522847498307936 * r
  let builder = @moongfx.Path::builder()
  if reversed {
    let _ = builder
      .move_to(at(cx + r, cy))
      .cubic_to(at(cx + r, cy - k), at(cx + k, cy - r), at(cx, cy - r))
      .cubic_to(at(cx - k, cy - r), at(cx - r, cy - k), at(cx - r, cy))
      .cubic_to(at(cx - r, cy + k), at(cx - k, cy + r), at(cx, cy + r))
      .cubic_to(at(cx + k, cy + r), at(cx + r, cy + k), at(cx + r, cy))
  } else {
    let _ = builder
      .move_to(at(cx + r, cy))
      .cubic_to(at(cx + r, cy + k), at(cx + k, cy + r), at(cx, cy + r))
      .cubic_to(at(cx - k, cy + r), at(cx - r, cy + k), at(cx - r, cy))
      .cubic_to(at(cx - r, cy - k), at(cx - k, cy - r), at(cx, cy - r))
      .cubic_to(at(cx + k, cy - r), at(cx + r, cy - k), at(cx + r, cy))
  }
  let _ = builder.close()
  builder.build()
}

///|
/// A pentagram: five corners taken in order, so every side crosses two others.
fn pentagram_path(cx : Float, cy : Float, radius : Float) -> @moongfx.Path {
  let builder = @moongfx.Path::builder()
  for i in 0..<5 {
    let turn = as_count(i)
    let angle : Float = -3.141592653589793 / 2.0 +
      4.0 * 3.141592653589793 * turn / 5.0
    let x = cx + radius * @math.cosf(angle)
    let y = cy + radius * @math.sinf(angle)
    if i == 0 {
      let _ = builder.move_to(at(x, y))
    } else {
      let _ = builder.line_to(at(x, y))
    }
  }
  let _ = builder.close()
  builder.build()
}

///|
/// A count as a float.
fn as_count(n : Int32) -> Float {
  Float::from_double(Int32::to_double(n))
}

///|
/// The five-by-seven glyphs the text scene uses, the same table the reference
/// generator carries.
fn scene_glyph(code : Char) -> Array[Int32]? {
  let rows = match code.to_ascii_uppercase() {
    ' ' => [0, 0, 0, 0, 0, 0, 0]
    'A' => [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]
    'B' => [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110]
    'C' => [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110]
    'F' => [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000]
    'G' => [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111]
    'M' => [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001]
    'N' => [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001]
    'O' => [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]
    'X' => [0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b01010, 0b10001]
    '0' => [0b01110, 0b10011, 0b10101, 0b10101, 0b10101, 0b11001, 0b01110]
    '1' => [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]
    '2' => [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111]
    '3' => [0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110]
    _ => return None
  }
  Some(rows)
}

///|
/// One line of the demo grid, filled as rectangles.
fn scene_text(
  canvas : @moongfx.Canvas,
  x : Float,
  baseline : Float,
  text : StringView,
  size : Float,
  ink : @moonrgba.Color,
) -> Unit {
  let cell = size / 8.0
  let mut pen = x
  for code in text {
    match scene_glyph(code) {
      Some(rows) => {
        let builder = @moongfx.Path::builder()
        let mut painted = false
        for row in 0..<7 {
          for column in 0..<5 {
            if ((rows[row] >> (4 - column)) & 1) == 0 {
              continue
            }
            let rx = pen + as_count(column) * cell
            let ry = baseline + (as_count(row) - 7.0) * cell
            let _ = builder.rect({
              min_x: rx,
              min_y: ry,
              max_x: rx + cell,
              max_y: ry + cell,
            })
            painted = true
          }
        }
        if painted {
          canvas.fill(builder.build(), @moongfx.solid(ink))
        }
      }
      None => ()
    }
    pen = pen + cell * 6.0
  }
}

///|
/// Fills, holes and the two winding rules.
pub fn fill_scene() -> @soft.Surface {
  let surface = scene_surface()
  let canvas = @moongfx.Canvas::new(surface)
  canvas.fill(
    pentagram_path(68.0, 72.0, 52.0),
    @moongfx.solid(colour(200, 40, 60)),
  )
  canvas.fill(
    pentagram_path(180.0, 72.0, 52.0),
    @moongfx.solid(colour(30, 110, 200)),
    rule=@moongfx.EvenOdd,
  )
  let donut = @moongfx.Path::builder()
  let _ = donut.append(circle_path(70.0, 180.0, 44.0, false))
  let _ = donut.append(circle_path(70.0, 180.0, 22.0, true))
  canvas.fill(donut.build(), @moongfx.solid(colour(40, 150, 110)))
  let plate = @moongfx.Path::builder()
  let _ = plate.append(rect_path(130.0, 140.0, 100.0, 80.0, false))
  let _ = plate.append(rect_path(160.0, 160.0, 40.0, 40.0, true))
  canvas.fill(plate.build(), @moongfx.solid(colour(240, 180, 40)))
  surface
}

///|
/// Joins, caps, the miter limit and a dash pattern.
pub fn stroke_scene() -> @soft.Surface {
  let surface = scene_surface()
  let canvas = @moongfx.Canvas::new(surface)
  let line = @moongfx.Path::builder()
  let _ = line
    .move_to(at(20.0, 40.0))
    .line_to(at(70.0, 20.0))
    .line_to(at(110.0, 60.0))
    .line_to(at(160.0, 25.0))
    .line_to(at(200.0, 70.0))
  canvas.stroke_path(
    line.build(),
    @moongfx.Stroke::new(12.0)
    .with_join(@moongfx.Round)
    .with_cap(@moongfx.Round),
    @moongfx.solid(colour(60, 60, 70)),
  )
  let corner = @moongfx.Path::builder()
  let _ = corner
    .move_to(at(20.0, 120.0))
    .line_to(at(120.0, 150.0))
    .line_to(at(20.0, 200.0))
  canvas.stroke_path(
    corner.build(),
    @moongfx.Stroke::new(14.0).with_join(@moongfx.Miter).with_cap(@moongfx.Butt),
    @moongfx.solid(colour(200, 80, 50)),
  )
  let spike = @moongfx.Path::builder()
  let _ = spike
    .move_to(at(20.0, 235.0))
    .line_to(at(120.0, 235.0))
    .line_to(at(20.0, 235.5))
  canvas.stroke_path(
    spike.build(),
    @moongfx.Stroke::new(10.0)
    .with_join(@moongfx.Miter)
    .with_cap(@moongfx.Butt)
    .with_miter_limit(1.5),
    @moongfx.solid(colour(90, 60, 160)),
  )
  canvas.stroke_path(
    circle_path(180.0, 175.0, 44.0, false),
    @moongfx.Stroke::new(8.0)
    .with_join(@moongfx.Round)
    .with_cap(@moongfx.Butt)
    .with_dashes([14.0, 10.0], offset=3.0),
    @moongfx.solid(colour(30, 130, 190)),
  )
  surface
}

///|
/// Linear and radial gradients, padded and repeated.
pub fn gradient_scene() -> @soft.Surface {
  let surface = scene_surface()
  let canvas = @moongfx.Canvas::new(surface)
  let three = @moongfx.Gradient::new([
    { offset: 0.0, color: colour(255, 90, 90), },
    { offset: 0.5, color: colour(250, 220, 80), },
    { offset: 1.0, color: colour(60, 140, 240), },
  ])
  canvas.fill(
    @moongfx.Path::builder()
    .rounded_rect(
      { min_x: 16.0, min_y: 16.0, max_x: 120.0, max_y: 120.0, },
      @moongfx.Corners::same(12.0),
    )
    .build(),
    @moongfx.linear(at(16.0, 16.0), at(120.0, 120.0), three),
  )
  let two = @moongfx.Gradient::two(colour(255, 255, 255), colour(40, 40, 90))
  canvas.fill(
    circle_path(180.0, 68.0, 52.0, false),
    @moongfx.radial(at(180.0, 68.0), 52.0, two),
  )
  let repeating = @moongfx.Gradient::new(
    [
      { offset: 0.0, color: colour(20, 20, 30), },
      { offset: 0.5, color: colour(90, 190, 220), },
    ],
    spread=@moongfx.Repeat,
  )
  canvas.fill(
    @moongfx.Path::builder()
    .rounded_rect(
      { min_x: 16.0, min_y: 140.0, max_x: 240.0, max_y: 240.0, },
      @moongfx.Corners::same(18.0),
    )
    .build(),
    @moongfx.linear(at(16.0, 140.0), at(140.0, 140.0), repeating),
  )
  surface
}

///|
/// Text drawn from the five by seven grid.
pub fn text_scene() -> @soft.Surface {
  let surface = scene_surface()
  let canvas = @moongfx.Canvas::new(surface)
  scene_text(canvas, 16.0, 64.0, "MOON GFX", 32.0, colour(20, 20, 30))
  scene_text(canvas, 16.0, 128.0, "0123 ABC", 16.0, colour(200, 60, 40))
  scene_text(canvas, 16.0, 180.0, "NAB", 24.0, colour(20, 90, 160))
  surface
}

///|
/// Two clips: stripes inside a circle, and a gradient inside a rounded rectangle.
pub fn clip_scene() -> @soft.Surface {
  let surface = scene_surface()
  let canvas = @moongfx.Canvas::new(surface)
  canvas.clip(circle_path(90.0, 100.0, 70.0, false))
  for i in 0..<8 {
    let x : Float = 12.0 + as_count(i) * 20.0
    let ink = if i % 2 == 0 { colour(230, 90, 60) } else { colour(40, 60, 160) }
    canvas.fill(rect_path(x, 10.0, 14.0, 180.0, false), @moongfx.solid(ink))
  }
  canvas.save()
  canvas.restore()
  canvas.clip(
    @moongfx.Path::builder()
    .rounded_rect(
      { min_x: 140.0, min_y: 120.0, max_x: 240.0, max_y: 230.0, },
      @moongfx.Corners::same(16.0),
    )
    .build(),
  )
  let ramp = @moongfx.Gradient::two(colour(250, 240, 200), colour(30, 120, 90))
  canvas.fill(
    rect_path(130.0, 110.0, 120.0, 130.0, false),
    @moongfx.radial(at(190.0, 175.0), 60.0, ramp),
  )
  surface
}

///|
/// Curves: quadratics, cubics, a filled blob and a ring with a square hole.
pub fn curve_scene() -> @soft.Surface {
  let surface = scene_surface()
  let canvas = @moongfx.Canvas::new(surface)
  let wave = @moongfx.Path::builder()
  let _ = wave
    .move_to(at(20.0, 40.0))
    .quad_to(at(80.0, 0.0), at(120.0, 60.0))
    .quad_to(at(160.0, 120.0), at(230.0, 60.0))
  canvas.stroke_path(
    wave.build(),
    @moongfx.Stroke::new(10.0)
    .with_join(@moongfx.Round)
    .with_cap(@moongfx.Round),
    @moongfx.solid(colour(180, 60, 140)),
  )
  let s = @moongfx.Path::builder()
  let _ = s
    .move_to(at(20.0, 110.0))
    .cubic_to(at(60.0, 80.0), at(100.0, 190.0), at(140.0, 130.0))
    .cubic_to(at(170.0, 85.0), at(210.0, 120.0), at(235.0, 105.0))
  canvas.stroke_path(
    s.build(),
    @moongfx.Stroke::new(8.0)
    .with_join(@moongfx.Miter)
    .with_cap(@moongfx.Square),
    @moongfx.solid(colour(40, 120, 180)),
  )
  let blob = @moongfx.Path::builder()
  let _ = blob
    .move_to(at(60.0, 230.0))
    .cubic_to(at(20.0, 200.0), at(40.0, 160.0), at(80.0, 175.0))
    .cubic_to(at(110.0, 155.0), at(150.0, 175.0), at(135.0, 205.0))
    .cubic_to(at(150.0, 235.0), at(95.0, 250.0), at(60.0, 230.0))
  let _ = blob.close()
  canvas.fill(blob.build(), @moongfx.solid(colour(90, 170, 70)))
  let ring = @moongfx.Path::builder()
  let _ = ring
    .move_to(at(186.0, 205.0))
    .line_to(at(226.0, 205.0))
    .line_to(at(226.0, 240.0))
    .line_to(at(186.0, 240.0))
  let _ = ring.close()
  let _ = ring.append(rect_path(196.0, 212.0, 20.0, 21.0, true))
  canvas.fill(ring.build(), @moongfx.solid(colour(230, 200, 60)))
  surface
}
