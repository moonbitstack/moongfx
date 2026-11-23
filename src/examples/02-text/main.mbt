// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A heading and a line of figures, laid out with the advance the glyphs report.
fn main {
  let surface = @soft.Surface::new(320, 96)
  let canvas = @moongfx.Canvas::new(surface)
  canvas.clear(@moonrgba.Color::rgb(252, 252, 250))
  let face = @moongfx.DemoFace::new()
  let cache = @moongfx.GlyphCache::new(face)
  let ink = @moongfx.solid(@moonrgba.Color::rgb(24, 28, 40))
  let moved = canvas.fill_text(
    @moonmath.Vec2::new(12.0, 40.0),
    "GLYPH ATLAS",
    30.0,
    ink,
    cache,
  )
  println("the heading advanced \{moved} pixels")
  let width = @moongfx.measure_text(cache, "0123 ABC", 16.0)
  println("the second line will be \{width} pixels wide")
  let _ = canvas.fill_text(
    @moonmath.Vec2::new(12.0, 74.0),
    "0123 ABC",
    16.0,
    @moongfx.solid(@moonrgba.Color::rgb(190, 70, 60)),
    cache,
  )
  println("glyphs rasterised: \{cache.misses()}, reused: \{cache.hits()}")
  let atlas = cache.atlas()
  println(
    "atlas \{atlas.width()} by \{atlas.height()}, \{atlas.fullness()} full",
  )
  let mut inked = 0
  for y in 0..<96 {
    for x in 0..<320 {
      let (r, _, _, _) = surface.pixel(x, y)
      if r < 0.5 {
        inked = inked + 1
      }
    }
  }
  println("dark pixels: \{inked}")
}
