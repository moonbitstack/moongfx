// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What happens to a gradient parameter that falls outside the stop range.
#derive(Debug, Eq)
pub(all) enum Spread {
  /// Hold the first or last colour.
  Pad
  /// Start the ramp again, so the pattern tiles.
  Repeat
  /// Run the ramp backwards, so the pattern mirrors.
  Reflect
}

///|
/// A colour and where it sits along a gradient.
#derive(Debug)
pub(all) struct Stop {
  offset : Float
  color : @moonrgba.Color
}

///|
/// The colours of a gradient, shared by the linear and radial kinds.
#derive(Debug)
pub(all) struct Gradient {
  stops : Array[Stop]
  spread : Spread
}

///|
/// A gradient running from one point to another.
#derive(Debug)
pub(all) struct LinearGradient {
  from : Vec2
  to : Vec2
  ramp : Gradient
}

///|
/// A gradient running outwards from a circle: the colour at `t` is the one at
/// that fraction of the way from `focus` to the circle of `radius` about
/// `centre`, measured along the ray through the point.
#derive(Debug)
pub(all) struct RadialGradient {
  centre : Vec2
  radius : Float
  focus : Vec2
  ramp : Gradient
  /// Maps the gradient's own space to the space the fill is evaluated in, so that
  /// a circle under a skew becomes the ellipse it has to be.
  space : Affine2
}

///|
/// How an image is resampled when it is drawn larger or smaller than its pixels,
/// or through a transform.
#derive(Debug, Eq)
pub(all) enum Filter {
  /// The nearest texel: sharp, and the only choice that reproduces pixels exactly.
  Nearest
  /// A weighted average of the four neighbouring texels: smooth.
  Bilinear
}

///|
/// An image mapped through a transform, drawn as a fill.
pub(all) struct ImagePattern {
  image : @moonimage.Image
  /// Where the image's own pixel grid lands in the space the fill is evaluated in.
  transform : Affine2
  filter : Filter
}

///|
/// What colour a fill or a stroke puts down.
///
/// A paint carries no geometry of its own except the gradients' own points, which
/// are already in the space being drawn in: the canvas moves them with the path.
pub(all) enum Paint {
  Solid(@moonrgba.Color)
  Linear(LinearGradient)
  Radial(RadialGradient)
  Texture(ImagePattern)
}

///|
pub impl @debug.Debug for ImagePattern with fn to_repr(self) -> @debug.Repr {
  @debug.Repr::Repr(("image", self.image.width, self.image.height, self.filter))
}

///|
pub impl @debug.Debug for Paint with fn to_repr(self) -> @debug.Repr {
  match self {
    Solid(color) => @debug.Repr::Repr(("Solid", color))
    Linear(ramp) => @debug.Repr::Repr(("Linear", ramp))
    Radial(ramp) => @debug.Repr::Repr(("Radial", ramp))
    Texture(pattern) => @debug.Repr::Repr(("Texture", pattern))
  }
}

///|
/// A gradient between two colours, padded at both ends.
pub fn Gradient::two(from : @moonrgba.Color, to : @moonrgba.Color) -> Gradient {
  {
    stops: [{ offset: 0.0, color: from, }, { offset: 1.0, color: to, }],
    spread: Pad,
  }
}

///|
/// A radial gradient with the focus at the centre, which is the common case: the
/// colour runs outwards evenly.
pub fn radial(
  centre : Vec2,
  radius : Float,
  ramp : Gradient,
  focus? : Vec2,
  space~ : Affine2 = Affine2::identity(),
) -> Paint {
  Radial({ centre, radius, focus: focus.unwrap_or(centre), ramp, space, })
}

///|
/// A linear gradient between two points.
pub fn linear(from : Vec2, to : Vec2, ramp : Gradient) -> Paint {
  Linear({ from, to, ramp, })
}

///|
/// A gradient from a list of stops, sorted by offset so that a caller may pass
/// them in any order.
pub fn Gradient::new(stops : Array[Stop], spread~ : Spread = Pad) -> Gradient {
  let sorted = stops.copy()
  sorted.sort_by(fn(a : Stop, b : Stop) {
    if a.offset < b.offset {
      -1
    } else if a.offset > b.offset {
      1
    } else {
      0
    }
  })
  { stops: sorted, spread, }
}

///|
/// The colour of this gradient at `t`, with the spread applied.
pub fn Gradient::at(self : Gradient, t : Float) -> @moonrgba.Color {
  let count = self.stops.length()
  if count == 0 {
    return @moonrgba.Color::transparent()
  }
  if count == 1 {
    return self.stops[0].color
  }
  let mut value = t
  match self.spread {
    Pad => {
      if value < 0.0 {
        value = 0.0
      }
      if value > 1.0 {
        value = 1.0
      }
    }
    Repeat => {
      let span : Float = value - value.floor()
      value = if span < 0.0 { span + 1.0 } else { span }
    }
    Reflect => {
      // Every other turn of the ramp runs backwards, so the first turn's fraction
      // is mirrored when the turn number is odd.
      let turn = value.floor()
      let base : Float = value - turn
      let doubled = turn / 2.0
      let odd = turn - doubled.floor() * 2.0 != 0.0
      value = if odd { 1.0 - base } else { base }
    }
  }
  if value <= self.stops[0].offset {
    return self.stops[0].color
  }
  for i in 1..<count {
    let high = self.stops[i]
    if value <= high.offset {
      let low = self.stops[i - 1]
      let span = high.offset - low.offset
      let along : Float = if span <= 0.0 {
        0.0
      } else {
        (value - low.offset) / span
      }
      return mix(low.color, high.color, along)
    }
  }
  self.stops[count - 1].color
}

///|
/// A colour `t` of the way from `a` to `b`, in sRGB with straight alpha.
pub fn mix(
  a : @moonrgba.Color,
  b : @moonrgba.Color,
  t : Float,
) -> @moonrgba.Color {
  let (ar, ag, ab) = a.to_srgb().components()
  let (br, bg, bb) = b.to_srgb().components()
  let alpha = a.alpha + (b.alpha - a.alpha) * t.to_double()
  @moonrgba.Color::srgb(
    ar + (br - ar) * t.to_double(),
    ag + (bg - ag) * t.to_double(),
    ab + (bb - ab) * t.to_double(),
    alpha~,
  )
}

///|
/// A paint of one colour.
pub fn solid(color : @moonrgba.Color) -> Paint {
  Solid(color)
}

///|
/// The paint's colour at `p`, as straight sRGB channels and alpha, each from zero
/// to one.
///
/// This is the reference the backends implement; a GPU backend evaluates the same
/// expressions in a fragment shader.
pub fn Paint::sample(self : Paint, p : Vec2) -> (Float, Float, Float, Float) {
  match self {
    Solid(color) => {
      let (r, g, b) = color.to_srgb().components()
      (as_f32(r), as_f32(g), as_f32(b), as_f32(color.alpha))
    }
    Linear(gradient) => {
      let dx = gradient.to.x - gradient.from.x
      let dy = gradient.to.y - gradient.from.y
      let length = dx * dx + dy * dy
      let t : Float = if length <= 0.0 {
        0.0
      } else {
        ((p.x - gradient.from.x) * dx + (p.y - gradient.from.y) * dy) / length
      }
      color_tuple(gradient.ramp.at(if t < 0.0 { 0.0 } else { t }))
    }
    Radial(gradient) => {
      let placed = match gradient.space.inverse() {
        Some(inverse) => inverse.transform_point(p)
        None => return (0.0, 0.0, 0.0, 0.0)
      }
      color_tuple(gradient.ramp.at(radial_parameter(gradient, placed)))
    }
    Texture(pattern) => {
      let inverse = match pattern.transform.inverse() {
        Some(m) => m
        None => return (0.0, 0.0, 0.0, 0.0)
      }
      let placed = inverse.transform_point(p)
      let sample = sample_image(pattern.image, placed, pattern.filter)
      sample
    }
  }
}

///|
fn color_tuple(color : @moonrgba.Color) -> (Float, Float, Float, Float) {
  let (r, g, b) = color.to_srgb().components()
  (as_f32(r), as_f32(g), as_f32(b), as_f32(color.alpha))
}

///|
/// Where `p` falls along a radial gradient: zero at the focus, one on the circle.
fn radial_parameter(gradient : RadialGradient, p : Vec2) -> Float {
  let vx = p.x - gradient.focus.x
  let vy = p.y - gradient.focus.y
  let ux = gradient.focus.x - gradient.centre.x
  let uy = gradient.focus.y - gradient.centre.y
  let vv = vx * vx + vy * vy
  if vv <= 1.0e-12 {
    return 0.0
  }
  let uv = ux * vx + uy * vy
  let disc = uv * uv -
    vv * (ux * ux + uy * uy - gradient.radius * gradient.radius)
  if disc < 0.0 {
    return 1.0
  }
  let root = disc.sqrt()
  let denominator = -uv + root
  if denominator.abs() <= 1.0e-9 {
    return 1.0
  }
  vv / denominator
}

///|
/// The image's colour at a point in its own pixel space.
fn sample_image(
  image : @moonimage.Image,
  p : Vec2,
  filter : Filter,
) -> (Float, Float, Float, Float) {
  match filter {
    Nearest =>
      image_color(
        image,
        (p.x - 0.5).round().to_int(),
        (p.y - 0.5).round().to_int(),
      )
    Bilinear => {
      let x : Float = p.x - 0.5
      let y : Float = p.y - 0.5
      let x0 = x.floor()
      let y0 = y.floor()
      let fx = x - x0
      let fy = y - y0
      let ix = x0.to_int()
      let iy = y0.to_int()
      let c00 = image_color(image, ix, iy)
      let c10 = image_color(image, ix + 1, iy)
      let c01 = image_color(image, ix, iy + 1)
      let c11 = image_color(image, ix + 1, iy + 1)
      let w00 : Float = (1.0 - fx) * (1.0 - fy)
      let w10 : Float = fx * (1.0 - fy)
      let w01 : Float = (1.0 - fx) * fy
      let w11 : Float = fx * fy
      (
        c00.0 * w00 + c10.0 * w10 + c01.0 * w01 + c11.0 * w11,
        c00.1 * w00 + c10.1 * w10 + c01.1 * w01 + c11.1 * w11,
        c00.2 * w00 + c10.2 * w10 + c01.2 * w01 + c11.2 * w11,
        c00.3 * w00 + c10.3 * w10 + c01.3 * w01 + c11.3 * w11,
      )
    }
  }
}

///|
/// One texel as straight sRGB, clamped at the edges so a bilinear sample never
/// reads past the image.
fn image_color(
  image : @moonimage.Image,
  x : Int32,
  y : Int32,
) -> (Float, Float, Float, Float) {
  let width = image.width.to_int()
  let height = image.height.to_int()
  if width == 0 || height == 0 {
    return (0.0, 0.0, 0.0, 0.0)
  }
  let cx = if x < 0 { 0 } else if x >= width { width - 1 } else { x }
  let cy = if y < 0 { 0 } else if y >= height { height - 1 } else { y }
  let pixel = image.pixel(cx, cy) catch { _ => return (0.0, 0.0, 0.0, 0.0) }
  (as_f32(pixel.r), as_f32(pixel.g), as_f32(pixel.b), as_f32(pixel.a))
}
