// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How many times the contours wind round `p`, counted by the crossings of a ray
/// going right. This is the definition the fill rule is written in, worked out
/// independently of the tessellator.
fn winding_at(contours : Array[@moongfx.Contour], p : @moonmath.Vec2) -> Int32 {
  let mut winding = 0
  for contour in contours {
    let points = contour.points()
    let count = points.length()
    if count < 2 {
      continue
    }
    for i in 0..<count {
      let a = points[i]
      let b = points[(i + 1) % count]
      let side = (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)
      if a.y <= p.y {
        if b.y > p.y && side > 0.0 {
          winding = winding + 1
        }
      } else if b.y <= p.y && side < 0.0 {
        winding = winding - 1
      }
    }
  }
  winding
}

///|
/// Whether the winding test says the point is inside under `rule`.
fn inside_by_winding(
  contours : Array[@moongfx.Contour],
  p : @moonmath.Vec2,
  rule : @moongfx.FillRule,
) -> Bool {
  let winding = winding_at(contours, p)
  match rule {
    NonZero => winding != 0
    EvenOdd => winding % 2 != 0
  }
}

///|
/// Whether any triangle covers the point, by the signed areas of the three
/// sub-triangles.
fn covered_by(triangles : Array[@moongfx.Triangle], p : @moonmath.Vec2) -> Bool {
  for triangle in triangles {
    // A triangle with no area covers nothing, and every point reads as inside it
    // by the sign test; the sweepline produces them where a slab pinches out.
    if triangle.area().abs() < 1.0e-6 {
      continue
    }
    if inside_triangle(triangle, p) {
      return true
    }
  }
  false
}

///|
fn inside_triangle(triangle : @moongfx.Triangle, p : @moonmath.Vec2) -> Bool {
  let d1 = (p.x - triangle.b.x) * (triangle.a.y - triangle.b.y) -
    (triangle.a.x - triangle.b.x) * (p.y - triangle.b.y)
  let d2 = (p.x - triangle.c.x) * (triangle.b.y - triangle.c.y) -
    (triangle.b.x - triangle.c.x) * (p.y - triangle.c.y)
  let d3 = (p.x - triangle.a.x) * (triangle.c.y - triangle.a.y) -
    (triangle.c.x - triangle.a.x) * (p.y - triangle.a.y)
  let negative = d1 < 0.0 || d2 < 0.0 || d3 < 0.0
  let positive = d1 > 0.0 || d2 > 0.0 || d3 > 0.0
  !(negative && positive)
}

///|
/// The share of a grid of sample points where the triangles and the winding test
/// disagree about what is inside.
fn agreement(path : @moongfx.Path, rule : @moongfx.FillRule) -> Double {
  let contours = path.flatten(flatten=@moongfx.Flatten::new(0.05))
  let triangles = @moongfx.fill(
    path,
    rule~,
    flatten=@moongfx.Flatten::new(0.05),
  )
  let box = path.bounds().expand(2.0)
  let steps = 16
  let step_x = box.width() / as_turn(steps)
  let step_y = box.height() / as_turn(steps)
  let mut agree = 0
  let mut total = 0
  for iy in 0..<steps {
    for ix in 0..<steps {
      // An offset of a third of a step keeps the samples off the vertices, where
      // both tests would be answering a question about a boundary rather than
      // about the inside.
      let p = @moonmath.Vec2::new(
        box.min_x + (as_turn(ix) + 0.37) * step_x,
        box.min_y + (as_turn(iy) + 0.37) * step_y,
      )
      let by_winding = inside_by_winding(contours, p, rule)
      let by_triangles = covered_by(triangles, p)
      if by_winding == by_triangles {
        agree = agree + 1
      }
      total = total + 1
    }
  }
  Int32::to_double(agree) / Int32::to_double(total)
}

///|
fn as_turn(n : Int32) -> Float {
  Float::from_double(Int32::to_double(n))
}

///|
test "the triangles of a pentagram agree with the winding rule" {
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(60.0, 20.0))
    .line_to(@moonmath.Vec2::new(100.0, 140.0))
    .line_to(@moonmath.Vec2::new(4.0, 62.0))
    .line_to(@moonmath.Vec2::new(116.0, 62.0))
    .line_to(@moonmath.Vec2::new(20.0, 140.0))
    .close()
    .build()
  assert_true(agreement(path, @moongfx.NonZero) > 0.995)
  assert_true(agreement(path, @moongfx.EvenOdd) > 0.995)
}

///|
test "the two rules disagree about a pentagram's middle" {
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(60.0, 20.0))
    .line_to(@moonmath.Vec2::new(100.0, 140.0))
    .line_to(@moonmath.Vec2::new(4.0, 62.0))
    .line_to(@moonmath.Vec2::new(116.0, 62.0))
    .line_to(@moonmath.Vec2::new(20.0, 140.0))
    .close()
    .build()
  let mut non_zero : Double = 0.0
  let mut even_odd : Double = 0.0
  for
    triangle in @moongfx.fill(
      path,
      rule=@moongfx.NonZero,
      flatten=@moongfx.fine,
    ) {
    non_zero = non_zero + triangle.area().to_double().abs()
  }
  for
    triangle in @moongfx.fill(
      path,
      rule=@moongfx.EvenOdd,
      flatten=@moongfx.fine,
    ) {
    even_odd = even_odd + triangle.area().to_double().abs()
  }
  // The middle pentagon is counted twice by the winding rule and not at all by
  // the even-odd one, so the even-odd area is smaller but not empty.
  assert_true(even_odd < non_zero * 0.95)
  assert_true(even_odd > non_zero * 0.5)
}

///|
test "a ring keeps its hole under both rules when the contours run opposite ways" {
  let path = @moongfx.Path::builder()
    .circle(@moonmath.Vec2::new(50.0, 50.0), 40.0)
    .move_to(@moonmath.Vec2::new(70.0, 50.0))
    .arc(@moonmath.Vec2::new(50.0, 50.0), 20.0, 0.0, -6.283185307179586)
    .close()
    .build()
  let non_zero = agreement(path, @moongfx.NonZero)
  let even_odd = agreement(path, @moongfx.EvenOdd)
  println("ring: non-zero \{non_zero}, even-odd \{even_odd}")
  assert_true(non_zero > 0.995)
  assert_true(even_odd > 0.995)
}

///|
test "a bow tie agrees with the winding rule" {
  let path = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(10.0, 10.0))
    .line_to(@moonmath.Vec2::new(90.0, 70.0))
    .line_to(@moonmath.Vec2::new(10.0, 70.0))
    .line_to(@moonmath.Vec2::new(90.0, 10.0))
    .close()
    .build()
  assert_true(agreement(path, @moongfx.NonZero) > 0.99)
  assert_true(agreement(path, @moongfx.EvenOdd) > 0.99)
}
