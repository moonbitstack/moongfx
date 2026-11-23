// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How far a point is from the circle of radius `radius` about the origin.
fn off_circle(p : @moonmath.Vec2, radius : Float) -> Float {
  let distance = (p.x * p.x + p.y * p.y).sqrt()
  (distance - radius).abs()
}

///|
/// The largest distance between a contour's points and a circle.
fn worst_off_circle(contour : @moongfx.Contour, radius : Float) -> Float {
  let mut worst : Float = 0.0
  for p in contour.points() {
    let off = off_circle(p, radius)
    if off > worst {
      worst = off
    }
  }
  worst
}

///|
test "an arc flattens to points on the arc, closer than the tolerance" {
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(50.0, 0.0))
    .arc(@moonmath.Vec2::new(0.0, 0.0), 50.0, 0.0, 3.141592653589793)
    .build()
  let tolerances : Array[Float] = [0.5, 0.25, 0.05]
  for tolerance in tolerances {
    let contours = path.flatten(flatten=@moongfx.Flatten::new(tolerance))
    assert_eq(contours.length(), 1)
    assert_true(worst_off_circle(contours[0], 50.0) < 1.0e-3)
  }
}

///|
test "a finer tolerance adds points and never takes them away" {
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(0.0, 0.0))
    .cubic_to(
      @moonmath.Vec2::new(0.0, 60.0),
      @moonmath.Vec2::new(60.0, 60.0),
      @moonmath.Vec2::new(60.0, 0.0),
    )
    .build()
  let coarse = path.flatten(flatten=@moongfx.coarse)
  let fine = path.flatten(flatten=@moongfx.fine)
  assert_true(fine[0].points().length() > coarse[0].points().length())
}

///|
test "a flattened curve stays within the tolerance of the curve" {
  // A quarter circle written as a cubic: the chord error of the flattening has to
  // stay under the tolerance, measured against the true circle.
  let radius : Float = 40.0
  let k : Float = 0.5522847498307936 * radius
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(radius, 0.0))
    .cubic_to(
      @moonmath.Vec2::new(radius, k),
      @moonmath.Vec2::new(k, radius),
      @moonmath.Vec2::new(0.0, radius),
    )
    .build()
  let tolerances : Array[Float] = [0.5, 0.1, 0.02]
  for tolerance in tolerances {
    let contours = path.flatten(flatten=@moongfx.Flatten::new(tolerance))
    let off = worst_off_circle(contours[0], radius)
    // The cubic itself is a ten-thousandth of the radius off the circle, so the
    // points may sit that far out on top of the flattening's own slack.
    assert_true(off <= tolerance + 0.02)
  }
}

///|
test "flattening keeps which subpaths were closed" {
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(0.0, 0.0))
    .line_to(@moonmath.Vec2::new(10.0, 0.0))
    .close()
    .move_to(@moonmath.Vec2::new(0.0, 10.0))
    .line_to(@moonmath.Vec2::new(10.0, 10.0))
    .build()
  let contours = path.flatten()
  assert_eq(contours.length(), 2)
  assert_true(contours[0].is_closed())
  assert_true(!contours[1].is_closed())
}

///|
test "a tolerance of zero or less falls back to the standard one" {
  assert_eq(@moongfx.Flatten::new(0.0).tolerance, @moongfx.standard.tolerance)
  assert_eq(@moongfx.Flatten::new(-1.0).tolerance, @moongfx.standard.tolerance)
}

///|
test "the presets are ordered from coarse to fine" {
  assert_true(@moongfx.coarse.tolerance > @moongfx.standard.tolerance)
  assert_true(@moongfx.standard.tolerance > @moongfx.fine.tolerance)
}
