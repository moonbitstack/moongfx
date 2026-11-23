// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The area the triangles cover, with the sign of each dropped.
fn shaded_area(triangles : Array[@moongfx.Triangle]) -> Double {
  let mut total : Double = 0.0
  for triangle in triangles {
    total = total + triangle.area().to_double().abs()
  }
  total
}

///|
/// A horizontal line from the origin, which makes the arithmetic in these tests
/// something a reader can check by hand.
fn level_line(length : Float) -> @moongfx.Path {
  @moongfx.Path::builder()
  .move_to(@moonmath.Vec2::new(0.0, 0.0))
  .line_to(@moonmath.Vec2::new(length, 0.0))
  .build()
}

///|
test "a stroke is as wide as its width says" {
  let triangles = @moongfx.stroke(level_line(100.0), @moongfx.Stroke::new(10.0))
  assert_true((shaded_area(triangles) - 1000.0).abs() < 0.5)
}

///|
test "a square cap adds half a width past each end" {
  let style = @moongfx.Stroke::new(10.0).with_cap(@moongfx.Square)
  let triangles = @moongfx.stroke(level_line(100.0), style)
  assert_true((shaded_area(triangles) - 1100.0).abs() < 0.5)
}

///|
test "a round cap adds the area of the circle it turns through" {
  let style = @moongfx.Stroke::new(10.0)
    .with_cap(@moongfx.Round)
    .with_tolerance(@moongfx.fine)
  let triangles = @moongfx.stroke(level_line(100.0), style)
  let expected = 1000.0 + 3.141592653589793 * 25.0
  assert_true((shaded_area(triangles) - expected).abs() / expected < 0.01)
}

///|
test "a round join fills the corner a bevelled one cuts off" {
  let corner = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(0.0, 0.0))
    .line_to(@moonmath.Vec2::new(200.0, 0.0))
    .line_to(@moonmath.Vec2::new(200.0, 200.0))
    .build()
  let bevel = @moongfx.Stroke::new(40.0)
    .with_join(@moongfx.Bevel)
    .with_tolerance(@moongfx.fine)
  let round = @moongfx.Stroke::new(40.0)
    .with_join(@moongfx.Round)
    .with_tolerance(@moongfx.fine)
  let bevel_area = shaded_area(@moongfx.stroke(corner, bevel))
  let round_area = shaded_area(@moongfx.stroke(corner, round))
  // Two hundred units of line at width forty, less the corner square the two
  // passes share, plus the quarter disc the round join turns through.
  let expected = 2.0 * 200.0 * 40.0 - 400.0 + 3.141592653589793 * 400.0 / 4.0
  assert_true((round_area - expected).abs() / expected < 0.005)
  assert_true(round_area > bevel_area)
}

///|
test "a miter join reaches past the corner and a small limit bevels it" {
  let sharp = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(0.0, 0.0))
    .line_to(@moonmath.Vec2::new(100.0, 20.0))
    .line_to(@moonmath.Vec2::new(0.0, 40.0))
    .build()
  let long = @moongfx.Stroke::new(10.0).with_miter_limit(20.0)
  let short = @moongfx.Stroke::new(10.0).with_miter_limit(1.2)
  let long_area = shaded_area(@moongfx.stroke(sharp, long))
  let short_area = shaded_area(@moongfx.stroke(sharp, short))
  assert_true(long_area > short_area)
  // Twenty degrees between the two arms needs a miter more than twice the width,
  // which the small limit refuses.
  assert_true(long_area / short_area > 1.03)
}

///|
test "dashes leave gaps in the pattern's proportion" {
  let style = @moongfx.Stroke::new(10.0).with_dashes([10.0, 10.0])
  let triangles = @moongfx.stroke(level_line(120.0), style)
  // Half of the line is inked, and the dashes stop and start on the line itself.
  assert_true((shaded_area(triangles) - 600.0).abs() < 6.0)
}

///|
test "a dash offset shifts the pattern along the line" {
  let plain = @moongfx.Stroke::new(10.0).with_dashes([10.0, 10.0])
  let shifted = @moongfx.Stroke::new(10.0).with_dashes([10.0, 10.0], offset=5.0)
  let plain_box = bounds_of(@moongfx.stroke(level_line(120.0), plain))
  let shifted_box = bounds_of(@moongfx.stroke(level_line(120.0), shifted))
  // The offset starts the line five units into the first dash, so the first gap
  // begins five units earlier.
  assert_true(shifted_box.min_x < plain_box.min_x + 1.0e-3)
  assert_true(
    (shaded_area(@moongfx.stroke(level_line(120.0), shifted)) - 600.0).abs() <
    6.0,
  )
}

///|
test "a stroke of no width draws nothing" {
  let triangles = @moongfx.stroke(level_line(100.0), @moongfx.Stroke::new(0.0))
  assert_eq(triangles.length(), 0)
}

///|
test "a closed contour is stroked as a ring, not as a line with two ends" {
  let path = @moongfx.Path::builder()
    .circle(@moonmath.Vec2::new(50.0, 50.0), 40.0)
    .build()
  let style = @moongfx.Stroke::new(6.0)
    .with_cap(@moongfx.Square)
    .with_tolerance(@moongfx.fine)
  let area = shaded_area(@moongfx.stroke(path, style))
  let expected = 3.141592653589793 * (43.0 * 43.0 - 37.0 * 37.0)
  assert_true((area - expected).abs() / expected < 0.02)
}

///|
/// The box the triangles span.
fn bounds_of(triangles : Array[@moongfx.Triangle]) -> @moongfx.Bounds {
  let mut box = @moongfx.Bounds::nothing()
  for triangle in triangles {
    box = box.union(triangle.bounds())
  }
  box
}
