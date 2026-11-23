// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A card with a rounded panel, a circle and a ring, drawn into the software
/// frame buffer and then read back pixel by pixel.
fn main {
  let surface = @soft.Surface::new(240, 160)
  let canvas = @moongfx.Canvas::new(surface)
  canvas.clear(@moonrgba.Color::rgb(250, 248, 244))
  canvas.fill_rounded_rect(
    { min_x: 16.0, min_y: 16.0, max_x: 224.0, max_y: 144.0, },
    @moongfx.Corners::same(18.0),
    @moongfx.solid(@moonrgba.Color::rgb(40, 44, 60)),
  )
  canvas.fill_circle(
    @moonmath.Vec2::new(70.0, 80.0),
    38.0,
    @moongfx.solid(@moonrgba.Color::rgb(230, 90, 80)),
  )
  canvas.stroke_circle(
    @moonmath.Vec2::new(160.0, 80.0),
    36.0,
    @moongfx.Stroke::new(10.0).with_join(@moongfx.Round),
    @moongfx.solid(@moonrgba.Color::rgb(90, 190, 170)),
  )
  let (r, g, b, a) = surface.pixel(70, 80)
  println("the filled circle is red: \{r} \{g} \{b}, opaque: \{a}")
  let (_, _, _, ring) = surface.pixel(160, 44)
  println("the ring's top edge: \{ring}")
  let (_, _, _, panel) = surface.pixel(30, 30)
  println("the panel's rounded corner: \{panel}")
  let (_, _, _, outside) = surface.pixel(4, 4)
  println("outside the panel, the cleared background: \{outside}")
}
