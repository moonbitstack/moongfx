// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The area the triangles cover.
fn shaded(triangles : Array[@moongfx.Triangle]) -> Double {
  let mut total : Double = 0.0
  for triangle in triangles {
    total = total + triangle.area().to_double().abs()
  }
  total
}

///|
/// A pentagram, whose sides cross each other, so the two fill rules disagree
/// about its middle.
fn main {
  let star = @moongfx.Path::builder()
    .move_to(@moonmath.Vec2::new(60.0, 20.0))
    .line_to(@moonmath.Vec2::new(100.0, 140.0))
    .line_to(@moonmath.Vec2::new(4.0, 62.0))
    .line_to(@moonmath.Vec2::new(116.0, 62.0))
    .line_to(@moonmath.Vec2::new(20.0, 140.0))
    .close()
    .build()
  let non_zero = @moongfx.fill(star, flatten=@moongfx.fine)
  let even_odd = @moongfx.fill(
    star,
    rule=@moongfx.EvenOdd,
    flatten=@moongfx.fine,
  )
  println("non-zero: \{non_zero.length()} triangles, area \{shaded(non_zero)}")
  println("even-odd: \{even_odd.length()} triangles, area \{shaded(even_odd)}")
  let ring = @moongfx.Path::builder()
    .circle(@moonmath.Vec2::new(0.0, 0.0), 40.0)
    .build()
  let hairline = @moongfx.stroke(ring, @moongfx.Stroke::new(2.0))
  let wide = @moongfx.stroke(ring, @moongfx.Stroke::new(12.0))
  println(
    "a hairline ring: \{hairline.length()} triangles, area \{shaded(hairline)}",
  )
  println("a wide ring: \{wide.length()} triangles, area \{shaded(wide)}")
  let dashed = @moongfx.stroke(
    ring,
    @moongfx.Stroke::new(6.0).with_dashes([12.0, 8.0]),
  )
  println("dashed: \{dashed.length()} triangles, area \{shaded(dashed)}")
}
