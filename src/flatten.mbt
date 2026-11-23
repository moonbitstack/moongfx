// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How far a flattened curve may sit from the curve it replaces, in the units of
/// the coordinates the path holds.
///
/// The presets below are the ones to reach for: a quarter of a pixel looks smooth
/// at normal scale, half a pixel is enough for a preview, and five hundredths is
/// for output that is looked at closely.
#derive(Debug, Eq)
pub(all) struct Flatten {
  tolerance : Float
}

///|
/// Half a pixel: for previews and thumbnails.
pub let coarse : Flatten = { tolerance: 0.5, }

///|
/// A quarter of a pixel: the default, and smooth at normal scale.
pub let standard : Flatten = { tolerance: 0.25, }

///|
/// A twentieth of a pixel: for large output, where a quarter would show.
pub let fine : Flatten = { tolerance: 0.05, }

///|
/// A tolerance of your own, in the same units as the coordinates.
pub fn Flatten::new(tolerance : Float) -> Flatten {
  if tolerance > 0.0 {
    { tolerance, }
  } else {
    standard
  }
}

///|
/// One subpath, flattened into the straight segments a tessellator or a
/// rasteriser works on.
///
/// `closed` is what the writer said, not what filling does: filling closes every
/// contour, stroking leaves an open one open so it gets caps.
#derive(Debug)
pub(all) struct Contour {
  points : Array[Vec2]
  closed : Bool
}

///|
/// The points, in drawing order.
pub fn Contour::points(self : Contour) -> Array[Vec2] {
  self.points
}

///|
/// Whether the subpath was closed.
pub fn Contour::is_closed(self : Contour) -> Bool {
  self.closed
}

///|
/// The number of points.
pub fn Contour::length(self : Contour) -> Int32 {
  self.points.length()
}

///|
/// The deepest a curve is split, as a guard against a tolerance so small that
/// subdivision would never end.
let max_subdivision : Int32 = 24

///|
/// The path as polygons, one per subpath, each within `flatten.tolerance` of the
/// curve it replaces.
///
/// Straight steps and arcs are exact — an arc is stepped by the angle its radius
/// allows — and quadratics and cubics are split until their control points sit
/// within the tolerance of the chord.
pub fn Path::flatten(
  self : Path,
  flatten~ : Flatten = standard,
) -> Array[Contour] {
  let contours : Array[Contour] = []
  let mut points : Array[Vec2] = []
  let mut current = Vec2::zero()
  let mut open = false
  let tolerance = flatten.tolerance
  for el in self.els {
    match el {
      MoveTo(p) => {
        if open && points.length() > 0 {
          contours.push({ points, closed: false, })
          points = []
        }
        points.push(p)
        current = p
        open = true
      }
      LineTo(p) => {
        if !open {
          points.push(p)
          open = true
        } else {
          points.push(p)
        }
        current = p
      }
      QuadTo(c, p) => {
        flatten_quad(current, c, p, tolerance, 0, points)
        current = p
      }
      CubicTo(a, b, p) => {
        flatten_cubic(current, a, b, p, tolerance, 0, points)
        current = p
      }
      Arc(a) => {
        flatten_arc(a, tolerance, points)
        current = a.end_point()
      }
      Close => {
        if points.length() > 0 {
          contours.push({ points, closed: true, })
        }
        points = []
        open = false
      }
    }
  }
  if points.length() > 0 {
    contours.push({ points, closed: false, })
  }
  contours
}

///|
fn flatten_quad(
  p0 : Vec2,
  p1 : Vec2,
  p2 : Vec2,
  tolerance : Float,
  depth : Int32,
  out : Array[Vec2],
) -> Unit {
  if depth >= max_subdivision || !off_line(p1, p0, p2, tolerance) {
    out.push(p2)
    return
  }
  let a = lerp(p0, p1, 0.5)
  let b = lerp(p1, p2, 0.5)
  let middle = lerp(a, b, 0.5)
  flatten_quad(p0, a, middle, tolerance, depth + 1, out)
  flatten_quad(middle, b, p2, tolerance, depth + 1, out)
}

///|
fn flatten_cubic(
  p0 : Vec2,
  p1 : Vec2,
  p2 : Vec2,
  p3 : Vec2,
  tolerance : Float,
  depth : Int32,
  out : Array[Vec2],
) -> Unit {
  let flat = !off_line(p1, p0, p3, tolerance) &&
    !off_line(p2, p0, p3, tolerance)
  if depth >= max_subdivision || flat {
    out.push(p3)
    return
  }
  let p01 = lerp(p0, p1, 0.5)
  let p12 = lerp(p1, p2, 0.5)
  let p23 = lerp(p2, p3, 0.5)
  let p012 = lerp(p01, p12, 0.5)
  let p123 = lerp(p12, p23, 0.5)
  let middle = lerp(p012, p123, 0.5)
  flatten_cubic(p0, p01, p012, middle, tolerance, depth + 1, out)
  flatten_cubic(middle, p123, p23, p3, tolerance, depth + 1, out)
}

///|
/// The angle between two points of an arc of radius `radius` that keeps the
/// chord within `tolerance` of the arc.
fn arc_step(radius : Float, tolerance : Float) -> Float {
  if radius <= tolerance {
    return half_turn / 2.0
  }
  let cosine : Float = 1.0 - tolerance / radius
  let step : Float = 2.0 *
    @math.acosf(
      if cosine < -1.0 {
        -1.0
      } else if cosine > 1.0 {
        1.0
      } else {
        cosine
      },
    )
  if step > half_turn / 2.0 {
    half_turn / 2.0
  } else if step < 1.0e-3 {
    1.0e-3
  } else {
    step
  }
}

///|
fn flatten_arc(arc : Arc, tolerance : Float, out : Array[Vec2]) -> Unit {
  let step = arc_step(arc.radius, tolerance)
  let count = (arc.sweep.abs() / step).ceil().to_int()
  let count = if count < 1 { 1 } else { count }
  let delta = arc.sweep / as_float(count)
  for i in 1..<=count {
    out.push(arc.point_at(arc.start + delta * as_float(i)))
  }
}
