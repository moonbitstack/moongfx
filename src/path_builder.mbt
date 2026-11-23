// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How round each corner of a rounded rectangle is, in the order the corners are
/// named rather than the order they are drawn.
#derive(Debug, Eq)
pub(all) struct Corners {
  top_left : Float
  top_right : Float
  bottom_right : Float
  bottom_left : Float
}

///|
/// Every corner with the same radius.
pub fn Corners::same(radius : Float) -> Corners {
  {
    top_left: radius,
    top_right: radius,
    bottom_right: radius,
    bottom_left: radius,
  }
}

///|
/// Square corners.
pub fn Corners::none() -> Corners {
  Corners::same(0.0)
}

///|
/// A path under construction.
///
/// Every step returns the builder, so a path reads as one chain. A step that
/// draws needs somewhere to draw from: when the previous subpath was closed, or
/// nothing has been drawn yet, a `line_to` starts a new subpath at that point
/// instead of failing.
pub struct PathBuilder {
  els : Array[PathEl]
  mut current : Vec2
  mut start : Vec2
  mut open : Bool
}

///|
/// Start a new subpath at `p`.
pub fn PathBuilder::move_to(self : PathBuilder, p : Vec2) -> PathBuilder {
  self.els.push(MoveTo(p))
  self.current = p
  self.start = p
  self.open = true
  self
}

///|
/// Draw a straight line to `p`.
pub fn PathBuilder::line_to(self : PathBuilder, p : Vec2) -> PathBuilder {
  if !self.open {
    return self.move_to(p)
  }
  self.els.push(LineTo(p))
  self.current = p
  self
}

///|
/// Draw a quadratic curve to `p`, bending towards `control`.
pub fn PathBuilder::quad_to(
  self : PathBuilder,
  control : Vec2,
  p : Vec2,
) -> PathBuilder {
  if !self.open {
    let _ = self.move_to(self.current)
  }
  self.els.push(QuadTo(control, p))
  self.current = p
  self
}

///|
/// Draw a cubic curve to `p` with two control points.
pub fn PathBuilder::cubic_to(
  self : PathBuilder,
  control1 : Vec2,
  control2 : Vec2,
  p : Vec2,
) -> PathBuilder {
  if !self.open {
    let _ = self.move_to(self.current)
  }
  self.els.push(CubicTo(control1, control2, p))
  self.current = p
  self
}

///|
/// Close the current subpath with a straight line back to where it started.
pub fn PathBuilder::close(self : PathBuilder) -> PathBuilder {
  if self.open {
    self.els.push(Close)
    self.current = self.start
    self.open = false
  }
  self
}

///|
/// A circular arc from `start_angle` sweeping `sweep_angle` radians.
///
/// The arc starts where its own geometry says it does; when that is not the
/// current point the builder adds a line first, so a chain of arcs and lines
/// stays connected.
pub fn PathBuilder::arc(
  self : PathBuilder,
  centre : Vec2,
  radius : Float,
  start_angle : Float,
  sweep_angle : Float,
) -> PathBuilder {
  let arc = { centre, radius, start: start_angle, sweep: sweep_angle, }
  let first = arc.start_point()
  if !self.open || first.distance(self.current) > 1.0e-4 {
    let _ = self.move_to(first)
  }
  self.els.push(Arc(arc))
  self.current = arc.end_point()
  self
}

///|
/// An elliptical arc in the endpoint form SVG's `A` command uses.
///
/// `rx` and `ry` are the radii before rotation, `rotation` turns the ellipse in
/// radians, and `large_arc` and `sweep_flag` pick which of the four arcs through
/// the two end points is meant. A zero radius draws a straight line, as the
/// specification says. The arc reaches the end point already given, so the
/// builder does not add one.
pub fn PathBuilder::arc_to(
  self : PathBuilder,
  rx : Float,
  ry : Float,
  rotation : Float,
  large_arc : Bool,
  sweep_flag : Bool,
  p : Vec2,
) -> PathBuilder {
  if rx == 0.0 || ry == 0.0 {
    return self.line_to(p)
  }
  let from = self.current
  let rx = rx.abs().to_double()
  let ry = ry.abs().to_double()
  let (x1, y1) = (from.x.to_double(), from.y.to_double())
  let (x2, y2) = (p.x.to_double(), p.y.to_double())
  let phi = rotation.to_double()
  let cos_phi = @math.cos(phi)
  let sin_phi = @math.sin(phi)
  let dx = (x1 - x2) / 2.0
  let dy = (y1 - y2) / 2.0
  let x1p = cos_phi * dx + sin_phi * dy
  let y1p = -sin_phi * dx + cos_phi * dy
  let lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
  let (rx, ry) = if lambda > 1.0 {
    let grow = lambda.sqrt()
    (rx * grow, ry * grow)
  } else {
    (rx, ry)
  }
  let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
  let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
  let ratio = if denominator == 0.0 { 0.0 } else { numerator / denominator }
  let ratio = if ratio < 0.0 { 0.0 } else { ratio }
  let sign = if large_arc == sweep_flag { -1.0 } else { 1.0 }
  let coefficient = sign * ratio.sqrt()
  let cxp = coefficient * rx * y1p / ry
  let cyp = -coefficient * ry * x1p / rx
  let cx = cos_phi * cxp - sin_phi * cyp + (x1 + x2) / 2.0
  let cy = sin_phi * cxp + cos_phi * cyp + (y1 + y2) / 2.0
  let start_angle = @math.atan2((y1p - cyp) / ry, (x1p - cxp) / rx)
  let end_angle = @math.atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx)
  let mut sweep = end_angle - start_angle
  if !sweep_flag && sweep > 0.0 {
    sweep = sweep - 2.0 * @math.PI
  }
  if sweep_flag && sweep < 0.0 {
    sweep = sweep + 2.0 * @math.PI
  }
  let steps = quarter_turn_count(as_f32(sweep))
  let delta : Double = sweep / Int32::to_double(steps)
  let k = 4.0 / 3.0 * @math.tan(delta / 4.0)
  for i in 0..<steps {
    let a0 = start_angle + delta * i.to_double()
    let a1 = a0 + delta
    let p0 = ellipse_point(cx, cy, rx, ry, cos_phi, sin_phi, a0)
    let p1 = ellipse_point(cx, cy, rx, ry, cos_phi, sin_phi, a1)
    let d0 = ellipse_tangent(rx, ry, cos_phi, sin_phi, a0)
    let d1 = ellipse_tangent(rx, ry, cos_phi, sin_phi, a1)
    self.els.push(
      CubicTo(
        to_vec(p0.0 + d0.0 * k, p0.1 + d0.1 * k),
        to_vec(p1.0 - d1.0 * k, p1.1 - d1.1 * k),
        to_vec(p1.0, p1.1),
      ),
    )
  }
  self.els.push(LineTo(p))
  self.current = p
  self
}

///|
fn to_vec(x : Double, y : Double) -> Vec2 {
  Vec2::new(as_f32(x), as_f32(y))
}

///|
fn ellipse_point(
  cx : Double,
  cy : Double,
  rx : Double,
  ry : Double,
  cos_phi : Double,
  sin_phi : Double,
  angle : Double,
) -> (Double, Double) {
  let x = rx * @math.cos(angle)
  let y = ry * @math.sin(angle)
  (cx + cos_phi * x - sin_phi * y, cy + sin_phi * x + cos_phi * y)
}

///|
fn ellipse_tangent(
  rx : Double,
  ry : Double,
  cos_phi : Double,
  sin_phi : Double,
  angle : Double,
) -> (Double, Double) {
  let dx = -rx * @math.sin(angle)
  let dy = ry * @math.cos(angle)
  (cos_phi * dx - sin_phi * dy, sin_phi * dx + cos_phi * dy)
}

///|
/// A rectangle, drawn clockwise in the order the two corners are given.
pub fn PathBuilder::rect(self : PathBuilder, box : Bounds) -> PathBuilder {
  self
  .move_to(Vec2::new(box.min_x, box.min_y))
  .line_to(Vec2::new(box.max_x, box.min_y))
  .line_to(Vec2::new(box.max_x, box.max_y))
  .line_to(Vec2::new(box.min_x, box.max_y))
  .close()
}

///|
/// A rectangle with round corners, as CSS and SVG both define it: a radius is
/// clamped to half the shorter side, so an oversized radius gives a capsule
/// rather than an overlap.
pub fn PathBuilder::rounded_rect(
  self : PathBuilder,
  box : Bounds,
  corners : Corners,
) -> PathBuilder {
  let limit = (if box.width() < box.height() {
      box.width()
    } else {
      box.height()
    }) /
    2.0
  let clamp = fn(r : Float) -> Float {
    if r < 0.0 {
      0.0
    } else if r > limit {
      limit
    } else {
      r
    }
  }
  let tl = clamp(corners.top_left)
  let tr = clamp(corners.top_right)
  let br = clamp(corners.bottom_right)
  let bl = clamp(corners.bottom_left)
  let mut path = self.move_to(Vec2::new(box.min_x + tl, box.min_y))
  if tr > 0.0 {
    path = path
      .line_to(Vec2::new(box.max_x - tr, box.min_y))
      .arc(
        Vec2::new(box.max_x - tr, box.min_y + tr),
        tr,
        -half_turn / 2.0,
        half_turn / 2.0,
      )
  } else {
    path = path.line_to(Vec2::new(box.max_x, box.min_y))
  }
  if br > 0.0 {
    path = path
      .line_to(Vec2::new(box.max_x, box.max_y - br))
      .arc(Vec2::new(box.max_x - br, box.max_y - br), br, 0.0, half_turn / 2.0)
  } else {
    path = path.line_to(Vec2::new(box.max_x, box.max_y))
  }
  if bl > 0.0 {
    path = path
      .line_to(Vec2::new(box.min_x + bl, box.max_y))
      .arc(
        Vec2::new(box.min_x + bl, box.max_y - bl),
        bl,
        half_turn / 2.0,
        half_turn / 2.0,
      )
  } else {
    path = path.line_to(Vec2::new(box.min_x, box.max_y))
  }
  if tl > 0.0 {
    path = path
      .line_to(Vec2::new(box.min_x, box.min_y + tl))
      .arc(
        Vec2::new(box.min_x + tl, box.min_y + tl),
        tl,
        half_turn,
        half_turn / 2.0,
      )
  } else {
    path = path.line_to(Vec2::new(box.min_x, box.min_y))
  }
  path.close()
}

///|
/// A full circle, drawn anticlockwise from its rightmost point.
pub fn PathBuilder::circle(
  self : PathBuilder,
  centre : Vec2,
  radius : Float,
) -> PathBuilder {
  self
  .move_to(Vec2::new(centre.x + radius, centre.y))
  .arc(centre, radius, 0.0, full_turn)
  .close()
}

///|
/// An ellipse, as four cubic steps of three quarters of a turn each.
pub fn PathBuilder::ellipse(
  self : PathBuilder,
  centre : Vec2,
  radius_x : Float,
  radius_y : Float,
) -> PathBuilder {
  let kappa : Float = 0.5522847498307936
  let kx : Float = radius_x * kappa
  let ky : Float = radius_y * kappa
  let (cx, cy) = (centre.x, centre.y)
  self
  .move_to(Vec2::new(cx + radius_x, cy))
  .cubic_to(
    Vec2::new(cx + radius_x, cy + ky),
    Vec2::new(cx + kx, cy + radius_y),
    Vec2::new(cx, cy + radius_y),
  )
  .cubic_to(
    Vec2::new(cx - kx, cy + radius_y),
    Vec2::new(cx - radius_x, cy + ky),
    Vec2::new(cx - radius_x, cy),
  )
  .cubic_to(
    Vec2::new(cx - radius_x, cy - ky),
    Vec2::new(cx - kx, cy - radius_y),
    Vec2::new(cx, cy - radius_y),
  )
  .cubic_to(
    Vec2::new(cx + kx, cy - radius_y),
    Vec2::new(cx + radius_x, cy - ky),
    Vec2::new(cx + radius_x, cy),
  )
  .close()
}

///|
/// A chain of straight lines through `points`.
pub fn PathBuilder::polyline(
  self : PathBuilder,
  points : Array[Vec2],
  closed~ : Bool = false,
) -> PathBuilder {
  if points.length() == 0 {
    return self
  }
  let mut path = self.move_to(points[0])
  for i in 1..<points.length() {
    path = path.line_to(points[i])
  }
  if closed {
    path = path.close()
  }
  path
}

///|
/// Add every step of `path`, so one path can be built from several.
pub fn PathBuilder::append(self : PathBuilder, path : Path) -> PathBuilder {
  let open = self.open
  for el in path.els {
    match el {
      MoveTo(p) => {
        self.els.push(MoveTo(p))
        self.current = p
        self.start = p
        self.open = true
      }
      LineTo(_) | QuadTo(_, _) | CubicTo(_, _, _) | Arc(_) as el => {
        self.els.push(el)
        self.current = match el {
          LineTo(p) => p
          QuadTo(_, p) => p
          CubicTo(_, _, p) => p
          Arc(a) => a.end_point()
          _ => self.current
        }
      }
      Close => {
        self.els.push(Close)
        self.current = self.start
        self.open = false
      }
    }
  }
  if open && !self.open {
    self.open = true
  }
  self
}

///|
/// The finished path. The builder must not be used afterwards.
pub fn PathBuilder::build(self : PathBuilder) -> Path {
  { els: self.els, }
}
