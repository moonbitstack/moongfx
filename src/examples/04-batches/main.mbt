// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Turns a few shapes into the vertex buffer and draw calls a GPU backend takes,
/// without touching a device.
fn main {
  let builder = @gpu.BatchBuilder::new()
  let panel = @moongfx.Path::builder()
    .rounded_rect(
      { min_x: 8.0, min_y: 8.0, max_x: 120.0, max_y: 88.0, },
      @moongfx.Corners::same(10.0),
    )
    .build()
  builder.fill(
    @moongfx.fill(panel),
    @moongfx.solid(@moonrgba.Color::rgb(30, 34, 48)),
  )
  let circle = @moongfx.Path::builder()
    .circle(@moonmath.Vec2::new(160.0, 48.0), 32.0)
    .build()
  let ramp = @moongfx.Gradient::two(
    @moonrgba.Color::rgb(250, 200, 80),
    @moonrgba.Color::rgb(200, 60, 120),
  )
  builder.fill(
    @moongfx.fill(circle),
    @moongfx.linear(
      @moonmath.Vec2::new(128.0, 16.0),
      @moonmath.Vec2::new(192.0, 80.0),
      ramp,
    ),
  )
  let face = @moongfx.DemoFace::new()
  let cache = @moongfx.GlyphCache::new(face)
  let glyph = match cache.entry('A', 24.0) {
    Some(entry) => entry
    None => {
      println("the glyph was not packed")
      return
    }
  }
  let quad = @moongfx.Quad::of_bounds({
    min_x: 20.0,
    min_y: 40.0,
    max_x: 20.0 + Float::from_double(Int32::to_double(glyph.region.width)),
    max_y: 40.0 + Float::from_double(Int32::to_double(glyph.region.height)),
  })
  builder.mask_quad(
    glyph.region.bounds(),
    quad,
    @moongfx.solid(@moonrgba.Color::rgb(255, 255, 255)),
    0,
  )
  let batch = builder.build()
  println("vertices: \{batch.vertices.length()}")
  println("triangles: \{batch.triangle_count()}")
  println("draw calls: \{batch.draw_count()}")
  for draw in batch.draws {
    println("  from \{draw.first}, \{draw.count} indices, clip \{draw.clip}")
  }
}
