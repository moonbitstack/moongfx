// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The two triangles that cover a box.
fn box_triangles(
  x : Float,
  y : Float,
  w : Float,
  h : Float,
) -> Array[@moongfx.Triangle] {
  let a = @moonmath.Vec2::new(x, y)
  let b = @moonmath.Vec2::new(x + w, y)
  let c = @moonmath.Vec2::new(x + w, y + h)
  let d = @moonmath.Vec2::new(x, y + h)
  [{ a, b, c, }, { a, b: c, c: d, }]
}

///|
test "a covered pixel reads full coverage" {
  let mask = @moongfx.rasterize(box_triangles(0.0, 0.0, 10.0, 10.0), 10, 10)
  assert_eq(mask.at(5, 5), 255)
  assert_eq(mask.at(0, 0), 255)
  assert_eq(mask.at(9, 9), 255)
  assert_eq(mask.width(), 10)
}

///|
test "a pixel reached halfway reads about half" {
  // A box from y = 0 to y = 0.5 covers the top half of the first row.
  let mask = @moongfx.rasterize(box_triangles(0.0, 0.0, 8.0, 0.5), 8, 2)
  let value = mask.at(4, 0)
  assert_true(value > 110 && value < 145)
  assert_eq(mask.at(4, 1), 0)
}

///|
test "two triangles that share an edge leave no seam" {
  // A square split along its diagonal: the pixel the diagonal crosses must come
  // out at full coverage, not at twice half or at one half.
  let mask = @moongfx.rasterize(box_triangles(0.0, 0.0, 16.0, 16.0), 16, 16)
  for i in 0..<16 {
    assert_eq(mask.at(i, i), 255)
  }
}

///|
test "a mask can be intersected with another" {
  let wide = @moongfx.rasterize(box_triangles(0.0, 0.0, 10.0, 10.0), 10, 10)
  let narrow = @moongfx.rasterize(box_triangles(0.0, 0.0, 5.0, 10.0), 10, 10)
  let both = wide.intersect(narrow)
  assert_eq(both.at(2, 5), 255)
  assert_eq(both.at(8, 5), 0)
}

///|
test "the intersection of two half-covered pixels is a quarter" {
  let top = @moongfx.rasterize(box_triangles(0.0, 0.0, 8.0, 0.5), 8, 2)
  let left = @moongfx.rasterize(box_triangles(0.0, 0.0, 0.5, 2.0), 8, 2)
  let both = top.intersect(left)
  // Half across and half down is a quarter of the pixel.
  assert_true(both.at(0, 0) > 55 && both.at(0, 0) < 75)
}

///|
test "geometry outside the mask is dropped rather than wrapped" {
  let mask = @moongfx.rasterize(box_triangles(-20.0, -20.0, 40.0, 10.0), 8, 8)
  assert_eq(mask.at(4, 4), 0)
  assert_eq(mask.at(-1, 4), 0)
  assert_eq(mask.at(4, 100), 0)
}

///|
test "an empty triangle list gives an empty mask" {
  let mask = @moongfx.rasterize([], 4, 4)
  assert_eq(mask.at(0, 0), 0)
  assert_eq(mask.data.length(), 16)
}
