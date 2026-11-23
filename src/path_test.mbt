// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a rectangle's bounds are its own corners" {
  let path = @moongfx.Path::builder()
    .rect({ min_x: 2.0, min_y: 3.0, max_x: 22.0, max_y: 13.0, })
    .build()
  let box = path.bounds()
  assert_eq(box.min_x, 2.0)
  assert_eq(box.min_y, 3.0)
  assert_eq(box.max_x, 22.0)
  assert_eq(box.max_y, 13.0)
  assert_eq(box.width(), 20.0)
  assert_eq(box.height(), 10.0)
}

///|
test "a curve's bounds reach its extremum, not just its end points" {
  // The curve leaves (0, 0) heading down and comes back up to (10, 0); its lowest
  // point is a quarter of the way down, which an end-point-only box would miss.
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(0.0, 0.0))
    .quad_to(@moonmath.Vec2::new(5.0, 20.0), @moonmath.Vec2::new(10.0, 0.0))
    .build()
  let box = path.bounds()
  assert_eq(box.min_y, 0.0)
  assert_true((box.max_y - 10.0).abs() < 1.0e-4)
}

///|
test "a cubic's bounds reach both of its extrema" {
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(0.0, 0.0))
    .cubic_to(
      @moonmath.Vec2::new(0.0, 30.0),
      @moonmath.Vec2::new(30.0, 30.0),
      @moonmath.Vec2::new(30.0, 0.0),
    )
    .build()
  let box = path.bounds()
  assert_true((box.max_y - 22.5).abs() < 1.0e-3)
  assert_eq(box.min_x, 0.0)
  assert_eq(box.max_x, 30.0)
}

///|
test "a circle's bounds are exact" {
  let path = @moongfx.Path::builder()
    .circle(@moonmath.Vec2::new(10.0, 20.0), 5.0)
    .build()
  let box = path.bounds()
  assert_true((box.min_x - 5.0).abs() < 1.0e-4)
  assert_true((box.max_x - 15.0).abs() < 1.0e-4)
  assert_true((box.min_y - 15.0).abs() < 1.0e-4)
  assert_true((box.max_y - 25.0).abs() < 1.0e-4)
}

///|
test "a half turn of an arc is bounded by its chord and its far side" {
  let arc : @moongfx.Arc = {
    centre: @moonmath.Vec2::new(0.0, 0.0),
    radius: 10.0,
    start: 0.0,
    sweep: 3.141592653589793,
  }
  let path = @moongfx.Path::builder()
    .move_to(arc.start_point())
    .arc(arc.centre, arc.radius, arc.start, arc.sweep)
    .build()
  let box = path.bounds()
  // From (10, 0) round to (-10, 0), reaching y = 10 halfway: the angle grows
  // towards +y, which a y-down screen shows as downwards.
  assert_true((box.min_y - 0.0).abs() < 1.0e-4)
  assert_true((box.max_y - 10.0).abs() < 1.0e-3)
  assert_true((box.max_x - 10.0).abs() < 1.0e-4)
  assert_true((box.min_x + 10.0).abs() < 1.0e-4)
}

///|
test "a transform that only rotates and scales keeps arcs as arcs" {
  let path = @moongfx.Path::builder()
    .circle(@moonmath.Vec2::new(0.0, 0.0), 10.0)
    .build()
  let moved = path.transform(
    @moonmath.Affine2::from_scale(@moonmath.Vec2::new(2.0, 2.0)),
  )
  match moved.elements()[1] {
    Arc(arc) => assert_true((arc.radius - 20.0).abs() < 1.0e-4)
    _ => fail("the arc became something else")
  }
}

///|
test "a skew turns an arc into cubics that cover the same ground" {
  let path = @moongfx.Path::builder()
    .circle(@moonmath.Vec2::new(0.0, 0.0), 10.0)
    .build()
  let skewed = path.transform(
    @moonmath.Affine2::from_scale(@moonmath.Vec2::new(2.0, 1.0)),
  )
  let mut arcs = 0
  let mut cubics = 0
  for element in skewed.elements() {
    match element {
      Arc(_) => arcs = arcs + 1
      CubicTo(_, _, _) => cubics = cubics + 1
      _ => ()
    }
  }
  assert_eq(arcs, 0)
  assert_eq(cubics, 4)
  let box = skewed.bounds()
  assert_true((box.max_x - 20.0).abs() < 1.0e-3)
  assert_true((box.max_y - 10.0).abs() < 1.0e-3)
}

///|
test "the endpoint form of an arc lands on its end point" {
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(10.0, 0.0))
    .arc_to(10.0, 10.0, 0.0, false, true, @moonmath.Vec2::new(0.0, 10.0))
    .build()
  let box = path.bounds()
  assert_true((box.max_x - 10.0).abs() < 0.01)
  assert_true((box.max_y - 10.0).abs() < 0.01)
  // A quarter circle through (10, 10) never leaves the first quadrant.
  assert_true(box.min_x > -0.01)
  assert_true(box.min_y > -0.01)
}

///|
test "a zero-radius endpoint arc is a straight line" {
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(0.0, 0.0))
    .arc_to(0.0, 5.0, 0.0, false, true, @moonmath.Vec2::new(10.0, 0.0))
    .build()
  match path.elements()[1] {
    LineTo(p) => assert_eq(p.x, 10.0)
    _ => fail("the arc did not become a line")
  }
}

///|
test "a corner radius is clamped to half the shorter side" {
  let path = @moongfx.Path::builder()
    .rounded_rect(
      { min_x: 0.0, min_y: 0.0, max_x: 40.0, max_y: 20.0, },
      @moongfx.Corners::same(100.0),
    )
    .build()
  // The result is a capsule: nothing reaches above y = 0 or below y = 20, and the
  // left and right ends are half circles of radius ten.
  let box = path.bounds()
  assert_true((box.min_x - 0.0).abs() < 1.0e-3)
  assert_true((box.max_x - 40.0).abs() < 1.0e-3)
  assert_true((box.min_y - 0.0).abs() < 1.0e-3)
  assert_true((box.max_y - 20.0).abs() < 1.0e-3)
}

///|
test "a line after a closed subpath starts a new one" {
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(0.0, 0.0))
    .line_to(@moonmath.Vec2::new(10.0, 0.0))
    .close()
    .line_to(@moonmath.Vec2::new(20.0, 0.0))
    .build()
  let contours = path.flatten(flatten=@moongfx.standard)
  assert_eq(contours.length(), 2)
  assert_true(contours[1].points().length() == 1)
}

///|
test "an empty path has no bounds" {
  let path = @moongfx.Path::new()
  assert_true(path.bounds().is_empty())
  assert_true(path.is_empty())
}
