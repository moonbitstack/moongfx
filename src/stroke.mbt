// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How the outer side of a corner is filled in.
#derive(Debug, Eq)
pub(all) enum Join {
  /// Carry both edges on to where they meet; a corner sharper than
  /// `miter_limit` falls back to `Bevel` rather than shooting off the page.
  Miter
  /// Cut the corner off with a straight edge.
  Bevel
  /// Turn the corner with an arc of the stroke's own radius.
  Round
}

///|
/// How an open end of a stroke finishes.
#derive(Debug, Eq)
pub(all) enum Cap {
  /// Stop at the last point.
  Butt
  /// Turn the end with a half circle.
  Round
  /// Carry the stroke half a width past the last point and cut it square.
  Square
}

///|
/// Everything about how a path is stroked: the width, what happens at corners
/// and ends, the miter limit that stops a sharp corner running away, and an
/// optional dash pattern.
///
/// `Stroke::new(width)` gives the common case — miter joins up to the usual
/// limit of four, butt caps, no dashes — and the `with_` methods change one thing
/// at a time.
#derive(Debug)
pub(all) struct Stroke {
  width : Float
  join : Join
  cap : Cap
  miter_limit : Float
  /// Lengths alternating on and off, starting with on. Empty means a solid line.
  dash : Array[Float]
  /// How far into the pattern the first point sits.
  dash_offset : Float
  /// How far a flattened curve may sit from the curve, in drawing units.
  tolerance : Float
}

///|
/// A solid stroke of `width`, miter joins limited to four, butt caps.
pub fn Stroke::new(width : Float) -> Stroke {
  {
    width,
    join: Miter,
    cap: Butt,
    miter_limit: 4.0,
    dash: [],
    dash_offset: 0.0,
    tolerance: 0.25,
  }
}

///|
/// The same stroke with a different corner.
pub fn Stroke::with_join(self : Stroke, join : Join) -> Stroke {
  { ..self, join, }
}

///|
/// The same stroke with a different end.
pub fn Stroke::with_cap(self : Stroke, cap : Cap) -> Stroke {
  { ..self, cap, }
}

///|
/// The same stroke with a different miter limit: the ratio of miter length to
/// width above which a corner is bevelled instead.
pub fn Stroke::with_miter_limit(self : Stroke, limit : Float) -> Stroke {
  { ..self, miter_limit: limit, }
}

///|
/// The same stroke, dashed. The pattern alternates on and off lengths starting
/// with on; an odd-length pattern repeats with the first length carried over.
pub fn Stroke::with_dashes(
  self : Stroke,
  pattern : Array[Float],
  offset~ : Float = 0.0,
) -> Stroke {
  { ..self, dash: pattern, dash_offset: offset, }
}

///|
/// The same stroke, flattening its curves to `flatten`'s tolerance.
pub fn Stroke::with_tolerance(self : Stroke, flatten : Flatten) -> Stroke {
  { ..self, tolerance: flatten.tolerance, }
}

///|
/// The normal to `d`, turned a quarter anticlockwise.
fn perp(d : Vec2) -> Vec2 {
  Vec2::new(-d.y, d.x)
}

///|
/// Points closer than this count as the same point. An arc's last point is only
/// equal to its first to within the float error of a sine, and a segment a few
/// millionths of a pixel long has no direction worth using.
let coincident : Float = 1.0e-4

///|
/// The points without the repeats that would make a zero-length segment, and
/// without a closing point that merely repeats the first.
fn clean_points(points : Array[Vec2], closed : Bool) -> Array[Vec2] {
  let kept : Array[Vec2] = []
  for p in points {
    let repeated = if kept.length() == 0 {
      false
    } else {
      kept[kept.length() - 1].distance_squared(p) <= coincident * coincident
    }
    if !repeated {
      kept.push(p)
    }
  }
  if closed {
    while kept.length() > 1 &&
          kept[kept.length() - 1].distance_squared(kept[0]) <=
          coincident * coincident {
      let _ = kept.pop()
    }
  }
  kept
}

///|
/// The unit direction of each segment; a closed contour gets one more than an
/// open one, the last closing the loop.
fn directions(points : Array[Vec2], closed : Bool) -> Array[Vec2] {
  let out : Array[Vec2] = []
  let count = points.length()
  let last = if closed { count } else { count - 1 }
  for i in 0..<last {
    let next = points[(i + 1) % count]
    out.push((next - points[i]).normalize())
  }
  out
}

///|
/// Points along an arc, neither end included.
fn arc_points(
  centre : Vec2,
  radius : Float,
  start : Float,
  sweep : Float,
  tolerance : Float,
  into : Array[Vec2],
) -> Unit {
  let step = arc_step(radius, tolerance)
  let count = (sweep.abs() / step).ceil().to_int()
  let count = if count < 1 { 1 } else { count }
  let delta = sweep / as_float(count)
  for i in 1..<count {
    let angle = start + delta * as_float(i)
    into.push(
      Vec2::new(
        centre.x + radius * @math.cosf(angle),
        centre.y + radius * @math.sinf(angle),
      ),
    )
  }
}

///|
/// The angle from `a` to `b`, taken the short way, in (-π, π].
fn shortest_sweep(a : Float, b : Float) -> Float {
  let mut sweep : Float = b - a
  while sweep > half_turn {
    sweep = sweep - full_turn
  }
  while sweep <= -half_turn {
    sweep = sweep + full_turn
  }
  sweep
}

///|
/// The points one corner needs on one side of the line.
fn join_at(
  p : Vec2,
  before : Vec2,
  after : Vec2,
  side : Float,
  half : Float,
  style : Stroke,
  into : Array[Vec2],
) -> Unit {
  let n1 = perp(before).scale(side)
  let n2 = perp(after).scale(side)
  let denominator : Float = 1.0 + n1.dot(n2)
  if denominator < 1.0e-4 {
    // The line doubles back on itself; two points keep the outline a polygon.
    into.push(p + n1.scale(half))
    into.push(p + n2.scale(half))
    return
  }
  let meet = p + (n1 + n2).scale(half / denominator)
  let outer = before.cross(after) * side < 0.0
  if !outer {
    if meet.distance(p) > half * 2.0 {
      into.push(p + n1.scale(half))
      into.push(p + n2.scale(half))
    } else {
      into.push(meet)
    }
    return
  }
  match style.join {
    Bevel => {
      into.push(p + n1.scale(half))
      into.push(p + n2.scale(half))
    }
    Miter => {
      let cosine : Float = 1.0 + before.dot(after)
      let positive : Float = if cosine < 0.0 { 0.0 } else { cosine }
      let sine_half : Float = positive.sqrt() / 1.4142135
      let ratio : Float = 1.0 / sine_half
      if ratio <= style.miter_limit {
        into.push(meet)
      } else {
        into.push(p + n1.scale(half))
        into.push(p + n2.scale(half))
      }
    }
    Round => {
      let start = @math.atan2f(n1.y, n1.x)
      let end = @math.atan2f(n2.y, n2.x)
      arc_points(
        p,
        half,
        start,
        shortest_sweep(start, end),
        style.tolerance,
        into,
      )
      into.push(p + n2.scale(half))
    }
  }
}

///|
/// One side of the stroke along a polyline, joins included.
fn offset_side(
  points : Array[Vec2],
  dirs : Array[Vec2],
  closed : Bool,
  side : Float,
  style : Stroke,
  into : Array[Vec2],
) -> Unit {
  let half : Float = style.width / 2.0
  let count = points.length()
  for i in 0..<count {
    let p = points[i]
    if closed {
      join_at(
        p,
        dirs[(i + count - 1) % count],
        dirs[i],
        side,
        half,
        style,
        into,
      )
    } else if i == 0 {
      into.push(p + perp(dirs[0]).scale(side * half))
    } else if i == count - 1 {
      into.push(p + perp(dirs[count - 2]).scale(side * half))
    } else {
      join_at(p, dirs[i - 1], dirs[i], side, half, style, into)
    }
  }
}

///|
/// The points a cap needs, in the order the outline visits them: from the left
/// side to the right side at the far end, and back the other way at the start.
fn cap_points(
  p : Vec2,
  dir : Vec2,
  half : Float,
  style : Stroke,
  at_start : Bool,
  into : Array[Vec2],
) -> Unit {
  let normal = perp(dir)
  let forward = if at_start { dir.scale(-1.0) } else { dir }
  // The outline arrives at the cap from one side and leaves on the other, so the
  // order of the points depends on which end this is: taking the sides in the
  // wrong order would cross the stroke and leave a crack through it.
  let first : Float = if at_start { -1.0 } else { 1.0 }
  match style.cap {
    Butt => ()
    Square => {
      into.push(p + normal.scale(half * first) + forward.scale(half))
      into.push(p - normal.scale(half * first) + forward.scale(half))
    }
    Round => {
      let start_point = p + normal.scale(half * first)
      let finish = p - normal.scale(half * first)
      let start = @math.atan2f(start_point.y - p.y, start_point.x - p.x)
      arc_points(p, half, start, -half_turn, style.tolerance, into)
      into.push(finish)
    }
  }
}

///|
/// The outlines of a stroked polyline.
///
/// A closed contour becomes two loops, one down each side, wound opposite ways:
/// filling both with the non-zero rule leaves the ring between them and nothing
/// else, and there is no seam to cross. An open one becomes a single loop that
/// walks one side, round the end cap, back along the other side and round the
/// start cap.
fn outlines(
  points : Array[Vec2],
  closed : Bool,
  style : Stroke,
  into : Array[Contour],
) -> Unit {
  let dirs = directions(points, closed)
  if dirs.length() == 0 {
    return
  }
  let half = style.width / 2.0
  let left : Array[Vec2] = []
  let right : Array[Vec2] = []
  offset_side(points, dirs, closed, 1.0, style, left)
  offset_side(points, dirs, closed, -1.0, style, right)
  if closed {
    into.push({ points: left, closed: true, })
    let reversed : Array[Vec2] = []
    for i in 1..<=right.length() {
      reversed.push(right[right.length() - i])
    }
    into.push({ points: reversed, closed: true, })
    return
  }
  let poly : Array[Vec2] = []
  for p in left {
    poly.push(p)
  }
  cap_points(
    points[points.length() - 1],
    dirs[dirs.length() - 1],
    half,
    style,
    false,
    poly,
  )
  for i in 1..<=right.length() {
    poly.push(right[right.length() - i])
  }
  cap_points(points[0], dirs[0], half, style, true, poly)
  into.push({ points: poly, closed: true, })
}

///|
/// The stroke drawn along `path`, as triangles covering exactly the inked area.
///
/// The outline is built first — both sides of the line, with its joins and caps —
/// and then filled with the non-zero rule, which is what makes a tight corner or
/// a self-crossing path come out right instead of being inked twice.
pub fn stroke(
  path : Path,
  style : Stroke,
  flatten~ : Flatten = standard,
) -> Array[Triangle] {
  if style.width <= 0.0 {
    return []
  }
  let tolerance : Flatten = if style.tolerance < flatten.tolerance {
    Flatten::new(style.tolerance)
  } else {
    flatten
  }
  let contours = path.flatten(flatten=tolerance)
  let outlines_out : Array[Contour] = []
  for contour in contours {
    let points = clean_points(contour.points, contour.closed)
    if points.length() < 2 {
      continue
    }
    if style.dash.length() > 0 {
      for
        run in dash_runs(points, contour.closed, style.dash, style.dash_offset) {
        outlines(run, false, style, outlines_out)
      }
    } else {
      outlines(points, contour.closed, style, outlines_out)
    }
  }
  fill_contours(outlines_out, NonZero)
}
