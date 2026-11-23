// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// An axis-aligned rectangle in drawing space, kept as its two corners so that a
/// box accumulates points without needing a normalised form.
///
/// An empty box has `min_x > max_x`; `Bounds::nothing` builds one. Points are
/// only added while flattening, so the empty box never reaches a rasteriser.
#derive(Debug, Eq)
pub(all) struct Bounds {
  min_x : Float
  min_y : Float
  max_x : Float
  max_y : Float
}

///|
/// The box that holds nothing.
pub fn Bounds::nothing() -> Bounds {
  {
    min_x: @float.infinity,
    min_y: @float.infinity,
    max_x: @float.neg_infinity,
    max_y: @float.neg_infinity,
  }
}

///|
/// Whether the box still holds nothing.
pub fn Bounds::is_empty(self : Bounds) -> Bool {
  self.min_x > self.max_x || self.min_y > self.max_y
}

///|
/// The box grown to hold `p`.
pub fn Bounds::add_point(self : Bounds, p : Vec2) -> Bounds {
  {
    min_x: if p.x < self.min_x {
      p.x
    } else {
      self.min_x
    },
    min_y: if p.y < self.min_y {
      p.y
    } else {
      self.min_y
    },
    max_x: if p.x > self.max_x {
      p.x
    } else {
      self.max_x
    },
    max_y: if p.y > self.max_y {
      p.y
    } else {
      self.max_y
    },
  }
}

///|
/// The smallest box holding both.
pub fn Bounds::union(self : Bounds, other : Bounds) -> Bounds {
  if other.is_empty() {
    self
  } else if self.is_empty() {
    other
  } else {
    {
      min_x: if other.min_x < self.min_x {
        other.min_x
      } else {
        self.min_x
      },
      min_y: if other.min_y < self.min_y {
        other.min_y
      } else {
        self.min_y
      },
      max_x: if other.max_x > self.max_x {
        other.max_x
      } else {
        self.max_x
      },
      max_y: if other.max_y > self.max_y {
        other.max_y
      } else {
        self.max_y
      },
    }
  }
}

///|
/// The box grown by `amount` on every side; a negative amount shrinks it.
pub fn Bounds::expand(self : Bounds, amount : Float) -> Bounds {
  {
    min_x: self.min_x - amount,
    min_y: self.min_y - amount,
    max_x: self.max_x + amount,
    max_y: self.max_y + amount,
  }
}

///|
pub fn Bounds::width(self : Bounds) -> Float {
  self.max_x - self.min_x
}

///|
pub fn Bounds::height(self : Bounds) -> Float {
  self.max_y - self.min_y
}

///|
/// The point in the middle; the zero vector for an empty box.
pub fn Bounds::centre(self : Bounds) -> Vec2 {
  if self.is_empty() {
    Vec2::zero()
  } else {
    Vec2::new((self.min_x + self.max_x) * 0.5, (self.min_y + self.max_y) * 0.5)
  }
}

///|
/// The overlap of two boxes, empty when they miss each other.
pub fn Bounds::intersect(self : Bounds, other : Bounds) -> Bounds {
  let min_x = if self.min_x > other.min_x { self.min_x } else { other.min_x }
  let min_y = if self.min_y > other.min_y { self.min_y } else { other.min_y }
  let max_x = if self.max_x < other.max_x { self.max_x } else { other.max_x }
  let max_y = if self.max_y < other.max_y { self.max_y } else { other.max_y }
  { min_x, min_y, max_x, max_y, }
}

///|
/// Whether `p` lies in the box, borders included.
pub fn Bounds::contains(self : Bounds, p : Vec2) -> Bool {
  p.x >= self.min_x &&
  p.x <= self.max_x &&
  p.y >= self.min_y &&
  p.y <= self.max_y
}

///|
/// The squared distance from `p` to the segment `a`–`b`.
fn distance_to_segment_squared(p : Vec2, a : Vec2, b : Vec2) -> Float {
  let dx = b.x - a.x
  let dy = b.y - a.y
  let len = dx * dx + dy * dy
  let t : Float = if len <= 0.0 {
    0.0
  } else {
    let raw = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len
    if raw < 0.0 {
      0.0
    } else if raw > 1.0 {
      1.0
    } else {
      raw
    }
  }
  let x = a.x + dx * t - p.x
  let y = a.y + dy * t - p.y
  x * x + y * y
}

///|
/// Whether `p` is close enough to the line through `a` and `b` to be treated as
/// lying on it, which is what decides that a curve is flat.
fn off_line(p : Vec2, a : Vec2, b : Vec2, tolerance : Float) -> Bool {
  distance_to_segment_squared(p, a, b) > tolerance * tolerance
}
