// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Add a point unless it repeats the last one, which happens where two segments
/// meet inside one dash.
fn push_unique(points : Array[Vec2], p : Vec2) -> Unit {
  if points.length() > 0 &&
    points[points.length() - 1].distance_squared(p) <= 1.0e-12 {
    return
  }
  points.push(p)
}

///|
/// The pattern with the values that carry no ink removed, doubled when its length
/// is odd so that on and off still alternate over a repeat.
fn normalise_dashes(pattern : Array[Float]) -> Array[Float] {
  let cleaned : Array[Float] = []
  for length in pattern {
    if length > 0.0 && length.is_finite() {
      cleaned.push(length)
    }
  }
  if cleaned.length() == 0 {
    return cleaned
  }
  if cleaned.length() % 2 == 1 {
    cleaned.push(cleaned[0])
  }
  cleaned
}

///|
/// The parts of a polyline that are inked, each an open run of points.
///
/// A run is a maximal stretch of the line where the dash pattern is on, cut at
/// the pattern's boundaries rather than snapped to the polyline's own points, so
/// the lengths are exact to the last bit of the arithmetic.
fn dash_runs(
  points : Array[Vec2],
  closed : Bool,
  pattern : Array[Float],
  offset : Float,
) -> Array[Array[Vec2]] {
  let runs : Array[Array[Vec2]] = []
  let lengths = normalise_dashes(pattern)
  if lengths.length() == 0 {
    return runs
  }
  let mut total : Float = 0.0
  for length in lengths {
    total = total + length
  }
  if total <= 0.0 {
    return runs
  }
  let mut phase = 0
  let mut remaining = lengths[0]
  let mut shift = offset
  while shift > total {
    shift = shift - total
  }
  while shift < 0.0 {
    shift = shift + total
  }
  while shift > 0.0 {
    if shift >= remaining {
      shift = shift - remaining
      phase = (phase + 1) % lengths.length()
      remaining = lengths[phase]
    } else {
      remaining = remaining - shift
      shift = 0.0
    }
  }
  let mut on = phase % 2 == 0
  let mut current : Array[Vec2] = []
  let segments = if closed { points.length() } else { points.length() - 1 }
  for i in 0..<segments {
    let p = points[i]
    let q = points[(i + 1) % points.length()]
    let delta = q - p
    let length = delta.length()
    if length <= 0.0 {
      continue
    }
    let unit = delta.scale(1.0 / length)
    let mut walked : Float = 0.0
    while walked < length - 1.0e-6 {
      let take = if remaining < length - walked {
        remaining
      } else {
        length - walked
      }
      let a = p + unit.scale(walked)
      let b = p + unit.scale(walked + take)
      if on {
        push_unique(current, a)
        push_unique(current, b)
      }
      walked = walked + take
      remaining = remaining - take
      if remaining <= 1.0e-6 {
        if on && current.length() >= 2 {
          runs.push(current)
          current = []
        }
        phase = (phase + 1) % lengths.length()
        remaining = lengths[phase]
        on = phase % 2 == 0
      }
    }
  }
  if on && current.length() >= 2 {
    runs.push(current)
  }
  runs
}
