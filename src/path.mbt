// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A circle arc kept as an arc rather than as a chain of curves, so that
/// flattening can place points exactly where the tolerance asks for them and
/// bounds come out exact.
///
/// `start` is the radian angle of the first point, measured from +x towards +y;
/// `sweep` is how far the arc turns, negative running the other way. A sweep of
/// a whole turn or more is legal and closes the arc on itself.
#derive(Debug, Eq)
pub(all) struct Arc {
  centre : Vec2
  radius : Float
  start : Float
  sweep : Float
}

///|
/// The point on the arc at `angle` radians.
pub fn Arc::point_at(self : Arc, angle : Float) -> Vec2 {
  Vec2::new(
    self.centre.x + self.radius * @math.cosf(angle),
    self.centre.y + self.radius * @math.sinf(angle),
  )
}

///|
/// The first point the arc passes through.
pub fn Arc::start_point(self : Arc) -> Vec2 {
  self.point_at(self.start)
}

///|
/// The last point the arc passes through.
pub fn Arc::end_point(self : Arc) -> Vec2 {
  self.point_at(self.start + self.sweep)
}

///|
/// One step of a path, in the order it was drawn.
#derive(Debug, Eq)
pub(all) enum PathEl {
  MoveTo(Vec2)
  LineTo(Vec2)
  /// The control point, then the end point.
  QuadTo(Vec2, Vec2)
  /// The two control points, then the end point.
  CubicTo(Vec2, Vec2, Vec2)
  Arc(Arc)
  Close
}

///|
/// A sequence of straight and curved steps, the unit every operation here takes.
///
/// Immutable: the builder produces one, and `transform` and the shape helpers
/// return new ones. Filling closes every subpath; stroking honours `Close`.
#derive(Debug)
pub(all) struct Path {
  els : Array[PathEl]
}

///|
/// The path with no steps in it.
pub fn Path::new() -> Path {
  { els: [], }
}

///|
/// The steps, in drawing order.
pub fn Path::elements(self : Path) -> Array[PathEl] {
  self.els
}

///|
/// Whether the path draws nothing.
pub fn Path::is_empty(self : Path) -> Bool {
  self.els.length() == 0
}

///|
/// A builder for a new path.
pub fn Path::builder() -> PathBuilder {
  { els: [], current: Vec2::zero(), start: Vec2::zero(), open: false, }
}

///|
/// Whether the transform keeps angles and scales both axes the same, which is
/// what lets a circular arc stay an arc instead of turning elliptical.
fn is_similarity(affine : Affine2) -> Bool {
  let c0 = affine.linear.c0
  let c1 = affine.linear.c1
  let s0 = c0.length()
  let s1 = c1.length()
  let scale = if s0 > s1 { s0 } else { s1 }
  let slack : Float = 1.0e-5 * (scale + 1.0)
  c0.dot(c1).abs() <= slack * (scale + 1.0) && (s0 - s1).abs() <= slack
}

///|
/// How many cubic steps a sweep needs so that no step covers more than a quarter
/// turn, which is where a cubic still fits a circular arc to within a thousandth.
fn quarter_turn_count(sweep : Float) -> Int32 {
  let turns : Float = sweep.abs() / (half_turn / 2.0)
  if turns <= 1.0 {
    1
  } else {
    let whole = turns.floor().to_int()
    if turns > as_float(whole) {
      whole + 1
    } else {
      whole
    }
  }
}

///|
/// The arc as cubic steps, the form an arbitrary affine transform can carry
/// without losing the shape.
fn arc_to_cubics(arc : Arc) -> Array[PathEl] {
  let out : Array[PathEl] = []
  let count = quarter_turn_count(arc.sweep)
  let delta : Float = arc.sweep / as_float(count)
  let k : Float = @math.tanf(delta / 4.0) * 4.0 / 3.0
  for i in 0..<count {
    let a0 : Float = arc.start + delta * as_float(i)
    let a1 : Float = a0 + delta
    let p0 = arc.point_at(a0)
    let p1 = arc.point_at(a1)
    let d0 = Vec2::new(-@math.sinf(a0), @math.cosf(a0)).scale(arc.radius * k)
    let d1 = Vec2::new(-@math.sinf(a1), @math.cosf(a1)).scale(arc.radius * k)
    out.push(CubicTo(p0 + d0, p1 - d1, p1))
  }
  out
}

///|
/// The path with every point run through `affine`.
///
/// Circular arcs stay arcs under a transform that only rotates, scales evenly
/// and moves; anything else — a skew, unequal scales — turns them into cubics
/// first, because an arc under such a transform is elliptical.
pub fn Path::transform(self : Path, affine : Affine2) -> Path {
  let out : Array[PathEl] = []
  let similar = is_similarity(affine)
  let c0 = affine.linear.c0
  let c1 = affine.linear.c1
  let uniform : Float = c0.length()
  let turn : Float = @math.atan2f(c0.y, c0.x)
  let mirrored = c0.cross(c1) < 0.0
  let mapped = fn(p : Vec2) { affine.transform_point(p) }
  for el in self.els {
    match el {
      MoveTo(p) => out.push(MoveTo(mapped(p)))
      LineTo(p) => out.push(LineTo(mapped(p)))
      QuadTo(c, p) => out.push(QuadTo(mapped(c), mapped(p)))
      CubicTo(a, b, p) => out.push(CubicTo(mapped(a), mapped(b), mapped(p)))
      Close => out.push(Close)
      Arc(a) =>
        if similar {
          out.push(
            Arc({
              centre: mapped(a.centre),
              radius: a.radius * uniform,
              start: if mirrored {
                turn - a.start
              } else {
                turn + a.start
              },
              sweep: if mirrored {
                -a.sweep
              } else {
                a.sweep
              },
            }),
          )
        } else {
          for cubic in arc_to_cubics(a) {
            match cubic {
              CubicTo(x, y, p) =>
                out.push(CubicTo(mapped(x), mapped(y), mapped(p)))
              _ => ()
            }
          }
        }
    }
  }
  { els: out, }
}

///|
/// The smallest box holding every point the path draws to.
///
/// Curves contribute their extrema, not just their end points, and arcs their
/// axis-aligned extremes, so the box is tight enough to size a clip or an atlas
/// cell against.
pub fn Path::bounds(self : Path) -> Bounds {
  let mut box = Bounds::nothing()
  let mut current = Vec2::zero()
  for el in self.els {
    match el {
      MoveTo(p) => current = p
      LineTo(p) => {
        box = box.add_point(current).add_point(p)
        current = p
      }
      QuadTo(c, p) => {
        box = quad_bounds(current, c, p, box)
        current = p
      }
      CubicTo(a, b, p) => {
        box = cubic_bounds(current, a, b, p, box)
        current = p
      }
      Arc(a) => {
        box = arc_bounds(a, box)
        current = a.end_point()
      }
      Close => ()
    }
  }
  box
}

///|
fn quad_bounds(p0 : Vec2, p1 : Vec2, p2 : Vec2, box : Bounds) -> Bounds {
  let mut out = box.add_point(p0).add_point(p2)
  let den_x : Float = p0.x - 2.0 * p1.x + p2.x
  if den_x.abs() > 1.0e-20 {
    let t : Float = (p0.x - p1.x) / den_x
    if t > 0.0 && t < 1.0 {
      out = out.add_point(quad_point(p0, p1, p2, t))
    }
  }
  let den_y : Float = p0.y - 2.0 * p1.y + p2.y
  if den_y.abs() > 1.0e-20 {
    let t : Float = (p0.y - p1.y) / den_y
    if t > 0.0 && t < 1.0 {
      out = out.add_point(quad_point(p0, p1, p2, t))
    }
  }
  out
}

///|
fn quad_point(p0 : Vec2, p1 : Vec2, p2 : Vec2, t : Float) -> Vec2 {
  let mt : Float = 1.0 - t
  Vec2::new(
    mt * mt * p0.x + 2.0 * mt * t * p1.x + t * t * p2.x,
    mt * mt * p0.y + 2.0 * mt * t * p1.y + t * t * p2.y,
  )
}

///|
fn cubic_point(p0 : Vec2, p1 : Vec2, p2 : Vec2, p3 : Vec2, t : Float) -> Vec2 {
  let mt : Float = 1.0 - t
  let a : Float = mt * mt * mt
  let b : Float = 3.0 * mt * mt * t
  let c : Float = 3.0 * mt * t * t
  let d : Float = t * t * t
  Vec2::new(
    a * p0.x + b * p1.x + c * p2.x + d * p3.x,
    a * p0.y + b * p1.y + c * p2.y + d * p3.y,
  )
}

///|
fn cubic_bounds(
  p0 : Vec2,
  p1 : Vec2,
  p2 : Vec2,
  p3 : Vec2,
  box : Bounds,
) -> Bounds {
  let mut out = box.add_point(p0).add_point(p3)
  for t in cubic_extrema(p0.x, p1.x, p2.x, p3.x) {
    if t > 0.0 && t < 1.0 {
      out = out.add_point(cubic_point(p0, p1, p2, p3, t))
    }
  }
  for t in cubic_extrema(p0.y, p1.y, p2.y, p3.y) {
    if t > 0.0 && t < 1.0 {
      out = out.add_point(cubic_point(p0, p1, p2, p3, t))
    }
  }
  out
}

///|
/// The parameters where one coordinate of a cubic turns around, from the roots
/// of its quadratic derivative.
fn cubic_extrema(
  v0 : Float,
  v1 : Float,
  v2 : Float,
  v3 : Float,
) -> Array[Float] {
  let out : Array[Float] = []
  // The derivative of the cubic, divided by three.
  let a : Float = -v0 + 3.0 * v1 - 3.0 * v2 + v3
  let b : Float = 2.0 * (v0 - 2.0 * v1 + v2)
  let c : Float = v1 - v0
  if a.abs() < 1.0e-20 {
    if b.abs() > 1.0e-20 {
      out.push(-c / b)
    }
    return out
  }
  let disc = b * b - 4.0 * a * c
  if disc < 0.0 {
    return out
  }
  let root : Float = disc.sqrt()
  out.push((-b + root) / (2.0 * a))
  out.push((-b - root) / (2.0 * a))
  out
}

///|
fn arc_bounds(arc : Arc, box : Bounds) -> Bounds {
  let mut out = box.add_point(arc.start_point()).add_point(arc.end_point())
  let step : Float = half_turn / 2.0
  let low : Float = if arc.sweep < 0.0 {
    arc.start + arc.sweep
  } else {
    arc.start
  }
  let high : Float = if arc.sweep < 0.0 {
    arc.start
  } else {
    arc.start + arc.sweep
  }
  let mut k = (low / step).ceil() * step
  while k <= high + 1.0e-5 {
    if k >= low - 1.0e-5 {
      out = out.add_point(arc.point_at(k))
    }
    k = k + step
  }
  out
}
