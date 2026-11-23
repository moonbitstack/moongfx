// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A surface with a canvas drawing into it.
fn scene(width : Int32, height : Int32) -> (@soft.Surface, @moongfx.Canvas) {
  let surface = @soft.Surface::new(width, height)
  let canvas = @moongfx.Canvas::new(surface)
  (surface, canvas)
}

///|
test "clearing fills every pixel with the colour" {
  let (surface, canvas) = scene(4, 3)
  canvas.clear(@moonrgba.Color::rgb(20, 40, 60))
  let (r, g, b, a) = surface.pixel(0, 0)
  assert_true((r - 20.0 / 255.0).abs() < 0.01)
  assert_true((g - 40.0 / 255.0).abs() < 0.01)
  assert_true((b - 60.0 / 255.0).abs() < 0.01)
  assert_true((a - 1.0).abs() < 0.01)
}

///|
test "a filled rectangle covers its own pixels and no others" {
  let (surface, canvas) = scene(20, 20)
  canvas.fill_rect(
    { min_x: 5.0, min_y: 5.0, max_x: 15.0, max_y: 15.0, },
    @moongfx.solid(@moonrgba.Color::rgb(255, 0, 0)),
  )
  let (r, _, _, a) = surface.pixel(10, 10)
  assert_true((r - 1.0).abs() < 0.01)
  assert_true((a - 1.0).abs() < 0.01)
  let (_, _, _, outside) = surface.pixel(2, 2)
  assert_eq(outside, 0.0)
  let (_, _, _, beyond) = surface.pixel(17, 10)
  assert_eq(beyond, 0.0)
}

///|
test "an edge pixel is partly covered" {
  // A rectangle that stops halfway through the pixel at x = 5 leaves it half in.
  let (surface, canvas) = scene(12, 4)
  canvas.fill_rect(
    { min_x: 0.0, min_y: 0.0, max_x: 5.5, max_y: 4.0, },
    @moongfx.solid(@moonrgba.Color::rgb(0, 0, 0)),
  )
  let (_, _, _, covered) = surface.pixel(5, 2)
  assert_true(covered > 0.35 && covered < 0.65)
  let (_, _, _, full) = surface.pixel(4, 2)
  assert_true(full > 0.95)
}

///|
test "a clip keeps what is inside and nothing else" {
  let (surface, canvas) = scene(40, 40)
  canvas.clip(
    @moongfx.Path::builder()
    .circle(@moonmath.Vec2::new(20.0, 20.0), 10.0)
    .build(),
  )
  canvas.fill_rect(
    { min_x: 0.0, min_y: 0.0, max_x: 40.0, max_y: 40.0, },
    @moongfx.solid(@moonrgba.Color::rgb(0, 128, 0)),
  )
  let (_, _, _, inside) = surface.pixel(20, 20)
  assert_true(inside > 0.95)
  let (_, _, _, corner) = surface.pixel(1, 1)
  assert_eq(corner, 0.0)
}

///|
test "restoring the clip lets drawing through again" {
  let (surface, canvas) = scene(40, 40)
  canvas.save()
  canvas.clip(
    @moongfx.Path::builder()
    .circle(@moonmath.Vec2::new(20.0, 20.0), 5.0)
    .build(),
  )
  canvas.fill_rect(
    { min_x: 0.0, min_y: 0.0, max_x: 40.0, max_y: 40.0, },
    @moongfx.solid(@moonrgba.Color::rgb(0, 0, 255)),
  )
  canvas.restore()
  canvas.fill_rect(
    { min_x: 30.0, min_y: 30.0, max_x: 36.0, max_y: 36.0, },
    @moongfx.solid(@moonrgba.Color::rgb(255, 0, 0)),
  )
  let (r, _, _, a) = surface.pixel(33, 33)
  assert_true(a > 0.95)
  assert_true((r - 1.0).abs() < 0.02)
}

///|
test "a transform moves what is drawn" {
  let (surface, canvas) = scene(40, 40)
  canvas.translate(10.0, 10.0)
  canvas.fill_rect(
    { min_x: 0.0, min_y: 0.0, max_x: 5.0, max_y: 5.0, },
    @moongfx.solid(@moonrgba.Color::rgb(255, 255, 255)),
  )
  let (_, _, _, at_translated_origin) = surface.pixel(1, 1)
  assert_eq(at_translated_origin, 0.0)
  let (_, _, _, at_moved) = surface.pixel(12, 12)
  assert_true(at_moved > 0.95)
}

///|
test "a gradient runs across the shape" {
  let (surface, canvas) = scene(32, 8)
  let ramp = @moongfx.Gradient::two(
    @moonrgba.Color::rgb(255, 0, 0),
    @moonrgba.Color::rgb(0, 0, 255),
  )
  canvas.fill_rect(
    { min_x: 0.0, min_y: 0.0, max_x: 32.0, max_y: 8.0, },
    @moongfx.linear(
      @moonmath.Vec2::new(0.0, 0.0),
      @moonmath.Vec2::new(32.0, 0.0),
      ramp,
    ),
  )
  let (left, _, _, _) = surface.pixel(0, 4)
  let (right, _, _, _) = surface.pixel(31, 4)
  assert_true(left > 0.9)
  assert_true(right < 0.1)
}

///|
test "text puts ink where the glyphs are" {
  let (surface, canvas) = scene(64, 32)
  let face = @moongfx.DemoFace::new()
  let cache = @moongfx.GlyphCache::new(face)
  let _ = canvas.fill_text(
    @moonmath.Vec2::new(4.0, 24.0),
    "HI",
    16.0,
    @moongfx.solid(@moonrgba.Color::rgb(0, 0, 0)),
    cache,
  )
  let mut inked = 0
  for y in 0..<32 {
    for x in 0..<64 {
      let (_, _, _, a) = surface.pixel(x, y)
      if a > 0.5 {
        inked = inked + 1
      }
    }
  }
  // Two letters of a five by seven grid at two pixels a cell: well over a hundred
  // pixels each, and nothing like the whole surface.
  assert_true(inked > 80)
  assert_true(inked < 64 * 32 / 2)
}

///|
test "the text pen moves by the advance it returns" {
  let (_, canvas) = scene(128, 32)
  let face = @moongfx.DemoFace::new()
  let cache = @moongfx.GlyphCache::new(face)
  let moved = canvas.fill_text(
    @moonmath.Vec2::new(0.0, 20.0),
    "ABCD",
    16.0,
    @moongfx.solid(@moonrgba.Color::rgb(0, 0, 0)),
    cache,
  )
  assert_eq(moved, 48.0)
}

///|
test "an image lands in the box it is given" {
  // A two by two image: red and green on top, blue and white below.
  let bytes : Array[Byte] = [
    b'\xFF', b'\x00', b'\x00', b'\xFF', b'\x00', b'\xFF', b'\x00', b'\xFF', b'\x00',
    b'\x00', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  ]
  let image = @moonimage.Image::of(
    2,
    2,
    @moonimage.PixelFormat::Rgba8,
    Bytes::from_array(bytes),
  ) catch {
    _ => fail("the two by two image did not build")
  }
  let (surface, canvas) = scene(16, 16)
  let box : @moongfx.Bounds = {
    min_x: 0.0,
    min_y: 0.0,
    max_x: 16.0,
    max_y: 16.0,
  }
  canvas.draw_image_in(image, box)
  let (r, g, _, a) = surface.pixel(4, 4)
  assert_true(a > 0.95)
  // Bilinear resampling pulls a little of the neighbour in at the centre of a
  // texel's block, so the corners are near their colour rather than exactly it.
  assert_true(r > 0.85 && g < 0.15)
  // Bottom left is the blue texel, top right the green one.
  let (_, _, b, _) = surface.pixel(4, 12)
  assert_true(b > 0.85)
  let (_, g, _, _) = surface.pixel(12, 4)
  assert_true(g > 0.85)
}
