// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Three corners, the shape every backend takes.
///
/// Winding is not part of the contract: a backend fills the triangle either way,
/// so a tessellator may emit both orientations in one path.
#derive(Debug)
pub(all) struct Triangle {
  a : Vec2
  b : Vec2
  c : Vec2
}

///|
/// The signed area, positive when the corners run anticlockwise in a space whose
/// y axis points up.
pub fn Triangle::area(self : Triangle) -> Float {
  (cross(self.a, self.b) + cross(self.b, self.c) + cross(self.c, self.a)) / 2.0
}

///|
/// The box the three corners span.
pub fn Triangle::bounds(self : Triangle) -> Bounds {
  Bounds::nothing().add_point(self.a).add_point(self.b).add_point(self.c)
}

///|
/// Which points count as inside a path that crosses itself.
#derive(Debug, Eq)
pub(all) enum FillRule {
  /// A point is inside when the path winds round it a non-zero number of times.
  NonZero
  /// A point is inside when a ray from it crosses the path an odd number of times.
  EvenOdd
}

///|
/// An edge of the flattened path, held in double precision because the sweep
/// compares crossings that can differ in the last few bits.
priv struct Edge {
  x0 : Double
  y0 : Double
  x1 : Double
  y1 : Double
  /// Positive when the edge runs down the page, so that summing these along a
  /// scanline gives the winding number.
  winding : Int32
}

///|
/// Where one edge crosses a slab.
priv struct Crossing {
  /// The x where the edge enters the slab, at its lower y.
  bottom : Double
  /// The x where the edge leaves the slab, at its upper y.
  top : Double
  /// The x in the middle of the slab, used to order the crossings.
  middle : Double
  winding : Int32
}

///|
fn Edge::x_at(self : Edge, y : Double) -> Double {
  self.x0 + (y - self.y0) * (self.x1 - self.x0) / (self.y1 - self.y0)
}

///|
fn compare_double(a : Double, b : Double) -> Int32 {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
/// The y where two edges cross, when they do so away from their own ends.
fn crossing_height(a : Edge, b : Edge) -> Double? {
  if a.y1 <= b.y0 || b.y1 <= a.y0 {
    return None
  }
  let ax = a.x1 - a.x0
  let ay = a.y1 - a.y0
  let bx = b.x1 - b.x0
  let by = b.y1 - b.y0
  let denominator = ax * by - ay * bx
  if denominator.abs() <= 1.0e-12 {
    return None
  }
  let dx = b.x0 - a.x0
  let dy = b.y0 - a.y0
  let t = (dx * by - dy * bx) / denominator
  let u = (dx * ay - dy * ax) / denominator
  if t <= 0.0 || t >= 1.0 || u <= 0.0 || u >= 1.0 {
    return None
  }
  Some(a.y0 + ay * t)
}

///|
/// The path filled under `rule`, as triangles that cover exactly the inside.
///
/// The flattening is the one filling needs: every subpath counts as closed. The
/// output never overlaps itself — the plane is cut into horizontal slabs at every
/// vertex, and each slab is filled by walking its crossings in order — so a
/// backend can draw the triangles one by one without blending twice.
pub fn fill(
  path : Path,
  rule~ : FillRule = NonZero,
  flatten~ : Flatten = standard,
) -> Array[Triangle] {
  fill_contours(path.flatten(flatten~), rule)
}

///|
/// The polygons filled under `rule`. Filling closes every contour, whatever its
/// own flag says.
pub fn fill_contours(
  contours : Array[Contour],
  rule : FillRule,
) -> Array[Triangle] {
  let edges : Array[Edge] = []
  for contour in contours {
    let points = contour.points
    let count = points.length()
    if count < 2 {
      continue
    }
    for i in 0..<count {
      let p = points[i]
      let q = points[(i + 1) % count]
      if p.y == q.y {
        continue
      }
      let downward = q.y > p.y
      edges.push({
        x0: as_f64(if downward { p.x } else { q.x }),
        y0: as_f64(if downward { p.y } else { q.y }),
        x1: as_f64(if downward { q.x } else { p.x }),
        y1: as_f64(if downward { q.y } else { p.y }),
        winding: if downward {
          1
        } else {
          -1
        },
      })
    }
  }
  if edges.length() == 0 {
    return []
  }
  let levels : Array[Double] = []
  for edge in edges {
    levels.push(edge.y0)
    levels.push(edge.y1)
  }
  // Two edges that cross inside a slab would swap places in the middle of it, and
  // the trapezoid the slab produces would be a bow tie. Splitting the plane at
  // every crossing keeps the order of the crossings constant within a slab, which
  // is what makes the fill of a self-crossing path exact.
  for i in 0..<edges.length() {
    for j in (i + 1)..<edges.length() {
      match crossing_height(edges[i], edges[j]) {
        Some(y) => levels.push(y)
        None => ()
      }
    }
  }
  levels.sort()
  let ys : Array[Double] = []
  for y in levels {
    if ys.length() == 0 || ys[ys.length() - 1] != y {
      ys.push(y)
    }
  }
  edges.sort_by(fn(a : Edge, b : Edge) {
    let by_low = compare_double(a.y0, b.y0)
    if by_low != 0 {
      by_low
    } else {
      compare_double(a.y1, b.y1)
    }
  })
  let out : Array[Triangle] = []
  let mut active : Array[Int32] = []
  let mut next = 0
  for i in 0..<(ys.length() - 1) {
    let low = ys[i]
    let high = ys[i + 1]
    if high <= low {
      continue
    }
    while next < edges.length() && edges[next].y0 < high {
      active.push(next)
      next = next + 1
    }
    let kept : Array[Int32] = []
    for index in active {
      if edges[index].y1 > low {
        kept.push(index)
      }
    }
    active = kept
    if active.length() < 2 {
      continue
    }
    let middle = (low + high) / 2.0
    let crossings : Array[Crossing] = []
    for index in active {
      let edge = edges[index]
      crossings.push({
        bottom: edge.x_at(low),
        top: edge.x_at(high),
        middle: edge.x_at(middle),
        winding: edge.winding,
      })
    }
    crossings.sort_by(fn(a : Crossing, b : Crossing) {
      compare_double(a.middle, b.middle)
    })
    let mut wound = 0
    let mut parity = 0
    for k in 0..<crossings.length() {
      wound = wound + crossings[k].winding
      parity = 1 - parity
      if k + 1 >= crossings.length() {
        break
      }
      let inside = if rule == NonZero { wound != 0 } else { parity != 0 }
      if !inside {
        continue
      }
      let left = crossings[k]
      let right = crossings[k + 1]
      if left.bottom >= right.bottom && left.top >= right.top {
        continue
      }
      let bottom_left = Vec2::new(as_f32(left.bottom), as_f32(low))
      let bottom_right = Vec2::new(as_f32(right.bottom), as_f32(low))
      let top_left = Vec2::new(as_f32(left.top), as_f32(high))
      let top_right = Vec2::new(as_f32(right.top), as_f32(high))
      out.push({ a: bottom_left, b: bottom_right, c: top_right, })
      out.push({ a: bottom_left, b: top_right, c: top_left, })
    }
  }
  out
}
