// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The total area of a triangle set, with the sign dropped triangle by triangle.
fn total_area(triangles : Array[@moongfx.Triangle]) -> Double {
  let mut sum : Double = 0.0
  for t in triangles {
    sum = sum + t.area().to_double().abs()
  }
  sum
}

///|
test "a filled circle has the area of the circle" {
  let radius : Float = 40.0
  let path = @moongfx.Path::builder()
    .circle(@moonmath.Vec2::new(50.0, 50.0), radius)
    .build()
  let triangles = @moongfx.fill(path, flatten=@moongfx.Flatten::new(0.01))
  let area = total_area(triangles)
  let expected : Double = 3.141592653589793 * 40.0 * 40.0
  assert_true((area - expected).abs() / expected < 2.0e-3)
}

///|
test "a filled rectangle has the area of the rectangle" {
  let path = @moongfx.Path::builder()
    .rect({ min_x: 2.0, min_y: 3.0, max_x: 22.0, max_y: 13.0, })
    .build()
  let triangles = @moongfx.fill(path, flatten=@moongfx.standard)
  assert_eq(triangles.length(), 2)
  assert_true((total_area(triangles) - 200.0).abs() < 1.0e-3)
}

///|
test "a ring keeps its hole with the non-zero rule and loses it without one" {
  let path = @moongfx.Path::builder()
    .circle(@moonmath.Vec2::new(50.0, 50.0), 40.0)
    .circle(@moonmath.Vec2::new(50.0, 50.0), 20.0)
    .build()
  let non_zero = total_area(
    @moongfx.fill(path, flatten=@moongfx.Flatten::new(0.01)),
  )
  let even_odd = total_area(
    @moongfx.fill(
      path,
      rule=@moongfx.EvenOdd,
      flatten=@moongfx.Flatten::new(0.01),
    ),
  )
  let outer : Double = 3.141592653589793 * 40.0 * 40.0
  let inner : Double = 3.141592653589793 * 20.0 * 20.0
  // Both circles run the same way, so the inner one fills too: the hole is gone.
  assert_true((non_zero - outer) / outer < 2.0e-3)
  // The even-odd rule counts the overlap as outside, so the ring is left.
  assert_true((even_odd - (outer - inner)) / outer < 3.0e-3)
}

///|
test "a stroked straight line has the area of the rectangle it draws" {
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(0.0, 0.0))
    .line_to(@moonmath.Vec2::new(100.0, 0.0))
    .build()
  let style = @moongfx.Stroke::new(10.0)
  let triangles = @moongfx.stroke(path, style, flatten=@moongfx.standard)
  assert_true((total_area(triangles) - 1000.0).abs() < 1.0e-2)
}
