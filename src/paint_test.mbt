// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The straight red, green and blue of a colour, from zero to one.
fn rgb_of(color : @moonrgba.Color) -> (Double, Double, Double) {
  let (r, g, b) = color.to_srgb().components()
  (r, g, b)
}

///|
/// Whether two colours agree on all four channels to within `tolerance`.
fn close_enough(
  a : @moonrgba.Color,
  b : @moonrgba.Color,
  tolerance : Double,
) -> Bool {
  let (ar, ag, ab) = rgb_of(a)
  let (br, bg, bb) = rgb_of(b)
  (ar - br).abs() < tolerance &&
  (ag - bg).abs() < tolerance &&
  (ab - bb).abs() < tolerance &&
  (a.alpha - b.alpha).abs() < tolerance
}

///|
/// The colour a paint puts at a point.
fn sample_color(
  paint : @moongfx.Paint,
  x : Float,
  y : Float,
) -> @moonrgba.Color {
  let (r, g, b, a) = paint.sample(@moonmath.Vec2::new(x, y))
  @moonrgba.Color::srgb(
    r.to_double(),
    g.to_double(),
    b.to_double(),
    alpha=a.to_double(),
  )
}

///|
test "a solid paint is the same colour everywhere" {
  let paint = @moongfx.solid(@moonrgba.Color::rgb(10, 20, 30))
  assert_true(
    close_enough(
      sample_color(paint, 0.0, 0.0),
      @moonrgba.Color::rgb(10, 20, 30),
      0.01,
    ),
  )
  assert_true(
    close_enough(
      sample_color(paint, 99.0, -40.0),
      @moonrgba.Color::rgb(10, 20, 30),
      0.01,
    ),
  )
}

///|
test "a linear gradient holds its first colour at the start and its last at the end" {
  let ramp = @moongfx.Gradient::two(
    @moonrgba.Color::rgb(255, 0, 0),
    @moonrgba.Color::rgb(0, 0, 255),
  )
  let paint = @moongfx.linear(
    @moonmath.Vec2::new(0.0, 0.0),
    @moonmath.Vec2::new(100.0, 0.0),
    ramp,
  )
  assert_true(
    close_enough(
      sample_color(paint, 0.0, 5.0),
      @moonrgba.Color::rgb(255, 0, 0),
      0.02,
    ),
  )
  assert_true(
    close_enough(
      sample_color(paint, 100.0, 5.0),
      @moonrgba.Color::rgb(0, 0, 255),
      0.02,
    ),
  )
  // Halfway along, halfway between the two.
  assert_true(
    close_enough(
      sample_color(paint, 50.0, 5.0),
      @moonrgba.Color::rgb(128, 0, 128),
      0.02,
    ),
  )
}

///|
test "a padded gradient holds its ends outside the range" {
  let ramp = @moongfx.Gradient::two(
    @moonrgba.Color::rgb(255, 0, 0),
    @moonrgba.Color::rgb(0, 0, 255),
  )
  let paint = @moongfx.linear(
    @moonmath.Vec2::new(0.0, 0.0),
    @moonmath.Vec2::new(10.0, 0.0),
    ramp,
  )
  assert_true(
    close_enough(
      sample_color(paint, -50.0, 0.0),
      @moonrgba.Color::rgb(255, 0, 0),
      0.02,
    ),
  )
  assert_true(
    close_enough(
      sample_color(paint, 60.0, 0.0),
      @moonrgba.Color::rgb(0, 0, 255),
      0.02,
    ),
  )
}

///|
test "a repeating gradient starts again after one turn" {
  let ramp = @moongfx.Gradient::new(
    [
      { offset: 0.0, color: @moonrgba.Color::rgb(0, 0, 0), },
      { offset: 1.0, color: @moonrgba.Color::rgb(255, 255, 255), },
    ],
    spread=@moongfx.Repeat,
  )
  let paint = @moongfx.linear(
    @moonmath.Vec2::new(0.0, 0.0),
    @moonmath.Vec2::new(10.0, 0.0),
    ramp,
  )
  // 2.5 units into the second turn is a quarter of the way up the ramp.
  assert_true(
    close_enough(
      sample_color(paint, 12.5, 0.0),
      @moonrgba.Color::rgb(64, 64, 64),
      0.03,
    ),
  )
  // A whole turn later is the same colour again.
  assert_true(
    close_enough(
      sample_color(paint, 22.5, 0.0),
      @moonrgba.Color::rgb(64, 64, 64),
      0.03,
    ),
  )
}

///|
test "a reflecting gradient runs back the way it came" {
  let ramp = mirror_ramp()
  let paint = @moongfx.linear(
    @moonmath.Vec2::new(0.0, 0.0),
    @moonmath.Vec2::new(10.0, 0.0),
    ramp,
  )
  // One and a half turns in, the ramp is on its way back down and halfway up.
  assert_true(
    close_enough(
      sample_color(paint, 15.0, 0.0),
      @moonrgba.Color::rgb(128, 128, 128),
      0.05,
    ),
  )
  // Two and a half turns in, it is on its way back up again, at the same height.
  assert_true(
    close_enough(
      sample_color(paint, 25.0, 0.0),
      @moonrgba.Color::rgb(128, 128, 128),
      0.05,
    ),
  )
}

///|
test "a radial gradient is its first colour in the middle and its last on the rim" {
  let ramp = @moongfx.Gradient::two(
    @moonrgba.Color::rgb(255, 255, 255),
    @moonrgba.Color::rgb(0, 0, 0),
  )
  let paint = @moongfx.radial(@moonmath.Vec2::new(50.0, 50.0), 20.0, ramp)
  assert_true(
    close_enough(
      sample_color(paint, 50.0, 50.0),
      @moonrgba.Color::rgb(255, 255, 255),
      0.02,
    ),
  )
  assert_true(
    close_enough(
      sample_color(paint, 70.0, 50.0),
      @moonrgba.Color::rgb(0, 0, 0),
      0.02,
    ),
  )
  // Half the radius out is halfway along the ramp.
  assert_true(
    close_enough(
      sample_color(paint, 60.0, 50.0),
      @moonrgba.Color::rgb(128, 128, 128),
      0.03,
    ),
  )
}

///|
test "a radius of zero or less is not a gradient" {
  let ramp = @moongfx.Gradient::two(
    @moonrgba.Color::rgb(255, 255, 255),
    @moonrgba.Color::rgb(0, 0, 0),
  )
  let paint = @moongfx.radial(@moonmath.Vec2::new(0.0, 0.0), 0.0, ramp)
  // Every point but the centre is outside a circle of no radius, so the rim
  // colour wins.
  assert_true(
    close_enough(
      sample_color(paint, 5.0, 0.0),
      @moonrgba.Color::rgb(0, 0, 0),
      0.05,
    ),
  )
}

///|
test "an image pattern reads the texel under the point" {
  let bytes : Array[Byte] = [
    b'\xFF', b'\x00', b'\x00', b'\xFF', // red
     b'\x00', b'\xFF', b'\x00', b'\xFF', // green
     b'\x00', b'\x00', b'\xFF', b'\xFF', // blue
     b'\xFF', b'\xFF', b'\xFF', b'\xFF', // white
  ]
  let image = @moonimage.Image::of(
    2,
    2,
    @moonimage.PixelFormat::Rgba8,
    Bytes::from_array(bytes),
  ) catch {
    _ => fail("the two by two image did not build")
  }
  let pattern = @moongfx.Texture({
    image,
    transform: @moonmath.Affine2::identity(),
    filter: @moongfx.Nearest,
  })
  let red = sample_color(pattern, 0.5, 0.5)
  let blue = sample_color(pattern, 0.5, 1.5)
  assert_true((rgb_of(red).0 - 1.0).abs() < 0.05)
  assert_true((rgb_of(blue).2 - 1.0).abs() < 0.05)
}

///|
test "a gradient is sorted by offset however it was given" {
  let ramp = @moongfx.Gradient::new([
    { offset: 1.0, color: @moonrgba.Color::rgb(0, 0, 255), },
    { offset: 0.0, color: @moonrgba.Color::rgb(255, 0, 0), },
    { offset: 0.5, color: @moonrgba.Color::rgb(0, 255, 0), },
  ])
  let paint = @moongfx.linear(
    @moonmath.Vec2::new(0.0, 0.0),
    @moonmath.Vec2::new(10.0, 0.0),
    ramp,
  )
  assert_true(
    close_enough(
      sample_color(paint, 0.0, 0.0),
      @moonrgba.Color::rgb(255, 0, 0),
      0.02,
    ),
  )
  assert_true(
    close_enough(
      sample_color(paint, 5.0, 0.0),
      @moonrgba.Color::rgb(0, 255, 0),
      0.02,
    ),
  )
  assert_true(
    close_enough(
      sample_color(paint, 10.0, 0.0),
      @moonrgba.Color::rgb(0, 0, 255),
      0.02,
    ),
  )
}

///|
/// A black to white ramp that mirrors.
fn mirror_ramp() -> @moongfx.Gradient {
  @moongfx.Gradient::new(
    [
      { offset: 0.0, color: @moonrgba.Color::rgb(0, 0, 0), },
      { offset: 1.0, color: @moonrgba.Color::rgb(255, 255, 255), },
    ],
    spread=@moongfx.Reflect,
  )
}
